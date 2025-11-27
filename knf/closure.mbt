///|
pub(all) struct KnfClosure {
  name : Name
  params : Array[(Name, Type)]
  ret_ty : Type
  body : KnfBlock
  captured_vars : Map[Name, Type]
}

///|
pub fn KnfClosure::to_string(self : KnfClosure, ident? : Int = 0) -> String {
  let sb = StringBuilder::new()
  let indent_str = " ".repeat(ident)
  if !self.captured_vars.is_empty() {
    sb.write_string("// Captured variables: \n")
    for name, ty in self.captured_vars {
      sb.write_string(indent_str)
      sb.write_string("// - \{name} : \{ty}\n")
    }
    sb.write_string(indent_str)
    sb.write_string("fn \{self.name}(")
  } else {
    sb.write_string("fn \{self.name}(")
  }
  let param_strs = self.params.map(name_ty => {
    let (name, ty) = name_ty
    "\{name} : \{ty}"
  })
  sb.write_string(param_strs.join(", "))
  sb.write_string(") -> \{self.ret_ty} ")
  sb.write_string(self.body.to_string(ident))
  sb.to_string()
}

///|
pub fn Context::local_function_to_knf(
  self : Context,
  local_function : @typecheck.LocalFunction,
) -> KnfClosure raise KnfTransformError {
  // Prepare parameter type information for function signature (outer scope)
  let mut param_specs : Array[(String, Type)] = []
  let mut param_types : Array[Type] = []

  let mut i = 0
  while i < local_function.param_list.length() {
    let (param_name_str, param_ty_typecheck) = local_function.param_list[i]
    let param_ty_knf = self.type_to_knf(param_ty_typecheck)
    param_specs = param_specs + [(param_name_str, param_ty_knf)]
    param_types = param_types + [param_ty_knf]
    i = i + 1
  }

  let ret_ty = self.type_to_knf(local_function.ret_ty)
  let function_ty = Type::Function(param_types, ret_ty)

  // Register closure name in current scope so nested closures can refer to it if needed
  let closure_name = self.add_new_name(local_function.fname, function_ty)

  // Transform body within a new scope
  self.enter_scope()
  defer { self.exit_scope() }

  // Make function name available inside its own body (for recursion) without marking as capture
  self.name_env.set(local_function.fname, closure_name, function_ty)

  // Register parameters inside the closure scope
  let mut params : Array[(Name, Type)] = []
  let mut j = 0
  while j < param_specs.length() {
    let (param_name_str, param_ty) = param_specs[j]
    let param_name = self.add_new_name(param_name_str, param_ty)
    params = params + [(param_name, param_ty)]
    j = j + 1
  }

  let body_block = self.block_expr_to_knf(local_function.body)

  let captured_entries = self.name_env.capture.to_array()
  let captured_vars : Map[Name, Type] = Map::new()
  let mut k = 0
  while k < captured_entries.length() {
    let (captured_name, captured_ty) = captured_entries[k]
    captured_vars.set(captured_name, captured_ty)
    k = k + 1
  }

  KnfClosure::{
    name: closure_name,
    params,
    ret_ty,
    body: body_block,
    captured_vars
  }
}
