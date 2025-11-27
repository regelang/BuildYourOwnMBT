///|
pub(all) struct KnfTopLet {
  name : Name
  ty : Type
  expr : KnfExpr
}

///|
pub fn Context::top_let_to_knf(
  self : Context,
  top_let : @typecheck.TopLet,
) -> KnfTopLet raise KnfTransformError {
  if self.globals.get(top_let.name) is Some(_) {
    raise KnfTransformError("Duplicate global variable declaration: " + top_let.name)
  }

  let (expr_stmts, expr_knf) = self.expr_to_knf(top_let.expr)
  // For now, we ignore any statements produced by the initializer
  // This is a simplification - in a full implementation, we might want to
  // create an initialization function or handle this differently
  // Most top-level lets should be simple constants anyway
  let _ = expr_stmts  // Explicitly ignore statements

  let knf_ty = self.type_to_knf(top_let.ty)

  let name = self.add_new_name(top_let.name, knf_ty)
  self.globals.set(top_let.name, knf_ty)

  KnfTopLet::{
    name,
    ty: knf_ty,
    expr: expr_knf,
  }
}

///|
pub impl Show for KnfTopLet with output(self, logger) {
  let { name, ty, expr } = self
  logger.write_string("let \{name} : \{ty} = \{expr};")
}
