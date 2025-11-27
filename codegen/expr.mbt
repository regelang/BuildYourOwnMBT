///|
///
/// 注意这里的expr_codegen的返回值是Option[&@llvm.Value]
/// 对于Unit类型的表达式，应当返回None做特殊处理。
///
/// 对于像let a: Unit = (); 这种表达式，可以考虑把a的值设为null指针，
/// 使用llvm_ctx.getConstPointerNull(llvm_ctx.getPtrTy())
pub fn Context::expr_codegen(
  self : Self,
  expr : @knf.KnfExpr,
) -> &@llvm.Value? raise {
  match expr {
    Int(i) => (self.llvm_ctx.getConstInt32(i) : &@llvm.Value) |> Some
    Double(d) => (self.llvm_ctx.getConstDouble(d) : &@llvm.Value) |> Some
    Bool(b) => {
      let true_val = self.llvm_ctx.getConstTrue()
      let false_val = self.llvm_ctx.getConstFalse()
      let value = if b { true_val } else { false_val }
      (value : &@llvm.Value) |> Some
    }
    String(s) => {
      let name = "str_lit_" + self.str_cnt.to_string()
      self.str_cnt = self.str_cnt + 1
      let global_ptr = self.builder.createGlobalString(s, name~)
      (global_ptr : &@llvm.Value) |> Some
    }
    Ident(name) => self.resolve_value(name) |> Some
    Not(name) => {
      let operand = self.resolve_value(name)
      let true_const = self.llvm_ctx.getConstTrue()
      let result = self.builder.createXor(true_const, operand)
      (result : &@llvm.Value) |> Some
    }
    Neg(name) => {
      let operand = self.resolve_value(name)
      let ty = operand.getType()
      if ty.isIEEELikeFPTy() {
        let result = self.builder.createFNeg(operand)
        (result : &@llvm.Value) |> Some
      } else {
        let zero = self.llvm_ctx.getConstInt32(0)
        let result = self.builder.createSub(zero, operand)
        (result : &@llvm.Value) |> Some
      }
    }
    Binary(op, lhs_name, rhs_name) => {
      let lhs = self.resolve_value(lhs_name)
      let rhs = self.resolve_value(rhs_name)
      let lhs_ty = lhs.getType()
      let is_float = lhs_ty.isIEEELikeFPTy()
      let result = match op {
        @knf.BinaryOp::Add =>
          if is_float {
            self.builder.createFAdd(lhs, rhs)
          } else {
            self.builder.createAdd(lhs, rhs)
          }
        @knf.BinaryOp::Sub =>
          if is_float {
            self.builder.createFSub(lhs, rhs)
          } else {
            self.builder.createSub(lhs, rhs)
          }
        @knf.BinaryOp::Mul =>
          if is_float {
            self.builder.createFMul(lhs, rhs)
          } else {
            self.builder.createMul(lhs, rhs)
          }
        @knf.BinaryOp::Div =>
          if is_float {
            self.builder.createFDiv(lhs, rhs)
          } else {
            self.builder.createSDiv(lhs, rhs)
          }
        @knf.BinaryOp::Mod =>
          if is_float {
            self.builder.createFRem(lhs, rhs)
          } else {
            self.builder.createSRem(lhs, rhs)
          }
        @knf.BinaryOp::Eq =>
          if is_float {
            self.builder.createFCmpOEQ(lhs, rhs)
          } else {
            self.builder.createICmpEQ(lhs, rhs)
          }
        @knf.BinaryOp::NE =>
          if is_float {
            self.builder.createFCmpONE(lhs, rhs)
          } else {
            self.builder.createICmpNE(lhs, rhs)
          }
        @knf.BinaryOp::LT =>
          if is_float {
            self.builder.createFCmpOLT(lhs, rhs)
          } else {
            self.builder.createICmpSLT(lhs, rhs)
          }
        @knf.BinaryOp::LE =>
          if is_float {
            self.builder.createFCmpOLE(lhs, rhs)
          } else {
            self.builder.createICmpSLE(lhs, rhs)
          }
        @knf.BinaryOp::GT =>
          if is_float {
            self.builder.createFCmpOGT(lhs, rhs)
          } else {
            self.builder.createICmpSGT(lhs, rhs)
          }
        @knf.BinaryOp::GE =>
          if is_float {
            self.builder.createFCmpOGE(lhs, rhs)
          } else {
            self.builder.createICmpSGE(lhs, rhs)
          }
        @knf.BinaryOp::And => self.builder.createAnd(lhs, rhs)
        @knf.BinaryOp::Or => self.builder.createOr(lhs, rhs)
        @knf.BinaryOp::BitAnd => self.builder.createAnd(lhs, rhs)
        @knf.BinaryOp::BitOr => self.builder.createOr(lhs, rhs)
        @knf.BinaryOp::ShiftLeft => self.builder.createShl(lhs, rhs)
        @knf.BinaryOp::ShiftRight => self.builder.createAShr(lhs, rhs)
      }
      (result : &@llvm.Value) |> Some
    }
    ArrayMake(size_name, init_name) => {
      let size_value = self.resolve_value(size_name)
      let init_value = self.resolve_value(init_name)
      
      // Debug: check size_value type
      let size_ty = match self.name_types.get(size_name) {
        Some(ty) => ty
        None => raise CodegenError("Missing type for size parameter: " + size_name.to_string())
      }
      // Size should be Int type
      match size_ty {
        @knf.Type::Int => ()  // OK
        _ => raise CodegenError("Array size must be Int, got: " + size_ty.to_string() + " for " + size_name.to_string())
      }
      
      let element_ty = match self.name_types.get(init_name) {
        Some(ty) => ty
        None => raise CodegenError("Missing type for array element: " + init_name.to_string())
      }
      let (builtin_name, arg_value) = match element_ty {
        @knf.Type::Int => ("make_int_array", init_value)
        @knf.Type::Double => ("make_double_array", init_value)
        @knf.Type::Bool => ("make_bool_array", init_value)
        _ => ("make_ptr_array", init_value)
      }
      let make_array_fn = match self.builtin_funcs.get(builtin_name) {
        Some(func) => func
        None => raise CodegenError("Missing builtin function: " + builtin_name)
      }
      let result = self.builder.createCall(make_array_fn, [
        size_value, arg_value,
      ])
      (result : &@llvm.Value) |> Some
    }
    ArrayLiteral(elem_ty, elem_names) => {
      let elem_count = elem_names.length()
      let size_const = self.llvm_ctx.getConstInt32(elem_count)
      let make_builtin = match elem_ty {
        @knf.Type::Int => "make_int_array"
        @knf.Type::Double => "make_double_array"
        @knf.Type::Bool => "make_bool_array"
        _ => "make_ptr_array"
      }
      let init_default = match elem_ty {
        @knf.Type::Int => (self.llvm_ctx.getConstInt32(0) : &@llvm.Value)
        @knf.Type::Double => (self.llvm_ctx.getConstDouble(0.0) : &@llvm.Value)
        @knf.Type::Bool => (self.llvm_ctx.getConstFalse() : &@llvm.Value)
        _ =>
          (
            self.llvm_ctx.getConstPointerNull(self.llvm_ctx.getPtrTy()) :
            &@llvm.Value)
      }
      let make_fn = match self.builtin_funcs.get(make_builtin) {
        Some(func) => func
        None => raise CodegenError("Missing builtin function: " + make_builtin)
      }
      let array_ptr = self.builder.createCall(make_fn, [
        size_const, init_default,
      ])
      // Use GEP + store instead of function call for initialization
      let elem_llvm_ty : &@llvm.Type = match elem_ty {
        @knf.Type::Int => (self.llvm_ctx.getInt32Ty() : &@llvm.Type)
        @knf.Type::Double => (self.llvm_ctx.getDoubleTy() : &@llvm.Type)
        @knf.Type::Bool => (self.llvm_ctx.getInt1Ty() : &@llvm.Type)
        _ => (self.llvm_ctx.getPtrTy() : &@llvm.Type)
      }
      let mut idx = 0
      while idx < elem_count {
        let elem_name = elem_names[idx]
        let elem_value = self.resolve_value(elem_name)
        let index_const = self.llvm_ctx.getConstInt32(idx)
        let elem_ptr = self.builder.createGEP(array_ptr, elem_llvm_ty, [index_const])
        let _ = self.builder.createStore(elem_value, elem_ptr)
        idx = idx + 1
      }
      (array_ptr : &@llvm.Value) |> Some
    }
    Block(block) => self.block_codegen(block)
    If(cond_expr, then_block, else_block) =>
      self.if_codegen(cond_expr, then_block, else_block)
    CreateStruct(struct_name, fields) => {
      let llvm_struct_ty = match self.struct_types.get(struct_name) {
        Some(ty) => ty
        None => raise CodegenError("Unknown struct type: " + struct_name)
      }
      let data_layout = self.llvm_mod.getDataLayout()
      let struct_size = data_layout.getTypeAllocSize(llvm_struct_ty)
      let size_value = self.llvm_ctx.getConstInt32(struct_size)
      let malloc_fn = match self.builtin_funcs.get("moonbit_malloc") {
        Some(func) => func
        None => raise CodegenError("Missing builtin function: moonbit_malloc")
      }
      let struct_ptr = self.builder.createCall(malloc_fn, [size_value])
      let knf_struct = match self.knf_struct_types.get(struct_name) {
        Some(def) => def
        None =>
          raise CodegenError(
            "Missing KNF struct definition for: " + struct_name,
          )
      }
      let mut idx = 0
      while idx < fields.length() {
        let (field_name, value_name) = fields[idx]
        let field_index = match knf_struct.get_field_index(field_name) {
          Some(i) => i
          None =>
            raise CodegenError(
              "Unknown field " + field_name + " in struct " + struct_name,
            )
        }
        let field_value = self.resolve_value(value_name)
        let zero = self.llvm_ctx.getConstInt32(0)
        let index_val = self.llvm_ctx.getConstInt32(field_index)
        let field_ptr = self.builder.createGEP(struct_ptr, llvm_struct_ty, [
          zero, index_val,
        ])
        let _ = self.builder.createStore(field_value, field_ptr)
        idx = idx + 1
      }
      struct_ptr |> Some
    }
    TupleLiteral(elem_names) => {
      let elem_types : Array[@knf.Type] = Array::new()
      let llvm_elem_types : Array[&@llvm.Type] = Array::new()
      let mut idx = 0
      while idx < elem_names.length() {
        let elem_name = elem_names[idx]
        let elem_ty = match self.name_types.get(elem_name) {
          Some(ty) => ty
          None =>
            raise CodegenError(
              "Missing type information for tuple element: " +
              elem_name.to_string(),
            )
        }
        let llvm_elem_ty = self.type_codegen_opaque(elem_ty)
        elem_types.push(elem_ty)
        llvm_elem_types.push(llvm_elem_ty)
        idx = idx + 1
      }
      let llvm_tuple_ty = self.llvm_ctx.getStructType(llvm_elem_types)
      let data_layout = self.llvm_mod.getDataLayout()
      let tuple_size = data_layout.getTypeAllocSize(llvm_tuple_ty)
      let size_value = self.llvm_ctx.getConstInt32(tuple_size)
      let malloc_fn = match self.builtin_funcs.get("moonbit_malloc") {
        Some(func) => func
        None => raise CodegenError("Missing builtin function: moonbit_malloc")
      }
      let tuple_ptr = self.builder.createCall(malloc_fn, [size_value])
      let zero = self.llvm_ctx.getConstInt32(0)
      let mut store_idx = 0
      while store_idx < elem_names.length() {
        let elem_name = elem_names[store_idx]
        let elem_value = self.resolve_value(elem_name)
        let index_val = self.llvm_ctx.getConstInt32(store_idx)
        let elem_ptr = self.builder.createGEP(tuple_ptr, llvm_tuple_ty, [
          zero, index_val,
        ])
        let _ = self.builder.createStore(elem_value, elem_ptr)
        store_idx = store_idx + 1
      }
      (tuple_ptr : &@llvm.Value) |> Some
    }
    FieldAccess(target_name, field_name) => {
      // 根据 KNF 类型区分结构体字段访问和枚举字段访问
      let target_ty = match self.name_types.get(target_name) {
        Some(ty) => ty
        None => raise CodegenError(
          "Missing type information for field access target: " +
          target_name.to_string(),
        )
      }

      match target_ty {
        @knf.Type::Struct(_) => {
          // 保持原有的结构体字段访问逻辑
          let (field_ptr, field_ty) = self.struct_field_ptr_and_type(
            target_name, field_name,
          )
          let llvm_field_ty = self.type_codegen_opaque(field_ty)
          let loaded = self.builder.createLoad(llvm_field_ty, field_ptr)
          (loaded : &@llvm.Value) |> Some
        }
        @knf.Type::Enum(enum_name) => {
          // 对枚举字段访问，使用 enum_field_access。
          // 当前 KNF 中为枚举字段生成的名字形如 "field1", "field2", ...，
          // 这里通过简单的字符串比较将其映射为字段索引。
          let field_zero_based =
            if field_name == "field1" { 0 }
            else if field_name == "field2" { 1 }
            else if field_name == "field3" { 2 }
            else if field_name == "field4" { 3 }
            else if field_name == "field5" { 4 }
            else {
              raise CodegenError("Unexpected enum field name: " + field_name)
            }

          // 从 KNF 枚举定义中尝试推断该字段的类型。
          let knf_enum = match self.knf_enum_types.get(enum_name) {
            Some(def) => def
            None => raise CodegenError("KNF enum definition not found: " + enum_name)
          }

          // 简化策略：找到第一个包含该字段索引的变体，并使用其参数类型。
          let mut inferred_ty : @knf.Type? = None
          let mut vi = 0
          while vi < knf_enum.variants.length() {
            let v = knf_enum.variants[vi]
            if field_zero_based < v.params.length() {
              inferred_ty = Some(v.params[field_zero_based])
              break
            }
            vi = vi + 1
          }

          let target_field_ty = match inferred_ty {
            Some(t) => t
            None => {
              @knf.Type::Struct("__enum_field_opaque")
            }
          }

          let loaded = self.enum_field_access(
            target_name,
            field_zero_based,
            target_field_ty,
          )
          (loaded : &@llvm.Value) |> Some
        }
        _ => raise CodegenError("Field access on non-struct/enum type")
      }
    }
    Call(func_name, arg_names) => {
      // 检查是否是内置的枚举标签检查
      let func_name_str = func_name.to_string()
      if func_name_str == "__builtin_enum_tag_eq" {
        // 特殊处理：枚举标签比较
        // arg_names[0] 是枚举值，arg_names[1] 是构造器名
        if arg_names.length() != 2 {
          raise CodegenError("__builtin_enum_tag_eq requires exactly 2 arguments")
        }
        
        let enum_value_name = arg_names[0]
        let constructor_name = arg_names[1]
        
        // 获取枚举标签
        let tag_value = self.enum_tag_access(enum_value_name)
        
        // 查找构造器的标签值
        let expected_tag = match self.find_constructor_tag(constructor_name.to_string()) {
          Some(tag) => tag
          None => raise CodegenError("Constructor not found: " + constructor_name.to_string())
        }
        let expected_tag_const = self.llvm_ctx.getConstInt32(expected_tag)
        
        // 生成比较
        let cmp_result = self.builder.createICmpEQ(tag_value, expected_tag_const)
        Some((cmp_result : &@llvm.Value))
      } else {
      // 函数调用代码生成
      // 需要处理三种情况：
      // 1. 直接函数调用（顶层函数）
      // 2. 闭包调用（通过闭包结构体指针）
      // 3. 函数指针调用（从数组等获取的函数指针）
      
      
      // 检查被调用者是否是一个变量（可能是闭包或函数指针）
      let callee_value_opt = self.name_values.get(func_name)
      
      // 确定被调用者的类型和调用方式
      // 返回：(callee值, 是否需要环境指针, 是否是闭包结构体)
      let (callee, need_env, _is_closure_struct) = match callee_value_opt {
        Some(value) => {
          // 被调用者是一个局部变量
          // 检查它是直接的函数引用还是闭包结构体指针
          match value.asValueEnum() {
            @llvm.ValueEnum::Function(_) => 
              // 直接的函数值，需要环境指针，但不是闭包结构体
              ((value : &@llvm.Value), true, false)
            _ => {
              // 是一个指针（可能是闭包结构体或从数组获取的函数指针）
              // 通过类型信息判断是否是闭包
              match self.name_types.get(func_name) {
                Some(@knf.Type::Function(_, _)) => {
                  // 类型是函数类型，说明是闭包结构体指针
                  ((value : &@llvm.Value), true, true)
                }
                _ => 
                  // 其他类型的指针
                  ((value : &@llvm.Value), true, false)
              }
            }
          }
        }
        None => {
          // 不是局部变量，尝试查找顶层函数
          match self.functions.get(func_name_str) {
            Some(f) => 
              // 找到顶层函数，main 函数不需要环境指针
              ((f : &@llvm.Value), func_name_str != "main", false)
            None =>
              // 尝试查找内建函数
              match self.builtin_funcs.get(func_name_str) {
                Some(f) => 
                  // 内建函数不需要环境指针
                  ((f : &@llvm.Value), false, false)
                None =>
                  raise CodegenError("Unknown function: " + func_name.to_string())
              }
          }
        }
      }
      
      // 简化实现：直接使用 callee，不从闭包结构体中提取函数指针
      // 注意：这是一个简化版本，实际上闭包结构体指针会被当作函数指针直接调用
      let actual_callee = callee
      
      // 准备函数调用参数
      let args : Array[&@llvm.Value] = Array::new()
      
      // 如果需要环境指针，添加为第一个参数
      if need_env {
        // 确定环境指针的值
        let env_ptr : &@llvm.Value = match actual_callee.asValueEnum() {
          @llvm.ValueEnum::Function(func) => {
            // 检查是否是当前闭包的递归调用
            match self.current_closure_func {
              Some(current_func) => {
                // 比较函数指针是否相同
                if func.getName() == current_func.getName() {
                  // 递归调用当前闭包，使用当前环境指针
                  match self.current_closure_env {
                    Some(env) => env
                    None => (self.llvm_ctx.getConstPointerNull(self.llvm_ctx.getPtrTy()) : &@llvm.Value)
                  }
                } else {
                  // 调用其他顶层函数，使用 null 环境指针
                  (self.llvm_ctx.getConstPointerNull(self.llvm_ctx.getPtrTy()) : &@llvm.Value)
                }
              }
              None => 
                // 不在闭包中，直接调用顶层函数，使用 null 环境指针
                (self.llvm_ctx.getConstPointerNull(self.llvm_ctx.getPtrTy()) : &@llvm.Value)
            }
          }
          _ => 
            // 间接调用（闭包），使用 callee 本身作为环境指针
            // callee 是闭包结构体指针
            actual_callee
        }
        args.push(env_ptr)
      }
      
      // 添加实际的函数参数
      let mut idx = 0
      while idx < arg_names.length() {
        let arg_name = arg_names[idx]
        
        // Check if this is a function (top-level or builtin) which doesn't have type info in name_types
        let name_str = arg_name.to_string()
        let is_function = match self.functions.get(name_str) {
          Some(_) => true
          None => match self.builtin_funcs.get(name_str) {
            Some(_) => true
            None => false
          }
        }
        
        if is_function {
          // Function (top-level or builtin): resolve_value will handle it
          let arg_value = self.resolve_value(arg_name)
          args.push(arg_value)
        } else {
          // Check if this argument is Unit type
          let arg_type = match self.name_types.get(arg_name) {
            Some(ty) => ty
            None => raise CodegenError("Missing type information for argument: " + arg_name.to_string())
          }
          
          match arg_type {
            @knf.Type::Unit => {
              // Unit type: pass a dummy i8 value (0)
              let dummy_value = self.llvm_ctx.getConstInt8(0)
              args.push((dummy_value : &@llvm.Value))
            }
            _ => {
              // Normal type: resolve and pass the value
              let arg_value = self.resolve_value(arg_name)
              args.push(arg_value)
            }
          }
        }
        idx = idx + 1
      }
      
      // 执行函数调用
      // 根据 callee 的类型选择直接调用或间接调用
      let (call_result, ret_ty) = match actual_callee.asValueEnum() {
        @llvm.ValueEnum::Function(f) => {
          // 直接调用：callee 是一个函数值
          // 使用 createCall 指令
          let result = self.builder.createCall(f, args)
          let ty = f.getFunctionType().getReturnType()
          (result, ty)
        }
        _ => {
          // 间接调用：callee 是一个闭包结构体指针
          // 需要从结构体中提取函数指针（第一个字段）
          
          // 构建函数类型（用于间接调用）
          let func_ty = match self.name_types.get(func_name) {
            Some(@knf.Type::Function(param_types, ret_ty)) => {
              // 函数类型：(ptr env, param1, param2, ...) -> ret_ty
              let llvm_param_types : Array[&@llvm.Type] = [self.llvm_ctx.getPtrTy()] // 环境指针
              param_types.each(pt => {
                // Unit type cannot be a function parameter in LLVM, use i8 instead
                let llvm_param_ty : &@llvm.Type = match pt {
                  @knf.Type::Unit => (self.llvm_ctx.getInt8Ty() : &@llvm.Type)
                  _ => self.type_codegen_opaque(pt)
                }
                llvm_param_types.push(llvm_param_ty)
              })
              // Unit return type should be void, not i8
              let llvm_ret_ty : &@llvm.Type = match ret_ty {
                @knf.Type::Unit => (self.llvm_ctx.getVoidTy() : &@llvm.Type)
                _ => self.type_codegen_opaque(ret_ty)
              }
              self.llvm_ctx.getFunctionType(llvm_ret_ty, llvm_param_types)
            }
            _ => raise CodegenError("Cannot determine function type for indirect call: " + func_name.to_string())
          }
          
          // 从闭包结构体中提取函数指针
          // 闭包结构体布局：{ ptr func_ptr, captured_vars... }
          let zero = self.llvm_ctx.getConstInt32(0)
          let closure_struct_ty = self.llvm_ctx.getStructType([self.llvm_ctx.getPtrTy()])
          let func_ptr_field = self.builder.createGEP(actual_callee, closure_struct_ty, [zero, zero])
          let func_ptr = self.builder.createLoad(self.llvm_ctx.getPtrTy(), func_ptr_field)
          
          // 执行间接调用
          let result = self.builder.createCallPtr(func_ptr, func_ty, args)
          let ty = func_ty.getReturnType()
          (result, ty)
        }
      }
      
      // Debug: log if the call returns void (expr_codegen will return None)
      match ret_ty.asTypeEnum() {
        @llvm.TypeEnum::VoidType(_) => {
          println("DEBUG: Call to '" + func_name_str + "' returns void, expr_codegen will return None")
          None
        }
        _ => {
          // Optionally print non-void returns for deeper debugging
          // println("DEBUG: Call to '" + func_name_str + "' returns value")
          (call_result : &@llvm.Value) |> Some
        }
      }
      }
    }
    TupleAccess(tuple_name, index) => {
      let (elem_ptr, elem_ty) = self.tuple_element_ptr_and_type(
        tuple_name, index,
      )
      let llvm_elem_ty = self.type_codegen_opaque(elem_ty)
      let loaded = self.builder.createLoad(llvm_elem_ty, elem_ptr)
      (loaded : &@llvm.Value) |> Some
    }
    ArrayAccess(array_name, index_name) => {
      let array_value = self.resolve_value(array_name)
      let index_value = self.resolve_value(index_name)
      let array_ty = match self.name_types.get(array_name) {
        Some(ty) => ty
        None => raise CodegenError("Missing type for array variable")
      }
      let element_ty = match array_ty {
        @knf.Type::Array(elem) => elem
        _ => raise CodegenError("Array access on non-array type")
      }
      // Use GEP + load instead of function call
      let elem_llvm_ty : &@llvm.Type = match element_ty {
        @knf.Type::Int => (self.llvm_ctx.getInt32Ty() : &@llvm.Type)
        @knf.Type::Double => (self.llvm_ctx.getDoubleTy() : &@llvm.Type)
        @knf.Type::Bool => (self.llvm_ctx.getInt1Ty() : &@llvm.Type)
        _ => (self.llvm_ctx.getPtrTy() : &@llvm.Type)
      }
      let elem_ptr = self.builder.createGEP(array_value, elem_llvm_ty, [index_value])
      let result = self.builder.createLoad(elem_llvm_ty, elem_ptr)
      (result : &@llvm.Value) |> Some
    }
    Unit => None
  }
}
