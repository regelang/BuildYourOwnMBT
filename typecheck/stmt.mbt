///|
pub(all) struct Stmt {
  kind : StmtKind
} derive(Show)

///|
pub(all) enum StmtKind {
  LetStmt(LetStmt)
  LetMutStmt(LetMutStmt)
  AssignStmt(AssignStmt)
  WhileStmt(WhileStmt)
  ExprStmt(Expr)
  ReturnStmt(Expr?)
  LocalFunction(LocalFunction)
} derive(Show)

///|
pub fn Context::check_stmt(
  self : Context,
  stmt : @parser.Stmt,
) -> Stmt raise TypeCheckError {
  match stmt.kind {
    @parser.StmtKind::LetStmt(let_stmt) => {
      let checked = self.check_let_stmt(let_stmt)
      Stmt::{ kind: StmtKind::LetStmt(checked) }
    }
    @parser.StmtKind::LetMutStmt(let_mut_stmt) => {
      let checked = self.check_let_mut_stmt(let_mut_stmt)
      Stmt::{ kind: StmtKind::LetMutStmt(checked) }
    }
    @parser.StmtKind::AssignStmt(assign_stmt) => {
      let checked = self.check_assign_stmt(assign_stmt)
      Stmt::{ kind: StmtKind::AssignStmt(checked) }
    }
    @parser.StmtKind::WhileStmt(while_stmt) => {
      let checked = self.check_while_stmt(while_stmt)
      Stmt::{ kind: StmtKind::WhileStmt(checked) }
    }
    @parser.StmtKind::ExprStmt(expr) => {
      let checked = self.check_expr(expr)
      Stmt::{ kind: StmtKind::ExprStmt(checked) }
    }
    @parser.StmtKind::IfStmt(expr) => {
      let checked = self.check_expr(expr)
      Stmt::{ kind: StmtKind::ExprStmt(checked) }
    }
    @parser.StmtKind::ReturnStmt(expr_opt) => {
      self.check_return_stmt(expr_opt)
    }
    @parser.StmtKind::LocalFunction(local_fn) => {
      let checked = self.check_local_function(local_fn)
      Stmt::{ kind: StmtKind::LocalFunction(checked) }
    }
  }
}

fn Context::check_return_stmt(
  self : Context,
  expr_opt : @parser.Expr?,
) -> Stmt raise TypeCheckError {
  let current_ret_ty = match self.current_func_ret_ty {
    Some(ty) => ty
    None => raise TypeCheckError("Return statement outside of function")
  }

  match expr_opt {
    Some(parser_expr) => {
      let checked_expr = self.check_expr(parser_expr)

      // Resolve any type variables in both the declared return type and the
      // expression type so unification results are reflected here.
      let mut expected_kind = self.resolve_type_kind(current_ret_ty)
      let mut expr_kind = self.resolve_type_kind(checked_expr.ty)

      // When we are inside a generic function body and there are concrete
      // bindings for generic parameters (e.g. T -> Int), apply those
      // bindings before checking compatibility. This allows a declared
      // return type like Array[T] to match a concrete Array[Int] in an
      // instantiated body.
      if self.checking_generic_function_body && !self.generic_type_bindings.is_empty() {
        let type_param_map = self.generic_type_bindings.copy()
        expected_kind = self.substitute_type_kind_with_map(expected_kind, type_param_map)
        expr_kind = self.substitute_type_kind_with_map(expr_kind, type_param_map)
      }

      if !self.is_type_compatible(expected_kind, expr_kind) {
        println("DEBUG: Return type mismatch - expected: " + expected_kind.to_string() + ", got: " + expr_kind.to_string())
        raise TypeCheckError("Return expression type mismatch")
      }
      Stmt::{ kind: StmtKind::ReturnStmt(Some(Expr::{ kind: checked_expr.kind, ty: expr_kind })) }
    }
    None => {
      let expected_kind = self.resolve_type_kind(current_ret_ty)
      if !self.is_type_compatible(expected_kind, TypeKind::Unit) {
        raise TypeCheckError("Return without value requires Unit return type")
      }
      Stmt::{ kind: StmtKind::ReturnStmt(None) }
    }
  }
}
