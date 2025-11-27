///|
pub(all) struct LeftValue {
  kind : LeftValueKind
  ty : Type
} derive(Show)

///|
pub(all) enum LeftValueKind {
  Ident(String)
  ArrayAccess(LeftValue, Expr)
  FieldAccess(LeftValue, String)
} derive(Show)

///|
pub(all) struct AssignStmt {
  left_value : LeftValue
  op : AssignOp
  expr : Expr
} derive(Show)

///|
pub(all) enum AssignOp {
  Assign // =
  PlusAssign // +=
  MinusAssign // -=
  MultAssign // *=
  DivAssign // /=
  ModAssign // %=
} derive(Show, Eq)

///|
pub fn AssignOp::from_parser_assign_op(op : @parser.AssignOp) -> AssignOp {
  match op {
    Assign => Assign
    PlusAssign => PlusAssign
    MinusAssign => MinusAssign
    MultAssign => MultAssign
    DivAssign => DivAssign
    ModAssign => ModAssign
  }
}

///|
pub fn Context::check_assign_stmt(
  self : Context,
  assign_stmt : @parser.AssignStmt,
) -> AssignStmt raise TypeCheckError {
  let checked_left = self.check_left_value(assign_stmt.left_value)
  let assign_op = AssignOp::from_parser_assign_op(assign_stmt.op)
  let checked_expr = self.check_expr(assign_stmt.expr)
  let resolved_expr = Expr::{
    kind: checked_expr.kind,
    ty: self.resolve_type_kind(checked_expr.ty)
  }
  let mut expr_ty = resolved_expr.ty

  if !checked_left.ty.mutable {
    raise TypeCheckError("Cannot assign to an immutable value")
  }

  let mut target_kind = self.resolve_type_kind(checked_left.ty.kind)

  match assign_op {
    Assign => {
      // Log the concrete types being compared to help diagnose generic mismatches.
      println("DEBUG: assign_stmt: target type " + target_kind.to_string())
      println("DEBUG: assign_stmt: expr type " + resolved_expr.ty.to_string())
      // Re-resolve the expression type in case new bindings were introduced.
      expr_ty = self.resolve_type_kind(expr_ty)

      let mut compatible = self.is_type_compatible(target_kind, expr_ty)
      // Only attempt generic compatibility when the assignment genuinely
      // involves generics (e.g. T, TypeVar, GenericStruct/Enum). For plain
      // concrete types like Int vs Double we must *not* fall back to
      // generic compatibility, otherwise negative tests such as
      // array_put_type_mismatch will incorrectly succeed.
      let expr_has_typevar = expr_ty.to_string().contains("TypeVar(")
      let target_has_generic = self.contains_generic_parameter(target_kind)
      let expr_has_generic = self.contains_generic_parameter(expr_ty)
      if !compatible && (expr_has_typevar || target_has_generic || expr_has_generic) {
        println("DEBUG: assign_stmt: forward compatibility failed, attempting generic compatibility")
        let saved_bindings = self.generic_type_bindings.copy()
        compatible = self.is_generic_compatible(target_kind, expr_ty)
        if !compatible {
          // Restore bindings to avoid leaving partial state behind
          self.generic_type_bindings = saved_bindings
        }
      }
      if !compatible && self.checking_generic_function_body {
        // As a last resort during generic function checks, bind an unbound generic
        // parameter (like Struct("T")) to the concrete target type so that
        // subsequent comparisons see the instantiated type.
        match expr_ty {
          TypeKind::Struct(name) => {
            let is_generic_param = name.length() == 1 && name >= "A" && name <= "Z"
            if is_generic_param {
              match self.generic_type_bindings.get(name) {
                Some(existing) => {
                  if self.is_type_compatible(existing, target_kind) {
                    compatible = true
                  }
                }
                None => {
                  println("DEBUG: assign_stmt: binding generic parameter " + name + " to " + target_kind.to_string())
                  self.generic_type_bindings.set(name, target_kind)
                  expr_ty = self.resolve_type_kind(expr_ty)
                  compatible = true
                }
              }
            }
          }
          _ => ()
        }
      }
      if !compatible {
        raise TypeCheckError("Assigned expression type is not compatible")
      }
    }
    PlusAssign | MinusAssign | MultAssign | DivAssign => {
      let numeric_kind = if self.is_type_compatible(target_kind, TypeKind::Int) {
        TypeKind::Int
      } else if self.is_type_compatible(target_kind, TypeKind::Double) {
        TypeKind::Double
      } else {
        raise TypeCheckError("Compound assignment requires Int or Double operands")
      }

      if !self.is_type_compatible(numeric_kind, resolved_expr.ty) {
        raise TypeCheckError("Compound assignment operand type mismatch")
      }

      target_kind = numeric_kind
    }
    ModAssign => {
      if !self.is_type_compatible(target_kind, TypeKind::Int) {
        raise TypeCheckError("Modulo assignment requires Int operands")
      }
      if !self.is_type_compatible(TypeKind::Int, resolved_expr.ty) {
        raise TypeCheckError("Modulo assignment operand type mismatch")
      }
      target_kind = TypeKind::Int
    }
  }

  let final_left_kind = self.resolve_type_kind(target_kind)
  let final_left = self.resolve_left_value(checked_left, final_left_kind)
  let final_expr = Expr::{ kind: resolved_expr.kind, ty: self.resolve_type_kind(expr_ty) }

  match final_left.kind {
    LeftValueKind::Ident(name) => {
      self.type_env.set(name, Type::{ kind: final_left.ty.kind, mutable: true })
    }
    LeftValueKind::ArrayAccess(base_lv, _) => {
      self.update_base_left_value_env(base_lv)
    }
    LeftValueKind::FieldAccess(base_lv, _) => {
      self.update_base_left_value_env(base_lv)
    }
  }

  AssignStmt::{
    left_value: final_left,
    op: assign_op,
    expr: final_expr
  }
}

