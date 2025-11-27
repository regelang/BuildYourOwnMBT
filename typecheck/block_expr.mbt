///|
pub(all) struct BlockExpr {
  stmts : Array[Stmt]
  ty : TypeKind
} derive(Show)

///|
pub fn Context::check_block_expr(
  self : Context,
  block_expr : @parser.BlockExpr,
) -> BlockExpr raise TypeCheckError {
  self.enter_scope()
  defer { self.exit_scope() }

  let mut checked_stmts : Array[Stmt] = []
  let mut i = 0
  while i < block_expr.stmts.length() {
    let checked_stmt = self.check_stmt(block_expr.stmts[i])
    checked_stmts = checked_stmts + [checked_stmt]
    i = i + 1
  }

  let block_ty = if checked_stmts.length() == 0 {
    TypeKind::Unit
  } else {
    match checked_stmts[checked_stmts.length() - 1].kind {
      StmtKind::ExprStmt(expr) => self.resolve_type_kind(expr.ty)
      StmtKind::ReturnStmt(expr_opt) => {
        // For return statements, use the function's return type if available
        match self.current_func_ret_ty {
          Some(ret_ty) => self.resolve_type_kind(ret_ty)
          None => {
            // If not in a function context, use the return expression's type or Unit
            match expr_opt {
              Some(expr) => self.resolve_type_kind(expr.ty)
              None => TypeKind::Unit
            }
          }
        }
      }
      _ => TypeKind::Unit
    }
  }

  BlockExpr::{
    stmts: checked_stmts,
    ty: block_ty
  }
}
