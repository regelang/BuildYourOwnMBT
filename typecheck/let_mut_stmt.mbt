///|
pub(all) struct LetMutStmt {
  name : String
  ty : TypeKind
  expr : Expr
} derive(Show)

///|
pub fn Context::check_let_mut_stmt(
  self : Context,
  stmt : @parser.LetMutStmt,
) -> LetMutStmt raise TypeCheckError {
  let checked_expr = self.check_expr(stmt.expr)
  let resolved_expr = Expr::{
    kind: checked_expr.kind,
    ty: self.resolve_type_kind(checked_expr.ty)
  }

  let final_kind = match stmt.ty {
    Some(parser_ty) => {
      let annotated_type = self.check_parser_type(parser_ty)
      if !self.is_type_compatible(annotated_type.kind, resolved_expr.ty) {
        raise TypeCheckError("Expression type does not match annotation in let mut")
      }
      self.resolve_type_kind(annotated_type.kind)
    }
    None => resolved_expr.ty
  }

  let var_type = Type::{ kind: final_kind, mutable: true }
  let var_name = stmt.name
  self.type_env.set(var_name, var_type)

  let final_expr = Expr::{ kind: resolved_expr.kind, ty: final_kind }

  LetMutStmt::{
    name: var_name,
    ty: final_kind,
    expr: final_expr
  }
}
