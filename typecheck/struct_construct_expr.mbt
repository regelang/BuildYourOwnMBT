///|
pub(all) struct StructConstructExpr {
  name : String
  fields : Array[(String, Expr)]
} derive(Show)

///|
pub fn Context::check_struct_construct_expr(
  self : Self,
  sc_expr : @parser.StructConstructExpr,
) -> (AtomExprKind, TypeKind) raise TypeCheckError {
  let struct_name = sc_expr.name

  let struct_def = match self.struct_defs.get(struct_name) {
    Some(def) => def
    None => raise TypeCheckError("Unknown struct: " + struct_name)
  }

  let field_types : Map[String, Type] = Map::new()
  let used_fields : Map[String, Bool] = Map::new()

  // Prepare a mapping from the struct's type parameters to the concrete
  // types that are currently bound in the generic context. If a parameter is
  // unbound, fall back to the placeholder Struct name so downstream checks can
  // still reason about the generic symbol.
  let type_param_map : Map[String, TypeKind] = Map::new()
  let mut tp_idx = 0
  while tp_idx < struct_def.type_params.length() {
    let param_name = struct_def.type_params[tp_idx]
    match self.generic_type_bindings.get(param_name) {
      Some(bound_type) => type_param_map.set(param_name, self.resolve_type_kind(bound_type))
      None => type_param_map.set(param_name, TypeKind::Struct(param_name))
    }
    tp_idx = tp_idx + 1
  }

  let mut i = 0
  while i < struct_def.fields.length() {
    let field = struct_def.fields[i]
    field_types.set(field.name, field.ty)
    used_fields.set(field.name, false)
    i = i + 1
  }

  let mut checked_fields : Array[(String, Expr)] = []
  let mut j = 0
  while j < sc_expr.fields.length() {
    let (field_name, field_expr) = sc_expr.fields[j]

    match field_types.get(field_name) {
      Some(expected_type) => {
        match used_fields.get(field_name) {
          Some(true) => raise TypeCheckError("Duplicate field '" + field_name + "' in struct construction")
          _ => ()
        }

        let checked_expr = self.check_expr(field_expr)
        let mut resolved_expr_ty = self.resolve_type_kind(checked_expr.ty)
        let mut resolved_expr = Expr::{ kind: checked_expr.kind, ty: resolved_expr_ty }

        // Special handling for generic functions: try to infer type bindings from expected type
        if resolved_expr_ty.to_string().contains("TypeVar(") && expected_type.kind.to_string().contains("TypeVar(") {
          // Save current bindings
          let old_bindings = self.generic_type_bindings.copy()
          // Clear generic type bindings before inference
          self.clear_generic_type_bindings()
          
          // Try to infer generic type bindings from expected type
          self.infer_generic_bindings(expected_type.kind, resolved_expr.ty)
          
          // Resolve the expression type with the inferred bindings
          resolved_expr_ty = self.resolve_type_kind(checked_expr.ty)
          resolved_expr = Expr::{ kind: checked_expr.kind, ty: resolved_expr_ty }
          
          // Restore previous bindings after inference
          self.generic_type_bindings = old_bindings
        }

        // Substitute struct-level generic parameters with any available bindings so
        // the compatibility check sees the concrete types being constructed.
        let substituted_expected = if struct_def.type_params.length() > 0 {
          self.substitute_type_kind_with_map(expected_type.kind, type_param_map)
        } else {
          expected_type.kind
        }

        // Emit detailed diagnostics so we can see which concrete types failed to match.
        println("DEBUG: struct_construct_expr: field " + field_name + " expected type " + substituted_expected.to_string())
        println("DEBUG: struct_construct_expr: field " + field_name + " actual type " + resolved_expr.ty.to_string())
        if !self.is_type_compatible(substituted_expected, resolved_expr.ty) {
          raise TypeCheckError("Field '" + field_name + "' type mismatch in struct construction")
        }

        used_fields.set(field_name, true)
        checked_fields = checked_fields + [(field_name, resolved_expr)]
      }
      None => raise TypeCheckError("Unknown field '" + field_name + "' for struct " + struct_name)
    }

    j = j + 1
  }

  let mut k = 0
  while k < struct_def.fields.length() {
    let field_name = struct_def.fields[k].name
    match used_fields.get(field_name) {
      Some(true) => ()
      _ => raise TypeCheckError("Missing field '" + field_name + "' in struct construction")
    }
    k = k + 1
  }

  // Emit a GenericStruct when type parameters exist so downstream consumers
  // can retain knowledge of the instantiated type arguments.
  let result_type = if struct_def.type_params.length() == 0 {
    TypeKind::Struct(struct_name)
  } else {
    let mut type_args : Array[TypeKind] = []
    let mut arg_idx = 0
    while arg_idx < struct_def.type_params.length() {
      let param_name = struct_def.type_params[arg_idx]
      match type_param_map.get(param_name) {
        Some(bound_type) => type_args = type_args + [bound_type]
        None => type_args = type_args + [TypeKind::Struct(param_name)]
      }
      arg_idx = arg_idx + 1
    }
    TypeKind::GenericStruct(struct_name, type_args)
  }
  println("DEBUG: struct_construct_expr: created struct of type " + result_type.to_string())
  
  (
    AtomExprKind::StructConstruct(StructConstructExpr::{ name: struct_name, fields: checked_fields }),
    result_type
  )
}
