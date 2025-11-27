///|
pub(all) struct KnfFunction {
  name : String
  ret_ty : Type
  params : Array[(Name, Type)]
  body : KnfBlock
}

///|
pub fn Context::top_function_to_knf(
  self : Context,
  top_func : @typecheck.TopFunction,
) -> KnfFunction raise KnfTransformError {
  // Note: globals are already registered in knf_transform, so we don't check for duplicates here

  self.enter_scope()
  defer { self.exit_scope() }

  let mut params : Array[(Name, Type)] = []
  let mut param_types : Array[Type] = []

  let mut i = 0
  while i < top_func.param_list.length() {
    let param = top_func.param_list[i]

    let param_ty_for_name = self.typekind_to_knf(param.ty)
    let param_name = self.add_new_name(param.name, param_ty_for_name)

    let param_ty_for_type_list = self.typekind_to_knf(param.ty)
    param_types = param_types + [param_ty_for_type_list]

    let param_ty_for_params = self.typekind_to_knf(param.ty)
    params = params + [(param_name, param_ty_for_params)]

    i = i + 1
  }

  // Function type is already registered in globals, no need to set it again

  let body_block = self.block_expr_to_knf(top_func.body)

  let ret_ty = self.typekind_to_knf(top_func.ret_ty)

  KnfFunction::{
    name: top_func.fname,
    ret_ty,
    params,
    body: body_block
  }
}

///|
pub impl Show for KnfFunction with output(self, logger) {
  let { name, ret_ty, params, body } = self
  logger.write_string("fn \{name}")
  if name != "main" {
    logger.write_string("(")
    let param_str = params
      .map(param => {
        let (param_name, param_ty) = param
        "\{param_name}: \{param_ty}"
      })
      .join(", ")
    logger.write_string(param_str)
    logger.write_string(") -> \{ret_ty}")
  }
  logger.write_char(' ')
  logger.write_object(body)
}


///| Convert a top-level function to KNF with a custom name
pub fn Context::top_function_to_knf_with_name(
  self : Context,
  top_func : @typecheck.TopFunction,
  custom_name : String
) -> KnfFunction raise KnfTransformError {
  self.enter_scope()
  defer { self.exit_scope() }

  let mut params : Array[(Name, Type)] = []
  let mut param_types : Array[Type] = []

  let mut i = 0
  while i < top_func.param_list.length() {
    let param = top_func.param_list[i]

    // Apply type substitution recursively
    let param_ty_kind = self.apply_type_substitution(param.ty)
    
    let param_ty_for_name = self.typekind_to_knf(param_ty_kind)
    let param_name = self.add_new_name(param.name, param_ty_for_name)

    let param_ty_for_type_list = self.typekind_to_knf(param_ty_kind)
    param_types = param_types + [param_ty_for_type_list]

    let param_ty_for_params = self.typekind_to_knf(param_ty_kind)
    params = params + [(param_name, param_ty_for_params)]

    i = i + 1
  }

  let body_block = self.block_expr_to_knf(top_func.body)

  // Apply type substitution to return type recursively
  let ret_ty_kind = self.apply_type_substitution(top_func.ret_ty)
  let ret_ty = self.typekind_to_knf(ret_ty_kind)

  KnfFunction::{
    name: custom_name,
    ret_ty,
    params,
    body: body_block
  }
}

///| Convert TypeKind to string for lookup
fn Context::type_to_string(self : Context, ty : @typecheck.TypeKind) -> String {
  match ty {
    @typecheck.TypeKind::Int => "Int"
    @typecheck.TypeKind::Bool => "Bool"
    @typecheck.TypeKind::Double => "Double"
    @typecheck.TypeKind::Unit => "Unit"
    @typecheck.TypeKind::String => "String"
    @typecheck.TypeKind::Struct(name) => name
    @typecheck.TypeKind::Enum(name) => name
    @typecheck.TypeKind::Array(elem) => "Array[" + self.type_to_string(elem) + "]"
    @typecheck.TypeKind::Tuple(types) => {
      let mut result = "("
      let mut i = 0
      while i < types.length() {
        if i > 0 {
          result = result + ", "
        }
        result = result + self.type_to_string(types[i])
        i = i + 1
      }
      result + ")"
    }
    @typecheck.TypeKind::Function(params, ret) => {
      let mut result = "("
      let mut i = 0
      while i < params.length() {
        if i > 0 {
          result = result + ", "
        }
        result = result + self.type_to_string(params[i])
        i = i + 1
      }
      result + ") -> " + self.type_to_string(ret)
    }
    _ => "Unknown"
  }
}


///| Apply type substitution recursively
fn Context::apply_type_substitution(
  self : Context,
  ty : @typecheck.TypeKind
) -> @typecheck.TypeKind {
  match ty {
    @typecheck.TypeKind::Struct(name) => {
      // Check if this is a generic type parameter
      match self.type_substitutions.get(name) {
        Some(substituted) => substituted
        None => ty
      }
    }
    @typecheck.TypeKind::Array(elem_ty) => {
      let substituted_elem = self.apply_type_substitution(elem_ty)
      @typecheck.TypeKind::Array(substituted_elem)
    }
    @typecheck.TypeKind::Tuple(types) => {
      let substituted_types = types.map(fn(t) { self.apply_type_substitution(t) })
      @typecheck.TypeKind::Tuple(substituted_types)
    }
    @typecheck.TypeKind::Function(params, ret) => {
      let substituted_params = params.map(fn(t) { self.apply_type_substitution(t) })
      let substituted_ret = self.apply_type_substitution(ret)
      @typecheck.TypeKind::Function(substituted_params, substituted_ret)
    }
    _ => ty
  }
}
