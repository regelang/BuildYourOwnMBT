///|
pub(all) struct StructDef {
  name : String
  type_params : Array[String]      // 泛型类型参数列表（如 ["T"]）
  fields : Array[StructField]
} derive(Show)

///|
pub(all) struct StructField {
  name : String
  ty : Type
} derive(Show)

///|
pub fn StructDef::get_field_type(self : Self, field_name : String) -> Type? {
  for field in self.fields {
    if field.name == field_name {
      return Some(field.ty)
    }
  }
  return None
}

///|

///|
pub fn Context::check_struct_def(
  self : Self,
  struct_def : @parser.StructDef,
) -> StructDef raise TypeCheckError {
  // Check for circular dependencies using a set of currently checking structs
  if self.checking_structs.contains(struct_def.name) {
    raise TypeCheckError("Circular dependency detected in struct " + struct_def.name)
  }
  // Create a new set with the current struct name added
  let new_checking_structs = Set::new()
  new_checking_structs.add(struct_def.name)  // This modifies the set in place
  
  // Create a new context with the updated checking_structs set
  let new_ctx = Context::{
    type_env: self.type_env,
    type_vars: self.type_vars,
    struct_defs: self.struct_defs,
    enum_defs: self.enum_defs,
    func_types: self.func_types,
    current_func_ret_ty: self.current_func_ret_ty,
    checking_structs: new_checking_structs,
    generic_functions: self.generic_functions,
    monomorphized_instances: self.monomorphized_instances,
    current_generic_type: self.current_generic_type,
    generic_type_bindings: self.generic_type_bindings,
    generic_recursion_counter: self.generic_recursion_counter,
    checking_generic_function_body: self.checking_generic_function_body,
  }
  
  // Convert each field in the struct definition
  let fields = struct_def.fields.map(fn(field) {
    // Get the type kind from the parser's type
    let type_kind = new_ctx.check_parser_typekind(field.ty.kind)
    
    // Check for direct self-reference
    match type_kind {
      TypeKind::Struct(name) => {
        if name == struct_def.name {
          raise TypeCheckError("Circular dependency detected in struct " + struct_def.name)
        }
      }
      _ => ()
    }
    
    // Create a new Type with the correct mutability
    let ty = Type::{
      kind: type_kind,
      mutable: field.is_mut
    }
    
    // Create a new StructField with the checked type
    StructField::{
      name: field.name,
      ty: ty
    }
  })
  
  // Create the new struct definition and store it in the context
  let checked_struct = StructDef::{
    name: struct_def.name,
    type_params: struct_def.type_params,  // Include type parameters
    fields: fields
  }

  self.struct_defs.set(struct_def.name, checked_struct)
  checked_struct
}
