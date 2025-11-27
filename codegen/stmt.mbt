///|
pub fn Context::stmt_codegen(self : Self, stmt : @knf.KnfStmt) -> Unit raise {
  match stmt {
    Let(name, ty, expr) => self.let_stmt_codegen(name, ty, expr)
    LetMut(name, ty, expr) => self.let_mut_stmt_codegen(name, ty, expr)
    Assign(name, expr) => self.assign_stmt_codegen(name, expr)
    ArrayPut(name, idx, expr) => self.array_put_codegen(name, idx, expr)
    StructFieldSet(struct_name, field_name, value_name) =>
      self.struct_field_set_codegen(struct_name, field_name, value_name)
    While(cond_block, body_block) => {
      let current_func = self.builder.getInsertFunction()
      // Don't specify names to avoid conflicts in nested loops
      let cond_bb = current_func.addBasicBlock()
      let body_bb = current_func.addBasicBlock()
      let merge_bb = current_func.addBasicBlock()

      let _ = self.builder.createBr(cond_bb)

      self.builder.setInsertPoint(cond_bb)
      // Generate condition statements directly without creating extra blocks
      let mut cond_value : &@llvm.Value? = None
      let mut i = 0
      while i < cond_block.stmts.length() {
        let stmt = cond_block.stmts[i]
        match stmt {
          @knf.KnfStmt::ExprStmt(expr) => {
            cond_value = self.expr_codegen(expr)
          }
          _ => self.stmt_codegen(stmt)
        }
        i = i + 1
      }
      let cond_val = match cond_value {
        Some(value) => value
        None => raise CodegenError("While condition must produce a value")
      }
      let _ = self.builder.createCondBr(cond_val, body_bb, merge_bb)

      self.builder.setInsertPoint(body_bb)
      // Generate body statements directly without creating extra blocks
      let mut j = 0
      while j < body_block.stmts.length() {
        let current_bb = self.builder.getInsertBlock()
        if current_bb.getTerminator() is Some(_) {
          break
        }
        self.stmt_codegen(body_block.stmts[j])
        j = j + 1
      }
      let final_bb = self.builder.getInsertBlock()
      match final_bb.getTerminator() {
        Some(_) => ()
        None => { let _ = self.builder.createBr(cond_bb) }
      }

      self.builder.setInsertPoint(merge_bb)
    }
    ExprStmt(expr) => {
      // Execute the expression for its side effects
      let _ = self.expr_codegen(expr)
    }
    Return(expr) =>
      match self.expr_codegen(expr) {
        Some(value) => {
          let _ = self.builder.createRet(value)

        }
        None => {
          let _ = self.builder.createRetVoid()

        }
      }
    ReturnUnit => {
      let _ = self.builder.createRetVoid()

    }
    ClosureDef(closure_def) => self.closure_codegen(closure_def)
  }
}

///|
pub fn Context::let_stmt_codegen(
  self : Self,
  name : @knf.Name,
  ty : @knf.Type,
  expr : @knf.KnfExpr,
) -> Unit raise {
  match self.expr_codegen(expr) {
    Some(value) => {
      // For enum types extracted from field access, we need to ensure
      // the value can be used for subsequent field access operations
      match ty {
        @knf.Type::Enum(_) => {
          // Check if this is a field access expression
          match expr {
            @knf.KnfExpr::FieldAccess(_, _) => {
              // Allocate storage and store the enum pointer
              let llvm_ty = self.type_codegen_opaque(ty)
              let alloca = self.builder.createAlloca(llvm_ty)
              let _ = self.builder.createStore(value, alloca)
              self.name_values.set(name, alloca)
              self.name_types.set(name, ty)
            }
            _ => {
              self.name_values.set(name, value)
              self.name_types.set(name, ty)
            }
          }
        }
        _ => {
          self.name_values.set(name, value)
          self.name_types.set(name, ty)
        }
      }
    }
    None => {
      let null_value = self.llvm_ctx.getConstPointerNull(
        self.llvm_ctx.getPtrTy(),
      )
      self.name_values.set(name, null_value)
      self.name_types.set(name, ty)
    }
  }
}

