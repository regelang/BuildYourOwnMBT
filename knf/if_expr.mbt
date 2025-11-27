///|
pub fn Context::if_expr_to_knf(
  self : Context,
  if_expr : @typecheck.IfExpr,
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  let cond_result = self.expr_to_knf(if_expr.cond)
  let mut stmts = cond_result.0
  let cond_expr = cond_result.1

  let then_block = self.block_expr_to_knf(if_expr.then_block)

  let else_block = match if_expr.else_block {
    None => {
      KnfBlock::{ stmts: [], ty: Type::Unit }
    }
    Some(@either.Either::Left(else_if_expr)) => {
      let else_result = self.if_expr_to_knf(else_if_expr)
      let else_stmts = else_result.0
      let nested_if_expr = else_result.1
      stmts = stmts + else_stmts

      let block_ty = self.typekind_to_knf(else_if_expr.ty)
      KnfBlock::{
        stmts: [ExprStmt(nested_if_expr)],
        ty: block_ty,
      }
    }
    Some(@either.Either::Right(else_block_expr)) => self.block_expr_to_knf(else_block_expr)
  }

  (stmts, If(cond_expr, then_block, else_block))
}
