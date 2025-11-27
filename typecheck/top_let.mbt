///|
pub(all) struct TopLet {
  name : String
  ty : Type
  expr : Expr
} derive(Show)

///|
pub fn Context::check_top_let(
  self : Context,
  top_let : @parser.TopLet,
) -> TopLet raise TypeCheckError {
  let checked_expr = self.check_expr(top_let.expr)
  let resolved_expr = Expr::{
    kind: checked_expr.kind,
    ty: self.resolve_type_kind(checked_expr.ty)
  }

  let final_ty = match top_let.ty {
    Some(parser_ty) => {
      let annotated = self.check_parser_type(parser_ty)
      if !self.is_type_compatible(annotated.kind, resolved_expr.ty) {
        raise TypeCheckError("Expression type does not match annotation in top let")
      }
      Type::{ kind: self.resolve_type_kind(annotated.kind), mutable: false }
    }
    None => Type::{ kind: resolved_expr.ty, mutable: false }
  }

  self.type_env.set(top_let.name, final_ty)

  TopLet::{
    name: top_let.name,
    ty: final_ty,
    expr: Expr::{ kind: resolved_expr.kind, ty: final_ty.kind }
  }
}
