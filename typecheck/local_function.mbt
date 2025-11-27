///|
pub(all) struct LocalFunction {
  fname : String
  param_list : Array[(String, Type)]
  ret_ty : Type
  body : BlockExpr
} derive(Show)

///|
pub fn Context::check_local_function(
  self : Context,
  func : @parser.LocalFunction,
) -> LocalFunction raise TypeCheckError {
  let mut raw_params : Array[(String, Type)] = []
  let mut param_type_kinds : Array[TypeKind] = []

  let mut i = 0
  while i < func.param_list.length() {
    let (param_name, param_type_opt) = func.param_list[i]
    let ty = match param_type_opt {
      Some(parser_ty) => self.check_parser_type(parser_ty)
      None => Type::{ kind: self.allocate_fresh_type_var(), mutable: false }
    }
    raw_params = raw_params + [(param_name, ty)]
    param_type_kinds = param_type_kinds + [ty.kind]
    i = i + 1
  }

  let ret_type = match func.ret_ty {
    Some(parser_ty) => self.check_parser_type(parser_ty)
    None => Type::{ kind: self.allocate_fresh_type_var(), mutable: false }
  }

  let function_ty_kind = TypeKind::Function(param_type_kinds, ret_type.kind)

  let prev_ret_ty = self.current_func_ret_ty
  self.current_func_ret_ty = Some(ret_type.kind)
  defer { self.current_func_ret_ty = prev_ret_ty }

  self.enter_scope()
  let mut scope_active = true
  defer {
    if scope_active {
      self.exit_scope()
    }
  }

  // Add the function name to the scope BEFORE checking the body
  // This allows the function to call itself recursively
  self.type_env.set(func.fname, Type::{ kind: function_ty_kind, mutable: false })

  let mut j = 0
  while j < raw_params.length() {
    let (param_name, param_type) = raw_params[j]
    self.type_env.set(param_name, param_type)
    j = j + 1
  }

  let checked_body = self.check_block_expr(func.body)

  // Resolve both the declared return type and the body type so any generic
  // bindings (e.g. T -> Int) are applied before we check compatibility.
  let expected_kind = self.resolve_type_kind(ret_type.kind)
  let body_kind = self.resolve_type_kind(checked_body.ty)

  if !self.is_type_compatible(expected_kind, body_kind) {
    raise TypeCheckError("Local function body type does not match return type")
  }

  let mut resolved_params : Array[(String, Type)] = []
  let mut resolved_param_kinds : Array[TypeKind] = []

  let mut k = 0
  while k < raw_params.length() {
    let (param_name, param_type) = raw_params[k]
    let resolved_kind = self.resolve_type_kind(param_type.kind)
    let resolved_type = Type::{ kind: resolved_kind, mutable: param_type.mutable }
    resolved_params = resolved_params + [(param_name, resolved_type)]
    resolved_param_kinds = resolved_param_kinds + [resolved_kind]
    k = k + 1
  }

  let resolved_ret_kind = expected_kind
  let resolved_function_ty = TypeKind::Function(resolved_param_kinds, resolved_ret_kind)

  // If we're inside a generic function body, apply any current bindings so local
  // functions see the concrete instantiations (e.g. Array[T] -> Array[Int]).
  let mut final_params = resolved_params
  let mut final_ret_kind = resolved_ret_kind
  let mut final_func_ty = resolved_function_ty
  let mut final_body_ty = body_kind
  if self.checking_generic_function_body && !self.generic_type_bindings.is_empty() {
    let type_param_map = self.generic_type_bindings.copy()
    let mut fp : Array[(String, Type)] = []
    let mut i = 0
    while i < final_params.length() {
      let (param_name, param_type) = final_params[i]
      let substituted_kind = self.substitute_type_kind_with_map(param_type.kind, type_param_map)
      fp = fp + [(param_name, Type::{ kind: substituted_kind, mutable: param_type.mutable })]
      i = i + 1
    }
    final_params = fp
    final_ret_kind = self.substitute_type_kind_with_map(resolved_ret_kind, type_param_map)
    final_func_ty = self.substitute_type_kind_with_map(resolved_function_ty, type_param_map)
    final_body_ty = self.substitute_type_kind_with_map(body_kind, type_param_map)
  }

  self.exit_scope()
  scope_active = false
  // Add the local function to the current scope so it can be called
  self.type_env.set(func.fname, Type::{ kind: final_func_ty, mutable: false })

  let resolved_body = BlockExpr::{
    stmts: checked_body.stmts,
    ty: final_body_ty
  }

  LocalFunction::{
    fname: func.fname,
    param_list: final_params,
    ret_ty: Type::{ kind: final_ret_kind, mutable: false },
    body: resolved_body
  }
}
