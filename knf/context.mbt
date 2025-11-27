///|
pub(all) suberror KnfTransformError String derive(Show)

///|
pub typealias @either.Either

///|
pub(all) struct Name {
  id : String
  slot : Int
} derive(Hash, Eq)

///|
pub fn Name::wildcard() -> Name {
  Name::{ id: "_", slot: 0 }
}

///|
pub impl Show for Name with output(self, logger) {
  logger.write_string(self.id)
  if self.slot > 0 {
    logger.write_string("$\{self.slot}")
  }
}

///|
pub(all) struct Env {
  local_ : Map[String, (Name, Type)] // defined in this scope
  capture : Map[Name, Type] // captured from outer scopes
  parent : Env?
}

///|
pub fn Env::new(parent? : Env? = None) -> Env {
  Env::{ local_: Map::new(), capture: Map::new(), parent }
}

///|
pub fn Env::get_name_type(self : Env, name : Name) -> Type? {
  let { id, .. } = name
  match self.local_.get(id) {
    Some((_, t)) => Some(t)
    None =>
      match self.parent {
        Some(p) => p.get_name_type(name)
        None => None
      }
  }
}

///|
pub fn Env::get(self : Env, name : String) -> Name? {
  match self.local_.get(name) {
    Some((n, _)) => Some(n)
    None =>
      match self.parent {
        Some(p) => p.get(name)
        None => None
      }
  }
}

///|
pub fn Env::set(self : Env, s : String, name : Name, ty : Type) -> Unit {
  self.local_.set(s, (name, ty))
}

///|
pub fn Env::record_capture(self : Env, name : Name, ty : Type) -> Unit {
  self.capture.set(name, ty)
}

///|
pub(all) struct Context {
  mut name_env : Env
  capture : Array[Name]
  globals : Map[String, Type]
  mut temp_counter : Int
  enum_defs : Map[String, @typecheck.EnumDef]  // 枚举定义，用于查找字段类型
  generic_functions : Map[String, @typecheck.TopFunction]  // 泛型函数定义
  mut monomorphized_functions : Map[String, KnfFunction]  // 单态化后的函数
  mut type_substitutions : Map[String, @typecheck.TypeKind]  // 当前的类型替换映射 (T -> Int)
}

///|
pub fn Context::new() -> Context {
  Context::{ 
    name_env: Env::new(), 
    capture: Array::new(), 
    globals: Map::new(), 
    temp_counter: 0, 
    enum_defs: Map::new(),
    generic_functions: Map::new(),
    monomorphized_functions: Map::new(),
    type_substitutions: Map::new(),
  }
}

///|
pub fn Context::lookup_name(self : Context, name_str : String) -> (Name, Type)? {
  // First check current environment (including parent chain)
  match self.lookup_name_and_capture(self.name_env, name_str) {
    Some(result) => Some(result)
    None => {
      // Then check globals
      match self.globals.get(name_str) {
        Some(ty) => Some((Name::{ id: name_str, slot: 0 }, ty))
        None => None
      }
    }
  }
}

///| Check if a name is an enum constructor
pub fn Context::is_enum_constructor(self : Context, name_str : String) -> Bool {
  for _enum_name, enum_def in self.enum_defs {
    for variant in enum_def.variants {
      if variant.name == name_str {
        return true
      }
    }
  }
  false
}

///|
pub fn Context::lookup_name_and_capture(
  self : Context,
  env : Env,
  name_str : String,
) -> (Name, Type)? {
  match env.local_.get(name_str) {
    Some((stored_name, stored_ty)) => Some((stored_name, stored_ty))
    None =>
      match env.parent {
        Some(parent_env) => {
          match self.lookup_name_and_capture(parent_env, name_str) {
            Some((found_name, found_ty)) => {
              env.record_capture(found_name, found_ty)
              Some((found_name, found_ty))
            }
            None => None
          }
        }
        None => None
      }
  }
}