fn Context::check_left_value(
  self : Context,
  left_value : @parser.LeftValue,
) -> LeftValue raise TypeCheckError {
  match left_value.kind {
    @parser.LeftValueKind::Ident(name) => {
      match self.type_env.get(name) {
        Some(var_type) => {
          LeftValue::{
            kind: LeftValueKind::Ident(name),
            ty: Type::{
              kind: self.resolve_type_kind(var_type.kind),
              mutable: var_type.mutable
            }
          }
        }
        None => raise TypeCheckError("Unknown identifier in assignment: " + name)
      }
    }
    @parser.LeftValueKind::ArrayAccess(base, index_expr) => {
      let checked_base = self.check_left_value(base)
      let resolved_base = self.resolve_left_value(checked_base, checked_base.ty.kind)

      let checked_index = self.check_expr(index_expr)
      if !self.is_type_compatible(checked_index.ty, TypeKind::Int) {
        raise TypeCheckError("Array index must be Int")
      }
      let resolved_index = Expr::{
        kind: checked_index.kind,
        ty: TypeKind::Int
      }

      let base_kind = self.resolve_type_kind(resolved_base.ty.kind)
      let element_kind = match base_kind {
        TypeKind::Array(elem_ty) => self.resolve_type_kind(elem_ty)
        TypeKind::Any => TypeKind::Any
        TypeKind::TypeVar(_) => {
          let fresh_elem = self.allocate_fresh_type_var()
          if !self.is_type_compatible(resolved_base.ty.kind, TypeKind::Array(fresh_elem)) {
            raise TypeCheckError("Array access expects an Array type")
          }
          self.resolve_type_kind(fresh_elem)
        }
        _ => raise TypeCheckError("Array access expects an Array type")
      }

      LeftValue::{
        kind: LeftValueKind::ArrayAccess(resolved_base, resolved_index),
        ty: Type::{ kind: element_kind, mutable: true }
      }
    }
    @parser.LeftValueKind::FieldAccess(base, field_name) => {
      let checked_base = self.check_left_value(base)
      let resolved_base = self.resolve_left_value(checked_base, checked_base.ty.kind)
      let base_kind = self.resolve_type_kind(resolved_base.ty.kind)

      let field_type = match base_kind {
        TypeKind::Struct(struct_name) => {
          match self.struct_defs.get(struct_name) {
            Some(struct_def) => {
              match struct_def.get_field_type(field_name) {
                Some(field_ty) => Type::{
                  kind: self.resolve_type_kind(field_ty.kind),
                  mutable: field_ty.mutable
                }
                None => raise TypeCheckError("Unknown field '" + field_name + "' on struct " + struct_name)
              }
            }
            None => raise TypeCheckError("Unknown struct: " + struct_name)
          }
        }
        TypeKind::GenericStruct(struct_name, type_args) => {
          // When concrete type arguments are available from the resolved kind (e.g. ValArray[Int]),
          // prefer them. Otherwise fall back to bindings recorded while checking a generic function body.
          match self.struct_defs.get(struct_name) {
            Some(struct_def) => {
              match struct_def.get_field_type(field_name) {
                Some(field_ty) => {
                  let type_param_map : Map[String, TypeKind] = Map::new()
                  let mut i = 0
                  while i < struct_def.type_params.length() {
                    let param_name = struct_def.type_params[i]
                    let concrete_arg = if i < type_args.length() {
                      Some(type_args[i])
                    } else {
                      self.generic_type_bindings.get(param_name)
                    }
                    match concrete_arg {
                      Some(arg_ty) => type_param_map.set(param_name, self.resolve_type_kind(arg_ty))
                      None => type_param_map.set(param_name, TypeKind::Struct(param_name))
                    }
                    i = i + 1
                  }

                  // Substitute type parameters in the field type using the constructed map.
                  let substituted = self.substitute_type_kind_with_map(field_ty.kind, type_param_map)
                  Type::{
                    kind: self.resolve_type_kind(substituted),
                    mutable: field_ty.mutable
                  }
                }
                None => raise TypeCheckError("Unknown field '" + field_name + "' on struct " + struct_name)
              }
            }
            None => raise TypeCheckError("Unknown struct: " + struct_name)
          }
        }
        TypeKind::Any => Type::{ kind: TypeKind::Any, mutable: true }
        TypeKind::TypeVar(_) => raise TypeCheckError("Cannot determine field access on unresolved type variable")
        _ => raise TypeCheckError("Field access expects a struct value")
      }

      LeftValue::{
        kind: LeftValueKind::FieldAccess(resolved_base, field_name),
        ty: field_type
      }
    }
  }
}

