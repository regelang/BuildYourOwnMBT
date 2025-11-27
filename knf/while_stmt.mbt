///|
pub fn Context::while_stmt_to_knf(
  self : Context,
  while_stmt : @typecheck.WhileStmt,
) -> Array[KnfStmt] raise KnfTransformError {
  let cond_result = self.expr_to_knf(while_stmt.cond)
  let cond_stmts = cond_result.0
  let cond_expr = cond_result.1

  // Build the condition block: evaluate condition statements then emit ExprStmt(cond_expr)
  let cond_all_stmts = cond_stmts + [ExprStmt(cond_expr)]
  let cond_ty = self.typekind_to_knf(while_stmt.cond.ty)
  let cond_block = KnfBlock::{
    stmts: cond_all_stmts,
    ty: cond_ty,
  }

  // Transform the loop body block expression into KNF
  let body_block = self.block_expr_to_knf(while_stmt.body)

  [While(cond_block, body_block)]
}
