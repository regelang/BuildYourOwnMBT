///|
pub(all) struct KnfBlock {
  stmts : Array[KnfStmt]
  ty : Type
}

///|
pub fn Context::block_expr_to_knf(
  self : Context,
  expr : @typecheck.BlockExpr,
) -> KnfBlock raise KnfTransformError {
  self.enter_scope()
  defer { self.exit_scope() }

  let mut all_stmts : Array[KnfStmt] = []
  let mut i = 0
  while i < expr.stmts.length() {
    let knf_stmts = self.stmt_to_knf(expr.stmts[i])
    all_stmts = all_stmts + knf_stmts
    i = i + 1
  }

  let knf_ty = self.typekind_to_knf(expr.ty)
  KnfBlock::{ stmts: all_stmts, ty: knf_ty }
}

///|
pub fn KnfBlock::to_string(self : KnfBlock, ident : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\n")
  for stmt in self.stmts {
    sb.write_string(stmt.to_string(ident=ident + 2))
    sb.write_string("\n")
  }
  sb.write_string(" ".repeat(ident))
  sb.write_string("}")
  sb.to_string()
}

///|
pub fn KnfBlock::nested_to_string(self : KnfBlock) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{")
  for stmt in self.stmts {
    sb.write_string(stmt.to_string(ident=0))
    sb.write_string(" ")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
pub impl Show for KnfBlock with output(self, logger) {
  logger.write_string(self.to_string(0))
}
