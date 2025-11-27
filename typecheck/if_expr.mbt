///|
pub(all) struct IfExpr {
  cond : Expr
  then_block : BlockExpr
  else_block : Either[IfExpr, BlockExpr]?
  ty : TypeKind
} derive(Show)

///|
pub fn Context::check_if_expr(
  self : Context,
  if_expr : @parser.IfExpr,
) -> IfExpr raise TypeCheckError {
  let cond_checked = self.check_expr(if_expr.cond)
  if !self.is_type_compatible(cond_checked.ty, TypeKind::Bool) {
    raise TypeCheckError("If condition must have Bool type")
  }

  let then_checked = self.check_block_expr(if_expr.then_block)

  // If there's no else block and the then-branch ends with a return,
  // treat the whole if-as-statement as producing Unit (it's used for
  // early-return control flow). This avoids requiring the then-branch
  // to be compatible with Unit when it contains a `return`.
  let then_ends_with_return_quick = self.block_ends_with_return(then_checked)
  if if_expr.else_block is None && then_ends_with_return_quick {
    return IfExpr::{
      cond: cond_checked,
      then_block: then_checked,
      else_block: None,
      ty: TypeKind::Unit
    }
  }

  let mut else_checked : Option[Either[IfExpr, BlockExpr]] = None
  let mut else_ty = TypeKind::Unit

  match if_expr.else_block {
    None => ()
    Some(@parser.Either::Left(else_if)) => {
      let checked_else_if = self.check_if_expr(else_if)
      else_ty = checked_else_if.ty
      else_checked = Some(@either.Either::Left(checked_else_if))
    }
    Some(@parser.Either::Right(else_block)) => {
      let checked_else_block = self.check_block_expr(else_block)
      else_ty = checked_else_block.ty
      else_checked = Some(@either.Either::Right(checked_else_block))
    }
  }

  if !self.is_type_compatible(then_checked.ty, else_ty) {
    raise TypeCheckError("If branches must have compatible types")
  }

  let result_ty = match else_checked {
    None => TypeKind::Unit
    Some(_) => {
      // Special case: if both branches end with return statements, 
      // the if expression should have the function's return type
      let then_ends_with_return = self.block_ends_with_return(then_checked)
      let else_ends_with_return = match else_checked {
        Some(@either.Either::Left(else_if)) => self.if_ends_with_return(else_if)
        Some(@either.Either::Right(else_block)) => self.block_ends_with_return(else_block)
        None => false
      }
      
      if then_ends_with_return && else_ends_with_return {
        // Both branches end with return, so this if expression has the function's return type
        match self.current_func_ret_ty {
          Some(ret_ty) => ret_ty
          None => self.resolve_type_kind(then_checked.ty) // Fallback
        }
      } else {
        self.resolve_type_kind(then_checked.ty)
      }
    }
  }

  IfExpr::{
    cond: cond_checked,
    then_block: then_checked,
    else_block: else_checked,
    ty: result_ty
  }
}

fn Context::block_ends_with_return(self : Context, block : BlockExpr) -> Bool {
  if block.stmts.length() == 0 {
    false
  } else {
    match block.stmts[block.stmts.length() - 1].kind {
      StmtKind::ReturnStmt(_) => true
      StmtKind::ExprStmt(expr) => match expr.kind {
        ExprKind::IfExpr(if_expr) => self.if_ends_with_return(if_expr)
        _ => false
      }
      _ => false
    }
  }
}

/// Check if an if expression ends with a return statement
fn Context::if_ends_with_return(self : Context, if_expr : IfExpr) -> Bool {
  // Check if then branch ends with return
  let then_ends_with_return = self.block_ends_with_return(if_expr.then_block)
  
  // Check if else branch ends with return
  let else_ends_with_return = match if_expr.else_block {
    None => false
    Some(@either.Either::Left(else_if)) => self.if_ends_with_return(else_if)
    Some(@either.Either::Right(else_block)) => self.block_ends_with_return(else_block)
  }
  
  then_ends_with_return && else_ends_with_return
}
