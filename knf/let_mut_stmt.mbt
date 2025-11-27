///|
pub fn Context::let_mut_stmt_to_knf(
  self : Context,
  let_mut_stmt : @typecheck.LetMutStmt,
) -> Array[KnfStmt] raise KnfTransformError {
  let (expr_stmts, expr_knf) = self.expr_to_knf(let_mut_stmt.expr)
  let mut stmts = expr_stmts

  let knf_ty = self.typekind_to_knf(let_mut_stmt.ty)
  let var_name = self.add_new_name(let_mut_stmt.name, knf_ty)

  stmts = stmts + [LetMut(var_name, knf_ty, expr_knf)]
  stmts
}
