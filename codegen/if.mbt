///|
pub fn Context::if_codegen(
  self : Self,
  cond : @knf.KnfExpr,
  then_block : @knf.KnfBlock,
  else_block : @knf.KnfBlock,
) -> &@llvm.Value? raise {
  let current_func = self.builder.getInsertFunction()

  let cond_value = match self.expr_codegen(cond) {
    Some(v) => v
    None => raise CodegenError("If condition must produce a value")
  }

  let then_bb = current_func.addBasicBlock()
  let else_bb = current_func.addBasicBlock()
  let merge_bb = current_func.addBasicBlock()

  let _ = self.builder.createCondBr(cond_value, then_bb, else_bb)

  self.builder.setInsertPoint(then_bb)
  let mut then_value : &@llvm.Value? = None
  let mut i = 0
  while i < then_block.stmts.length() {
    if self.builder.getInsertBlock().getTerminator() is Some(_) {
      break
    }

    let stmt = then_block.stmts[i]
    match stmt {
      @knf.KnfStmt::ExprStmt(expr) => {
        then_value = self.expr_codegen(expr)
      }
      _ => {
        self.stmt_codegen(stmt)
        then_value = None
      }
    }
    i = i + 1
  }

  let then_insert_bb = self.builder.getInsertBlock()
  let then_has_term = then_insert_bb.getTerminator() is Some(_)
  if !then_has_term {
    if !(then_block.ty is @knf.Type::Unit) && then_value is None {
      raise CodegenError("Then branch missing value in non-unit if expression")
    }
    let _ = self.builder.createBr(merge_bb)
  }

  self.builder.setInsertPoint(else_bb)
  let mut else_value : &@llvm.Value? = None
  let mut j = 0
  while j < else_block.stmts.length() {
    if self.builder.getInsertBlock().getTerminator() is Some(_) {
      break
    }

    let stmt = else_block.stmts[j]
    match stmt {
      @knf.KnfStmt::ExprStmt(expr) => {
        else_value = self.expr_codegen(expr)
      }
      _ => {
        self.stmt_codegen(stmt)
        else_value = None
      }
    }
    j = j + 1
  }

  let else_insert_bb = self.builder.getInsertBlock()
  let else_has_term = else_insert_bb.getTerminator() is Some(_)
  if !else_has_term {
    if !(else_block.ty is @knf.Type::Unit) && else_value is None {
      raise CodegenError("Else branch missing value in non-unit if expression")
    }
    let _ = self.builder.createBr(merge_bb)
  }

  let then_fallthrough = !then_has_term
  let else_fallthrough = !else_has_term

  if !then_fallthrough && !else_fallthrough {
    merge_bb.removeFromParent()
    return None
  }

  self.builder.setInsertPoint(merge_bb)

  // If either branch has Unit type, treat the whole if as Unit.
  // This covers patterns like:
  //   if cond { return v; };
  // where the if expression is used as a statement (trailing semicolon)
  // and one branch may contain a return (terminator) while the other falls through.
  if then_block.ty is @knf.Type::Unit || else_block.ty is @knf.Type::Unit {
    None
  } else {
    // For non-Unit result, both branches must fall through so we can create a PHI.
    if !(then_fallthrough && else_fallthrough) {
      println("DEBUG: if_codegen - then_block.ty: " + then_block.ty.to_string())
      println("DEBUG: if_codegen - then_fallthrough: " + then_fallthrough.to_string() + ", else_fallthrough: " + else_fallthrough.to_string())
      raise CodegenError("Both branches must fall through for non-unit if expression")
    }

    let value_ty = self.type_codegen_opaque(then_block.ty)
    let phi = self.builder.createPHI(value_ty)
    let then_val = match then_value {
      Some(v) => v
      None => raise CodegenError("Then branch missing value in non-unit if expression")
    }
    let else_val = match else_value {
      Some(v) => v
      None => raise CodegenError("Else branch missing value in non-unit if expression")
    }
    phi.addIncoming(then_val, then_insert_bb)
    phi.addIncoming(else_val, else_insert_bb)
    (phi : &@llvm.Value) |> Some
  }
}
