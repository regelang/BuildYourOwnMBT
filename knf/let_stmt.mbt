///|
pub fn Context::let_stmt_to_knf(
  self : Context,
  let_stmt : @typecheck.LetStmt,
) -> Array[KnfStmt] raise KnfTransformError {
  let (expr_stmts, expr_knf) = self.expr_to_knf(let_stmt.expr)
  let knf_ty = self.typekind_to_knf(let_stmt.ty)
  bind_pattern_to_expr(self, let_stmt.pattern, knf_ty, expr_knf, expr_stmts)
}

///|
fn bind_pattern_to_expr(
  ctx : Context,
  pattern : @typecheck.Pattern,
  expected_ty : Type,
  expr : KnfExpr,
  stmts : Array[KnfStmt],
) -> Array[KnfStmt] raise KnfTransformError {
  match pattern.kind {
    @typecheck.PatternKind::Ident(name) => {
      let var_name = ctx.add_new_name(name, expected_ty)
      stmts + [Let(var_name, expected_ty, expr)]
    }
    @typecheck.PatternKind::Wildcard =>
      stmts + [Let(Name::wildcard(), expected_ty, expr)]
    @typecheck.PatternKind::Constructor(_constructor_name, _sub_patterns) => {
      // 构造器模式：简化处理，直接绑定到临时变量
      // 完整实现需要提取字段并递归绑定子模式
      let temp_name = ctx.add_temp(expected_ty)
      stmts + [Let(temp_name, expected_ty, expr)]
    }
    @typecheck.PatternKind::Tuple(sub_patterns) => {
      let elem_types = match expected_ty {
        Type::Tuple(types) => types
        _ => raise KnfTransformError("Tuple pattern requires tuple type")
      }
      if elem_types.length() != sub_patterns.length() {
        raise KnfTransformError("Tuple type arity mismatch")
      }
      let (components, base_stmts) = match expr {
        KnfExpr::TupleLiteral(names) => {
          if names.length() != sub_patterns.length() {
            raise KnfTransformError("Tuple pattern arity mismatch")
          }
          (names, stmts)
        }
        KnfExpr::Ident(name) => {
          let mut generated : Array[Name] = []
          let mut current = stmts
          let mut idx = 0
          while idx < elem_types.length() {
            let elem_ty = elem_types[idx]
            let elem_temp = ctx.add_temp(elem_ty)
            current = current +
              [Let(elem_temp, elem_ty, KnfExpr::TupleAccess(name, idx))]
            generated = generated + [elem_temp]
            idx = idx + 1
          }
          (generated, current)
        }
        _ => {
          let tuple_temp = ctx.add_temp(expected_ty)
          let mut current = stmts + [Let(tuple_temp, expected_ty, expr)]
          let mut generated : Array[Name] = []
          let mut idx = 0
          while idx < elem_types.length() {
            let elem_ty = elem_types[idx]
            let elem_temp = ctx.add_temp(elem_ty)
            current = current +
              [Let(elem_temp, elem_ty, KnfExpr::TupleAccess(tuple_temp, idx))]
            generated = generated + [elem_temp]
            idx = idx + 1
          }
          (generated, current)
        }
      }
      let mut i = 0
      let mut current_stmts = base_stmts
      while i < sub_patterns.length() {
        let name_expr = KnfExpr::Ident(components[i])
        current_stmts = bind_pattern_to_expr(
          ctx,
          sub_patterns[i],
          elem_types[i],
          name_expr,
          current_stmts,
        )
        i = i + 1
      }
      current_stmts
    }
  }
}
