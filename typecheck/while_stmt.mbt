///|
pub(all) struct WhileStmt {
  cond : Expr
  body : BlockExpr
} derive(Show)

///|
pub fn Context::check_while_stmt(
  self : Context,
  while_stmt : @parser.WhileStmt,
) -> WhileStmt raise TypeCheckError {
  let checked_cond = self.check_expr(while_stmt.cond)
  if !self.is_type_compatible(checked_cond.ty, TypeKind::Bool) {
    raise TypeCheckError("While condition must have Bool type")
  }

  let checked_body = self.check_block_expr(while_stmt.body)

  WhileStmt::{
    cond: checked_cond,
    body: checked_body
  }
}