///|
pub fn Context::let_mut_stmt_codegen(
  self : Self,
  name : @knf.Name,
  ty : @knf.Type,
  expr : @knf.KnfExpr,
) -> Unit raise {
  let llvm_ty = self.type_codegen_opaque(ty)
  let alloc = self.builder.createAlloca(llvm_ty)
  match self.expr_codegen(expr) {
    Some(value) => {
      let _ = self.builder.createStore(value, alloc)

    }
    None => {
      let _ = self.builder.createStore(
        self.llvm_ctx.getConstPointerNull(self.llvm_ctx.getPtrTy()),
        alloc,
      )

    }
  }
  self.name_values.set(name, alloc)
  self.name_types.set(name, ty)
  self.mutable_names.add(name)  // 标记为可变变量
}

///|  
pub fn Context::assign_stmt_codegen(
  self : Self,
  name : @knf.Name,
  expr : @knf.KnfExpr,
) -> Unit raise {
  // 首先检查变量是否被声明为可变
  if !self.mutable_names.contains(name) {
    raise CodegenError("Assign target is not mutable: " + name.to_string())
  }
  
  // 直接从name_values获取指针，这是关键！
  // 对于可变变量，name_values中存储的是指针
  let target_ptr = match self.name_values.get(name) {
    Some(ptr) => ptr
    None => raise CodegenError("Unknown assign target: " + name.to_string())
  }
  let value = match self.expr_codegen(expr) {
    Some(v) => v
    None =>
      // If the expression is Unit (represented by None here), allow assignment
      // only if the target variable's type is Unit. In that case there is
      // nothing to store; just return early. Otherwise it's an error.
      match self.name_types.get(name) {
        Some(@knf.Type::Unit) => return
        _ => raise CodegenError(
          "Cannot assign Unit value to variable: " + name.to_string(),
        )
      }
  }
  
  // 对于可变变量，无论是局部的AllocaInst还是从闭包捕获的指针
  // 我们都需要直接存储值到这个指针
  // 这确保了闭包中修改的可变变量能够正确地反映到外部作用域
  let _ = self.builder.createStore(value, target_ptr)
}

///|
pub fn Context::array_put_codegen(
  self : Self,
  name : @knf.Name,
  idx : @knf.Name,
  expr : @knf.KnfExpr,
) -> Unit raise {
  let array_ptr = self.resolve_value(name)
  let index_value = self.resolve_value(idx)
  let value = match self.expr_codegen(expr) {
    Some(v) => v
    None => raise CodegenError("Cannot store Unit value into array")
  }
  let array_ty = match self.name_types.get(name) {
    Some(ty) => ty
    None => raise CodegenError("Unknown array in ArrayPut: " + name.to_string())
  }
  let element_ty = match array_ty {
    @knf.Type::Array(elem) => elem
    _ => raise CodegenError("ArrayPut target is not an array")
  }
  // Use GEP + store instead of function call
  let elem_llvm_ty : &@llvm.Type = match element_ty {
    @knf.Type::Int => (self.llvm_ctx.getInt32Ty() : &@llvm.Type)
    @knf.Type::Double => (self.llvm_ctx.getDoubleTy() : &@llvm.Type)
    @knf.Type::Bool => (self.llvm_ctx.getInt1Ty() : &@llvm.Type)
    _ => (self.llvm_ctx.getPtrTy() : &@llvm.Type)
  }
  let elem_ptr = self.builder.createGEP(array_ptr, elem_llvm_ty, [index_value])
  let _ = self.builder.createStore(value, elem_ptr)

}

///|
pub fn Context::struct_field_set_codegen(
  self : Self,
  name : @knf.Name,
  field : String,
  value_name : @knf.Name,
) -> Unit raise {
  let (field_ptr, field_ty) = self.struct_field_ptr_and_type(name, field)
  let value = self.resolve_value(value_name)
  match field_ty {
    @knf.Type::Unit =>
      raise CodegenError("Cannot store Unit value in struct field")
    _ => ()
  }
  let _ = self.builder.createStore(value, field_ptr)

}