///|
pub fn Context::lookup_name_in_parent(self : Context, name_str : String) -> (Name, Type)? {
  let mut current_env = self.name_env.parent
  while current_env is Some(env) {
    match env.local_.get(name_str) {
      Some((parent_name, parent_ty)) => return Some((parent_name, parent_ty))
      None => current_env = env.parent
    }
  }
  None
}

///|
pub fn Context::enter_scope(self : Context) -> Unit {
  let sub_env = Env::new(parent=Some(self.name_env))
  self.name_env = sub_env
}

///|
pub fn Context::exit_scope(self : Context) -> Unit {
  self.name_env = match self.name_env.parent {
    Some(p) => p
    None => self.name_env
  }
}

///|
pub fn Context::add_new_name(self : Context, s : String, ty : Type) -> Name {
  match self.name_env.get(s) {
    Some({ id, slot }) => {
      let name = Name::{ id, slot: slot + 1 }
      self.name_env.set(s, name, ty)
      name
    }
    None => {
      let name = Name::{ id: s, slot: 0 }
      self.name_env.set(s, name, ty)
      name
    }
  }
}

///|
pub fn Context::add_temp(self : Context, _ty : Type) -> Name {
  let temp_id = "tmp"
  let counter = self.temp_counter
  self.temp_counter = counter + 1
  Name::{ id: temp_id, slot: counter }
}


///| Check if a function is generic (has generic type parameters)
pub fn Context::is_generic_function(
  self : Context,
  func : @typecheck.TopFunction
) -> Bool {
  // Check if any parameter type is a generic type (empty struct)
  let mut i = 0
  while i < func.param_list.length() {
    if self.is_generic_type(func.param_list[i].ty) {
      return true
    }
    i = i + 1
  }
  
  // Check return type
  self.is_generic_type(func.ret_ty)
}

///| Check if a type is generic (contains generic type parameters)
fn Context::is_generic_type(self : Context, ty : @typecheck.TypeKind) -> Bool {
  match ty {
    @typecheck.TypeKind::Struct(name) => {
      // Check if this is an empty struct (generic type parameter)
      // We don't have access to struct_defs here, so we use a heuristic:
      // Generic type parameters are typically single uppercase letters
      name.length() == 1 && name[0] >= 'A' && name[0] <= 'Z'
    }
    @typecheck.TypeKind::Array(elem_ty) => self.is_generic_type(elem_ty)
    @typecheck.TypeKind::Tuple(types) => {
      let mut i = 0
      while i < types.length() {
        if self.is_generic_type(types[i]) {
          return true
        }
        i = i + 1
      }
      false
    }
    @typecheck.TypeKind::Function(params, ret) => {
      let mut i = 0
      while i < params.length() {
        if self.is_generic_type(params[i]) {
          return true
        }
        i = i + 1
      }
      self.is_generic_type(ret)
    }
    _ => false
  }
}


///| Monomorphize a generic function for specific argument types
pub fn Context::monomorphize_function(
  self : Context,
  generic_func : @typecheck.TopFunction,
  arg_types : Array[Type]
) -> String raise KnfTransformError {
  // Generate a unique name for this monomorphized version
  let mut mono_name = generic_func.fname
  let mut i = 0
  while i < arg_types.length() {
    mono_name = mono_name + "_" + self.type_to_mangled_string(arg_types[i])
    i = i + 1
  }
  
  // Check if we've already monomorphized this version
  if self.monomorphized_functions.get(mono_name) is Some(_) {
    return mono_name
  }
  
  // Create type substitution map by unifying parameter types with argument types
  let old_substitutions = self.type_substitutions
  self.type_substitutions = Map::new()
  
  // Unify each parameter type with its corresponding argument type
  let mut pi = 0
  while pi < generic_func.param_list.length() && pi < arg_types.length() {
    let param_ty = generic_func.param_list[pi].ty
    let arg_ty = self.knf_type_to_typekind(arg_types[pi])
    
    // Unify the types to extract generic type bindings
    self.unify_types_for_generics(param_ty, arg_ty)
    
    pi = pi + 1
  }
  
  // Convert the generic function with type substitution
  let mono_func = self.top_function_to_knf_with_name(generic_func, mono_name)
  
  // Restore old substitutions
  self.type_substitutions = old_substitutions
  
  // Store the monomorphized function
  self.monomorphized_functions.set(mono_name, mono_func)
  
  mono_name
}

