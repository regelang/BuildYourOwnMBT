///|
pub(all) struct Param {
  name : String
  ty : TypeKind
} derive(Show)

///|
pub(all) struct TopFunction {
  fname : String
  param_list : Array[Param]
  ret_ty : TypeKind
  body : BlockExpr
} derive(Show)

///|
pub fn Context::check_top_function(
  self : Context,
  func : @parser.TopFunction,
) -> TopFunction raise TypeCheckError {
  // Handle generic functions - register the type parameter temporarily
  let is_generic = func.type_params.length() > 0
  if is_generic {
    // Register the generic type parameter as a placeholder struct
    if func.type_params.length() > 0 {
      let type_param = func.type_params[0]  // For simplicity, use the first type parameter
      let generic_struct = StructDef::{
        name: type_param,
        type_params: [],
        fields: []
      }
      self.struct_defs.set(type_param, generic_struct)
    }
  }
  
  // Set flag to indicate we're checking a generic function body
  let prev_checking_generic = self.checking_generic_function_body
  if is_generic {
    self.checking_generic_function_body = true
  }
  defer {
    self.checking_generic_function_body = prev_checking_generic
  }
  
  let mut checked_params : Array[Param] = []
  let mut resolved_param_types : Array[TypeKind] = []
  let mut param_bindings : Array[(String, Type)] = []

  let mut i = 0
  while i < func.param_list.length() {
    let param = func.param_list[i]
    let parsed_kind = self.check_parser_typekind(param.ty.kind)
    let resolved_kind = self.resolve_type_kind(parsed_kind)
    checked_params = checked_params + [Param::{ name: param.name, ty: resolved_kind }]
    resolved_param_types = resolved_param_types + [resolved_kind]
    param_bindings = param_bindings + [(param.name, Type::{ kind: resolved_kind, mutable: false })]
    i = i + 1
  }

  let ret_kind_annot = self.check_parser_typekind(func.ret_ty.kind)
  let resolved_ret_kind = self.resolve_type_kind(ret_kind_annot)

  let func_type_kind = TypeKind::Function(resolved_param_types, resolved_ret_kind)
  self.func_types.set(func.fname, func_type_kind)
  self.type_env.set(func.fname, Type::{ kind: func_type_kind, mutable: false })

  let prev_ret_kind = self.current_func_ret_ty
  self.current_func_ret_ty = Some(ret_kind_annot)
  defer { self.current_func_ret_ty = prev_ret_kind }

  // Clear generic type bindings before checking function body
  self.generic_type_bindings.clear()
  self.generic_recursion_counter.clear()

  self.enter_scope()
  defer { self.exit_scope() }

  let mut j = 0
  while j < param_bindings.length() {
    let (param_name, param_type) = param_bindings[j]
    self.type_env.set(param_name, param_type)
    j = j + 1
  }

  let checked_body = self.check_block_expr(func.body)

  let resolved_body_ty = self.resolve_type_kind(checked_body.ty)

  // Check if function body type matches declared return type
  // The body type should be compatible with the declared return type
  let type_compatible = self.is_type_compatible(resolved_ret_kind, resolved_body_ty)
  
  // Debug: Print the types for debugging
  println("Function: " + func.fname)
  println("Declared return type: " + resolved_ret_kind.to_string())
  println("Body type: " + resolved_body_ty.to_string())
  
  if !type_compatible {
    raise TypeCheckError("Function body type does not match declared return type")
  }

  TopFunction::{
    fname: func.fname,
    param_list: checked_params,
    ret_ty: resolved_ret_kind,
    body: BlockExpr::{ stmts: checked_body.stmts, ty: resolved_body_ty }
  }
}


///|
pub fn Context::check_generic_function(
  self : Context,
  func : @parser.TopFunction,
  type_param : String,
) -> TopFunction raise TypeCheckError {
  // For generic functions, we create a placeholder that accepts any type
  // The actual monomorphization will happen when we see the function calls
  
  let mut checked_params : Array[Param] = []
  let mut resolved_param_types : Array[TypeKind] = []
  
  let mut i = 0
  while i < func.param_list.length() {
    let param = func.param_list[i]
    // For generic type parameters, use TypeVar as placeholder
    let param_kind = if self.is_generic_type(param.ty.kind, type_param) {
      TypeKind::TypeVar(0)  // Use TypeVar(0) as placeholder for generic type
    } else {
      let parsed_kind = self.check_parser_typekind(param.ty.kind)
      self.resolve_type_kind(parsed_kind)
    }
    checked_params = checked_params + [Param::{ name: param.name, ty: param_kind }]
    resolved_param_types = resolved_param_types + [param_kind]
    i = i + 1
  }

  let ret_kind = if self.is_generic_type(func.ret_ty.kind, type_param) {
    TypeKind::TypeVar(0)
  } else {
    let parsed_kind = self.check_parser_typekind(func.ret_ty.kind)
    self.resolve_type_kind(parsed_kind)
  }

  // Create a simple body placeholder
  let body = BlockExpr::{
    stmts: [],
    ty: ret_kind
  }

  TopFunction::{
    fname: func.fname,
    param_list: checked_params,
    ret_ty: ret_kind,
    body: body
  }
}

///|
fn Context::is_generic_type(
  self : Context,
  ty : @parser.TypeKind,
  type_param : String
) -> Bool {
  match ty {
    @parser.TypeKind::Defined(name) => name == type_param
    @parser.TypeKind::Array(elem_ty) => self.is_generic_type(elem_ty, type_param)
    @parser.TypeKind::Tuple(types) => {
      let mut i = 0
      while i < types.length() {
        if self.is_generic_type(types[i], type_param) {
          return true
        }
        i = i + 1
      }
      false
    }
    @parser.TypeKind::Function(params, ret) => {
      // Check if any parameter type contains the generic type parameter
      let mut i = 0
      while i < params.length() {
        if self.is_generic_type(params[i], type_param) {
          return true
        }
        i = i + 1
      }
      // Check if the return type contains the generic type parameter
      self.is_generic_type(ret, type_param)
    }
    _ => false
  }
}