fn Context::resolve_left_value(
  self : Context,
  left_value : LeftValue,
  expected_kind : TypeKind,
) -> LeftValue {
  let resolved_kind = self.resolve_type_kind(expected_kind)
  let resolved_type = Type::{ kind: resolved_kind, mutable: left_value.ty.mutable }

  match left_value.kind {
    LeftValueKind::Ident(name) => {
      LeftValue::{
        kind: LeftValueKind::Ident(name),
        ty: resolved_type
      }
    }
    LeftValueKind::ArrayAccess(base_lv, index_expr) => {
      let resolved_base = self.resolve_left_value(base_lv, base_lv.ty.kind)
      let resolved_index = Expr::{
        kind: index_expr.kind,
        ty: self.resolve_type_kind(index_expr.ty)
      }
      LeftValue::{
        kind: LeftValueKind::ArrayAccess(resolved_base, resolved_index),
        ty: resolved_type
      }
    }
    LeftValueKind::FieldAccess(base_lv, field_name) => {
      let resolved_base = self.resolve_left_value(base_lv, base_lv.ty.kind)
      LeftValue::{
        kind: LeftValueKind::FieldAccess(resolved_base, field_name),
        ty: resolved_type
      }
    }
  }
}

fn Context::update_base_left_value_env(self : Context, left_value : LeftValue) -> Unit {
  match left_value.kind {
    LeftValueKind::Ident(name) => {
      self.type_env.set(name, Type::{ kind: self.resolve_type_kind(left_value.ty.kind), mutable: left_value.ty.mutable })
    }
    LeftValueKind::ArrayAccess(base_lv, _) => {
      self.update_base_left_value_env(base_lv)
    }
    LeftValueKind::FieldAccess(base_lv, _) => {
      self.update_base_left_value_env(base_lv)
    }
  }
}