///| Unify two types to extract generic type bindings
///| For example: unify Array[T] with Array[Int] => T = Int
fn Context::unify_types_for_generics(
  self : Context,
  param_ty : @typecheck.TypeKind,
  arg_ty : @typecheck.TypeKind
) -> Unit {
  match (param_ty, arg_ty) {
    (@typecheck.TypeKind::Struct(name), concrete_ty) => {
      // Check if this is a generic type parameter (single uppercase letter)
      if name.length() == 1 && name[0] >= 'A' && name[0] <= 'Z' {
        // This is a generic type parameter - bind it to the concrete type
        self.type_substitutions.set(name, concrete_ty)
      }
    }
    (@typecheck.TypeKind::Array(param_elem), @typecheck.TypeKind::Array(arg_elem)) => {
      // Recursively unify array element types
      self.unify_types_for_generics(param_elem, arg_elem)
    }
    (@typecheck.TypeKind::Tuple(param_types), @typecheck.TypeKind::Tuple(arg_types)) => {
      // Recursively unify tuple element types
      let mut i = 0
      while i < param_types.length() && i < arg_types.length() {
        self.unify_types_for_generics(param_types[i], arg_types[i])
        i = i + 1
      }
    }
    (@typecheck.TypeKind::Function(param_params, param_ret), @typecheck.TypeKind::Function(arg_params, arg_ret)) => {
      // Recursively unify function parameter and return types
      let mut i = 0
      while i < param_params.length() && i < arg_params.length() {
        self.unify_types_for_generics(param_params[i], arg_params[i])
        i = i + 1
      }
      self.unify_types_for_generics(param_ret, arg_ret)
    }
    _ => ()  // Types match or no generic parameters
  }
}

///| Convert KNF type back to TypeKind (for type substitution)
fn Context::knf_type_to_typekind(self : Context, ty : Type) -> @typecheck.TypeKind {
  match ty {
    Type::Int => @typecheck.TypeKind::Int
    Type::Bool => @typecheck.TypeKind::Bool
    Type::Double => @typecheck.TypeKind::Double
    Type::Unit => @typecheck.TypeKind::Unit
    Type::String => @typecheck.TypeKind::String
    Type::Array(elem) => @typecheck.TypeKind::Array(self.knf_type_to_typekind(elem))
    Type::Struct(name) => @typecheck.TypeKind::Struct(name)
    Type::Enum(name) => @typecheck.TypeKind::Enum(name)
    Type::Tuple(types) => {
      let type_kinds = types.map(fn(t) { self.knf_type_to_typekind(t) })
      @typecheck.TypeKind::Tuple(type_kinds)
    }
    Type::Function(params, ret) => {
      let param_kinds = params.map(fn(t) { self.knf_type_to_typekind(t) })
      let ret_kind = self.knf_type_to_typekind(ret)
      @typecheck.TypeKind::Function(param_kinds, ret_kind)
    }
  }
}

///| Mangle a type name for use in function names
fn Context::type_to_mangled_string(self : Context, ty : Type) -> String {
  match ty {
    Type::Int => "Int"
    Type::Bool => "Bool"
    Type::Double => "Double"
    Type::Unit => "Unit"
    Type::String => "String"
    Type::Array(elem) => "Array_" + self.type_to_mangled_string(elem)
    Type::Struct(name) => name
    Type::Enum(name) => name
    Type::Tuple(types) => {
      let mut result = "Tuple"
      let mut i = 0
      while i < types.length() {
        result = result + "_" + self.type_to_mangled_string(types[i])
        i = i + 1
      }
      result
    }
    Type::Function(_, _) => "Func"
  }
}
