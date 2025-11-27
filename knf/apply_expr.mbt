///|
pub fn Context::apply_expr_to_knf(
  self : Context,
  apply_expr : @typecheck.ApplyExpr,
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  match apply_expr.kind {
    @typecheck.ApplyExprKind::AtomExpr(atom_expr) => self.atom_expr_to_knf(atom_expr)
    @typecheck.ApplyExprKind::ArrayAccess(array_expr, index_expr) => {
      let (array_stmts, array_knf) = self.apply_expr_to_knf(array_expr)
      let (index_stmts, index_knf) = self.expr_to_knf(index_expr)

      let stmts = array_stmts + index_stmts

      let array_type = self.typekind_to_knf(array_expr.ty)
      let array_name = self.expr_to_knf_name(array_knf, array_type, stmts)

      let index_type = self.typekind_to_knf(index_expr.ty)
      let index_name = self.expr_to_knf_name(index_knf, index_type, stmts)

      (stmts, ArrayAccess(array_name, index_name))
    }
    @typecheck.ApplyExprKind::FieldAccess(object_expr, field_name) => {
      let (object_stmts, object_knf) = self.apply_expr_to_knf(object_expr)
      let stmts = object_stmts

      let object_type = self.typekind_to_knf(object_expr.ty)
      let object_name = self.expr_to_knf_name(object_knf, object_type, stmts)

      (stmts, FieldAccess(object_name, field_name))
    }
    @typecheck.ApplyExprKind::Call(callee_expr, arg_exprs) => {
      let (callee_stmts, callee_knf) = self.apply_expr_to_knf(callee_expr)
      let mut stmts = callee_stmts

      let callee_type = self.typekind_to_knf(callee_expr.ty)
      let mut callee_name = self.expr_to_knf_name(callee_knf, callee_type, stmts)

      let mut arg_names : Array[Name] = []
      let mut arg_types : Array[Type] = []
      let mut i = 0
      while i < arg_exprs.length() {
        let (arg_stmts, arg_knf) = self.expr_to_knf(arg_exprs[i])
        stmts = stmts + arg_stmts

        let arg_type = self.typekind_to_knf(arg_exprs[i].ty)
        let arg_name = self.expr_to_knf_name(arg_knf, arg_type, stmts)
        arg_names = arg_names + [arg_name]
        arg_types = arg_types + [arg_type]
        i = i + 1
      }

      // Check if this is a call to a generic function
      let func_name_str = callee_name.id
      match self.generic_functions.get(func_name_str) {
        Some(generic_func) => {
          // This is a generic function call - monomorphize it
          let mono_name = self.monomorphize_function(generic_func, arg_types)
          callee_name = Name::{ id: mono_name, slot: 0 }
        }
        None => ()
      }

      (stmts, Call(callee_name, arg_names))
    }
    @typecheck.ApplyExprKind::EnumVariantAccess(enum_name, variant_name) => {
      // For enum variant access like Color::Red, we treat it as a constructor call
      // In KNF, this becomes a call to the enum variant constructor
      let constructor_name = Name::{ id: enum_name + "::" + variant_name, slot: 0 }
      ([], Call(constructor_name, []))
    }
  }
}
