///|
pub(all) struct Type {
  kind : TypeKind
  mutable : Bool
} derive(Show)

///|
pub(all) enum TypeKind {
  Unit
  Bool
  Int
  Double
  String
  Tuple(Array[TypeKind])
  Array(TypeKind)
  Function(Array[TypeKind], TypeKind)
  Struct(String)
  Enum(String)  // 枚举类型，存储枚举名称
  // Generic struct type with type arguments
  GenericStruct(String, Array[TypeKind])
  // Generic enum type with type arguments
  GenericEnum(String, Array[TypeKind])
  Any
  TypeVar(Int)
} derive(Hash)

///|
pub fn Context::check_parser_typekind(
  self : Context,
  ty : @parser.TypeKind,
) -> TypeKind raise TypeCheckError {
  match ty {
    @parser.TypeKind::Unit => TypeKind::Unit
    @parser.TypeKind::Bool => TypeKind::Bool
    @parser.TypeKind::Int => TypeKind::Int
    @parser.TypeKind::Double => TypeKind::Double
    @parser.TypeKind::String => TypeKind::String
    @parser.TypeKind::Tuple(types) => {
      TypeKind::Tuple(types.map(fn(t) { self.check_parser_typekind(t) }))
    }
    @parser.TypeKind::Array(elem_ty) => {
      TypeKind::Array(self.check_parser_typekind(elem_ty))
    }
    @parser.TypeKind::Function(param_tys, ret_ty) => {
      TypeKind::Function(
        param_tys.map(fn(t) { self.check_parser_typekind(t) }),
        self.check_parser_typekind(ret_ty)
      )
    }
    @parser.TypeKind::GenericEnum(name, type_args) => {
      let checked_args = type_args.map(fn(t) { self.check_parser_typekind(t) })

      // Treat the parsed generic name as a struct when a struct definition exists so
      // that generic struct field and method resolution can succeed during type checking.
      if self.struct_defs.get(name) is Some(_) {
        TypeKind::GenericStruct(name, checked_args)
      } else if self.enum_defs.get(name) is Some(_) {
        TypeKind::GenericEnum(name, checked_args)
      } else {
        TypeKind::GenericEnum(name, checked_args)
      }
    }
    @parser.TypeKind::Defined(name) => {
      // First check if it's a generic type parameter (single uppercase letter)
      if name.length() == 1 && {
        name == "T" || name == "K" || name == "V" || name == "E" || name == "R" || 
        name == "A" || name == "B" || name == "C" || name == "D" || name == "F" ||
        name == "G" || name == "H" || name == "I" || name == "J" || name == "L" ||
        name == "M" || name == "N" || name == "O" || name == "P" || name == "Q" ||
        name == "S" || name == "U" || name == "W" || name == "X" || name == "Y" || name == "Z"
      } {
        // This is a generic type parameter
        TypeKind::Struct(name)
      } else {
        // Look up the name in the type environment
        match self.type_env.get(name) {
          Some(ty) => {
            // If it's in the type environment, return its kind
            ty.kind
          }
          None => {
            // Check if it's a struct or enum
            if self.struct_defs.get(name) is Some(_) {
              TypeKind::Struct(name)
            } else if self.enum_defs.get(name) is Some(_) {
              TypeKind::Enum(name)
            } else {
              raise TypeCheckError("Unknown type: " + name)
            }
          }
        }
      }
    }
  }
}

///| Helper method to check tuple types recursively
fn Context::check_tuple_types(
  self: Context,
  types_a: Array[TypeKind],
  types_b: Array[TypeKind],
  visited: Array[(TypeKind, TypeKind)],
  index: Int
) -> Bool raise TypeCheckError {
  if index >= types_a.length() {
    true
  } else {
    let compatible = self.is_type_compatible_with_cycle(types_a[index], types_b[index], visited)
    if compatible {
      self.check_tuple_types(types_a, types_b, visited, index + 1)
    } else {
      false
    }
  }
}

///| Helper method to check function parameters recursively
fn Context::check_function_params(
  self: Context,
  params_a: Array[TypeKind],
  params_b: Array[TypeKind],
  visited: Array[(TypeKind, TypeKind)],
  index: Int
) -> Bool raise TypeCheckError {
  if index >= params_a.length() {
    true
  } else {
    let compatible = self.is_type_compatible_with_cycle(params_a[index], params_b[index], visited)
    if compatible {
      self.check_function_params(params_a, params_b, visited, index + 1)
    } else {
      false
    }
  }
}

///|
pub fn Context::check_parser_type(
  self : Context,
  ty : @parser.Type,
  mutable? : Bool = false,
) -> Type raise TypeCheckError {
  Type::{
    kind: self.check_parser_typekind(ty.kind),
    mutable: mutable
  }
}

/// Helper function to resolve a type variable to its concrete type
fn Context::resolve_type_var(self: Context, id: Int) -> TypeKind {
  match self.type_vars.get(id) {
    Some(TypeVar(other_id)) if other_id != id => {
      // Add cycle detection to prevent infinite recursion
      let resolved = self.resolve_type_var_with_cycle(other_id, [id])
      self.type_vars.set(id, resolved)
      resolved
    }
    Some(ty) => ty
    None => TypeVar(id)
  }
}

/// Helper function to resolve type variable with cycle detection
fn Context::resolve_type_var_with_cycle(self: Context, id: Int, visited: Array[Int]) -> TypeKind {
  // Limit recursion depth to prevent stack overflow
  if visited.length() > 500 {
    println("WARNING: Hit recursion depth limit in resolve_type_var_with_cycle");
    return TypeVar(id)  // Return original if we've gone too deep
  }
  
  match self.type_vars.get(id) {
    Some(TypeVar(other_id)) if other_id != id => {
      // Check for cycles
      for i = 0; i < visited.length(); i = i + 1 {
        if visited[i] == other_id {
          // Cycle detected - return the original type variable
          return TypeVar(id)
        }
      }
      let new_visited = visited.copy()
      new_visited.push(id)
      let resolved = self.resolve_type_var_with_cycle(other_id, new_visited)
      self.type_vars.set(id, resolved)
      resolved
    }
    Some(ty) => ty
    None => TypeVar(id)
  }
}

fn Context::update_dependents(self: Context, root_id: Int, ty: TypeKind) -> Unit {
  self.update_dependents_with_cycle(root_id, ty, [])
}

fn Context::update_dependents_with_cycle(self: Context, root_id: Int, ty: TypeKind, visited: Array[Int]) -> Unit {
  // Limit recursion depth to prevent stack overflow
  if visited.length() > 500 {
    println("WARNING: Hit recursion depth limit in update_dependents_with_cycle");
    return
  }
  
  // Check for cycles
  for i = 0; i < visited.length(); i = i + 1 {
    if visited[i] == root_id {
      return
    }
  }
  
  let new_visited = visited.copy()
  new_visited.push(root_id)
  
  let mut id = 0
  while id < 256 {
    let _ = match self.type_vars.get(id) {
      Some(TypeVar(var_id)) if var_id == root_id => {
        // Only update if it's not the same variable to avoid infinite recursion
        if id != root_id {
          self.type_vars.set(id, ty)
          self.update_dependents_with_cycle(id, ty, new_visited)
        }
        ()
      }
      _ => ()
    }
    id = id + 1
  }
}

///| Check if a type contains a specific generic type parameter (occurs check)
fn contains_generic_param(ty: TypeKind, param_name: String) -> Bool {
  contains_generic_param_with_cycle(ty, param_name, [])
}

fn contains_generic_param_with_cycle(ty: TypeKind, param_name: String, visited: Array[TypeKind]) -> Bool {
  // Check for cycles to prevent infinite recursion
  for i = 0; i < visited.length(); i = i + 1 {
    if types_equal_simple(ty, visited[i]) {
      return false  // Cycle detected, assume no containment to avoid infinite recursion
    }
  }
  
  let new_visited = visited.copy()
  new_visited.push(ty)
  
  match ty {
    TypeKind::Struct(name) => name == param_name
    TypeKind::Tuple(types) => {
      let mut i = 0
      let mut found = false
      while i < types.length() && !found {
        found = contains_generic_param_with_cycle(types[i], param_name, new_visited)
        i = i + 1
      }
      found
    }
    TypeKind::Array(elem_type) => contains_generic_param_with_cycle(elem_type, param_name, new_visited)
    TypeKind::Function(param_types, return_type) => {
      let mut i = 0
      let mut found = false
      while i < param_types.length() && !found {
        found = contains_generic_param_with_cycle(param_types[i], param_name, new_visited)
        i = i + 1
      }
      found || contains_generic_param_with_cycle(return_type, param_name, new_visited)
    }
    TypeKind::GenericEnum(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = contains_generic_param_with_cycle(type_args[i], param_name, new_visited)
        i = i + 1
      }
      found
    }
    TypeKind::GenericStruct(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = contains_generic_param_with_cycle(type_args[i], param_name, new_visited)
        i = i + 1
      }
      found
    }
    _ => false
  }
}

///| Check if a type contains a specific type variable (occurs check)
fn contains_type_var(ty: TypeKind, var_id: Int) -> Bool {
  contains_type_var_with_cycle(ty, var_id, [])
}

fn contains_type_var_with_cycle(ty: TypeKind, var_id: Int, visited: Array[TypeKind]) -> Bool {
  // Check for cycles to prevent infinite recursion
  for i = 0; i < visited.length(); i = i + 1 {
    if types_equal_simple(ty, visited[i]) {
      return false  // Cycle detected, assume no containment to avoid infinite recursion
    }
  }
  
  let new_visited = visited.copy()
  new_visited.push(ty)
  
  match ty {
    TypeKind::TypeVar(id) => id == var_id
    TypeKind::Tuple(types) => {
      let mut i = 0
      let mut found = false
      while i < types.length() && !found {
        found = contains_type_var_with_cycle(types[i], var_id, new_visited)
        i = i + 1
      }
      found
    }
    TypeKind::Array(elem_type) => contains_type_var_with_cycle(elem_type, var_id, new_visited)
    TypeKind::Function(param_types, return_type) => {
      let mut i = 0
      let mut found = false
      while i < param_types.length() && !found {
        found = contains_type_var_with_cycle(param_types[i], var_id, new_visited)
        i = i + 1
      }
      found || contains_type_var_with_cycle(return_type, var_id, new_visited)
    }
    TypeKind::GenericEnum(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = contains_type_var_with_cycle(type_args[i], var_id, new_visited)
        i = i + 1
      }
      found
    }
    TypeKind::GenericStruct(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = contains_type_var_with_cycle(type_args[i], var_id, new_visited)
        i = i + 1
      }
      found
    }
    _ => false
  }
}

/// Simple structural equality check without recursion
fn types_equal_simple(a: TypeKind, b: TypeKind) -> Bool {
  match (a, b) {
    (Unit, Unit) => true
    (Bool, Bool) => true
    (Int, Int) => true
    (Double, Double) => true
    (String, String) => true
    (Struct(name_a), Struct(name_b)) => name_a == name_b
    (Enum(name_a), Enum(name_b)) => name_a == name_b
    (Any, Any) => true
    (TypeVar(id_a), TypeVar(id_b)) => id_a == id_b
    _ => false
  }
}

/// Helper function to set a type variable to a type and propagate dependencies
fn Context::unify_type_var(self: Context, id: Int, ty: TypeKind) -> Unit raise TypeCheckError {
  println("DEBUG: unify_type_var called for id=" + id.to_string() + " with ty=" + ty.to_string())
  let resolved_ty = match ty {
    TypeVar(other_id) => self.resolve_type_var(other_id)
    _ => ty
  }

  match self.resolve_type_var(id) {
    TypeVar(existing_id) => {
      if existing_id != id {
        // Avoid infinite recursion by directly setting the binding
        // instead of recursively calling unify_type_var
        self.type_vars.set(existing_id, resolved_ty)
        println("DEBUG: unify_type_var setting existing_id=" + existing_id.to_string() + " => " + resolved_ty.to_string())
        match resolved_ty {
          TypeVar(_) => ()
          _ => self.update_dependents(existing_id, resolved_ty)
        }
      } else {
        println("DEBUG: unify_type_var setting id=" + id.to_string() + " => " + resolved_ty.to_string())
        self.type_vars.set(id, resolved_ty)
        match resolved_ty {
          TypeVar(_) => ()
          _ => self.update_dependents(id, resolved_ty)
        }
      }
    }
    existing_ty => {
      if !self.is_type_compatible(existing_ty, resolved_ty) {
        raise TypeCheckError("Type mismatch in unification")
      }
    }
  }
}

///|
pub fn Context::is_type_compatible(
  self : Context,
  a : TypeKind,
  b : TypeKind,
) -> Bool raise TypeCheckError {
  self.is_type_compatible_with_cycle(a, b, [])
}

fn Context::is_type_compatible_with_cycle(
  self : Context,
  a : TypeKind,
  b : TypeKind,
  visited: Array[(TypeKind, TypeKind)]
) -> Bool raise TypeCheckError {
  // Limit recursion depth to prevent stack overflow
  if visited.length() > 500 {
    println("WARNING: Hit recursion depth limit in is_type_compatible_with_cycle");
    return true  // Assume compatible if we've gone too deep
  }
  
  // Check for cycles to prevent infinite recursion
  for i = 0; i < visited.length(); i = i + 1 {
    let (prev_a, prev_b) = visited[i]
    if self.types_equal(a, prev_a) && self.types_equal(b, prev_b) {
      return true  // We've seen this pair before, assume compatible
    }
  }
  
  let new_visited = visited.copy()
  new_visited.push((a, b))
  
  let resolved_a = match a {
    TypeVar(id) => self.resolve_type_var(id)
    _ => a
  }

  let resolved_b = match b {
    TypeVar(id) => self.resolve_type_var(id)
    _ => b
  }

  match (resolved_a, resolved_b) {
    (TypeVar(id_a), TypeVar(id_b)) => {
      if id_a != id_b {
        // Use a more robust approach: unify the smaller ID to the larger ID
        // to avoid creating cycles
        if id_a < id_b {
          self.type_vars.set(id_a, TypeVar(id_b))
        } else {
          self.type_vars.set(id_b, TypeVar(id_a))
        }
      }
      true
    }
    (TypeVar(id), ty) => {
      if contains_type_var(ty, id) {
        raise TypeCheckError("Infinite type detected")
      }
      self.unify_type_var(id, ty)
      true
    }
    (ty, TypeVar(id)) => {
      if contains_type_var(ty, id) {
        raise TypeCheckError("Infinite type detected")
      }
      self.unify_type_var(id, ty)
      true
    }
    (Unit, Unit) => true
    (Bool, Bool) => true
    (Int, Int) => true
    (Double, Double) => true
    (String, String) => true
    (Tuple(types_a), Tuple(types_b)) => {
      if types_a.length() != types_b.length() {
        false
      } else {
        self.check_tuple_types(types_a, types_b, new_visited, 0)
      }
    }
    (Array(elem_a), Array(elem_b)) => self.is_type_compatible_with_cycle(elem_a, elem_b, new_visited)
    (Function(params_a, ret_a), Function(params_b, ret_b)) => {
      if params_a.length() != params_b.length() {
        false
      } else {
        self.check_function_params(params_a, params_b, new_visited, 0) && self.is_type_compatible_with_cycle(ret_a, ret_b, new_visited)
      }
    }
    (Struct(name_a), Struct(name_b)) => name_a == name_b
    (Enum(name_a), Enum(name_b)) => name_a == name_b
    // Handle compatibility between generic enums and regular enums with the same name
    (Enum(name_a), GenericEnum(name_b, _)) => name_a == name_b
    (GenericEnum(name_a, _), Enum(name_b)) => name_a == name_b
    // Handle compatibility between generic enums with the same name and type arguments
    (GenericEnum(name_a, args_a), GenericEnum(name_b, args_b)) => {
      if name_a != name_b {
        false
      } else {
        // Check if type arguments are compatible
        if args_a.length() != args_b.length() {
          false
        } else {
          let mut i = 0
          let mut compatible = true
          while i < args_a.length() && compatible {
            compatible = self.is_type_compatible_with_cycle(args_a[i], args_b[i], new_visited)
            i = i + 1
          }
          compatible
        }
      }
    }
    // Handle compatibility between generic structs and regular structs with the same name
    (Struct(name_a), GenericStruct(name_b, _)) => name_a == name_b
    (GenericStruct(name_a, _), Struct(name_b)) => name_a == name_b
    // Handle compatibility between generic structs with the same name and type arguments
    (GenericStruct(name_a, args_a), GenericStruct(name_b, args_b)) => {
      if name_a != name_b {
        false
      } else {
        // Check if type arguments are compatible
        if args_a.length() != args_b.length() {
          false
        } else {
          let mut i = 0
          let mut compatible = true
          while i < args_a.length() && compatible {
            compatible = self.is_type_compatible_with_cycle(args_a[i], args_b[i], new_visited)
            i = i + 1
          }
          compatible
        }
      }
    }
    (Any, _) => true
    (_, Any) => true
    _ => false
  }
}

/// Helper function to check structural equality of types
fn Context::types_equal(self: Context, a: TypeKind, b: TypeKind) -> Bool {
  match (a, b) {
    (Unit, Unit) => true
    (Bool, Bool) => true
    (Int, Int) => true
    (Double, Double) => true
    (String, String) => true
    (Tuple(types_a), Tuple(types_b)) => {
      if types_a.length() != types_b.length() {
        false
      } else {
        let mut i = 0
        let mut equal = true
        while i < types_a.length() && equal {
          equal = self.types_equal(types_a[i], types_b[i])
          i = i + 1
        }
        equal
      }
    }
    (Array(elem_a), Array(elem_b)) => self.types_equal(elem_a, elem_b)
    (Function(params_a, ret_a), Function(params_b, ret_b)) => {
      if params_a.length() != params_b.length() {
        false
      } else {
        let mut i = 0
        let mut equal = true
        while i < params_a.length() && equal {
          equal = self.types_equal(params_a[i], params_b[i])
          i = i + 1
        }
        equal && self.types_equal(ret_a, ret_b)
      }
    }
    (Struct(name_a), Struct(name_b)) => name_a == name_b
    (Enum(name_a), Enum(name_b)) => name_a == name_b
    // Handle equality between generic enums with the same name and type arguments
    (GenericEnum(name_a, args_a), GenericEnum(name_b, args_b)) => {
      if name_a != name_b {
        false
      } else {
        // Check if type arguments are equal
        if args_a.length() != args_b.length() {
          false
        } else {
          let mut i = 0
          let mut equal = true
          while i < args_a.length() && equal {
            equal = self.types_equal(args_a[i], args_b[i])
            i = i + 1
          }
          equal
        }
      }
    }
    // Handle equality between generic structs with the same name and type arguments
    (GenericStruct(name_a, args_a), GenericStruct(name_b, args_b)) => {
      if name_a != name_b {
        false
      } else {
        // Check if type arguments are equal
        if args_a.length() != args_b.length() {
          false
        } else {
          let mut i = 0
          let mut equal = true
          while i < args_a.length() && equal {
            equal = self.types_equal(args_a[i], args_b[i])
            i = i + 1
          }
          equal
        }
      }
    }
    (Any, Any) => true
    (TypeVar(id_a), TypeVar(id_b)) => id_a == id_b
    _ => false
  }
}

///|
pub impl Show for TypeKind with output(self, logger) {
  let s = match self {
    Unit => "Unit"
    Bool => "Bool"
    Int => "Int"
    Double => "Double"
    String => "String"
    Tuple(types) => {
      let inner = types.map(typekind => typekind.to_string()).join(", ")
      "(\{inner})"
    }
    Array(elem_type) => "Array[\{elem_type.to_string()}]"
    Function(param_types, return_type) => {
      let params = param_types.map(typekind => typekind.to_string()).join(", ")
      "(\{params}) -> \{return_type.to_string()}"
    }
    Struct(name) => "\{name}"
    Enum(name) => "\{name}"
    GenericEnum(name, type_args) => {
      let args = type_args.map(typekind => typekind.to_string()).join(", ")
      "\{name}[\{args}]"
    }
    GenericStruct(name, type_args) => {
      let args = type_args.map(typekind => typekind.to_string()).join(", ")
      "\{name}[\{args}]"
    }
    Any => "Any"
    TypeVar(name) => "TypeVar(\{name})"
  }
  logger.write_string(s)
}


///| Check if a type is compatible with a potentially generic type
pub fn Context::is_generic_compatible(
  self : Context,
  expected : TypeKind,
  actual : TypeKind
) -> Bool raise TypeCheckError {
  println("DEBUG: is_generic_compatible entry - expected: " + expected.to_string() + ", actual: " + actual.to_string());
  let result = self.is_generic_compatible_with_cycle(expected, actual, Array::new());
  println("DEBUG: is_generic_compatible exit - result: " + result.to_string());
  result
}

fn Context::is_generic_compatible_with_cycle(
  self : Context,
  expected : TypeKind,
  actual : TypeKind,
  visited: Array[(TypeKind, TypeKind)]
) -> Bool raise TypeCheckError {
  // Limit recursion depth to prevent stack overflow
  if visited.length() > 100 {
    println("WARNING: Hit recursion depth limit in is_generic_compatible_with_cycle");
    return true  // Assume compatible if we've gone too deep
  }
  
  // Check for cycles to prevent infinite recursion
  for i = 0; i < visited.length(); i = i + 1 {
    let (prev_expected, prev_actual) = visited[i]
    if self.types_equal(expected, prev_expected) && self.types_equal(actual, prev_actual) {
      println("DEBUG: Cycle detected in is_generic_compatible_with_cycle: " + expected.to_string() + " vs " + actual.to_string())
      return true  // We've seen this pair before, assume compatible
    }
  }
  
  let new_visited = visited.copy()
  new_visited.push((expected, actual))
  
  println("is_generic_compatible called with expected: " + expected.to_string() + ", actual: " + actual.to_string());
  
  // Handle TypeVar case - this represents generic type parameters
  match expected {
    TypeKind::TypeVar(var_id) => {
      println("DEBUG: Found TypeVar " + var_id.to_string() + ", checking bindings");
      // Check if this type variable already has a binding
      match self.type_vars.get(var_id) {
        Some(bound_type) => {
          // Type variable already bound - check compatibility with the bound type
          println("DEBUG: TypeVar " + var_id.to_string() + " already bound to: " + bound_type.to_string());
          // Check if the TypeVar is bound to itself (unbound/free variable)
          match bound_type {
            TypeVar(bound_id) if bound_id == var_id => {
              // TypeVar is bound to itself, meaning it's free/unbound
              // Check occurs check to prevent infinite types
              if contains_type_var(actual, var_id) {
                println("DEBUG: Occurs check failed for TypeVar " + var_id.to_string() + " with type " + actual.to_string());
                return false;  // Prevent infinite type
              }
              // Allow it to unify with the actual type and update the binding
              println("DEBUG: TypeVar " + var_id.to_string() + " is free, unifying with: " + actual.to_string());
              self.type_vars.set(var_id, actual);
              return true;
            }
            _ => {
              // TypeVar is bound to a concrete type - check compatibility with that type
              println("DEBUG: TypeVar " + var_id.to_string() + " is bound to concrete type, checking compatibility");
              return self.is_generic_compatible_with_cycle(bound_type, actual, new_visited)
            }
          }
        }
        None => {
          // Type variable not bound yet - bind it to the actual type
          // But avoid binding to itself to prevent circular dependencies
          match actual {
            TypeKind::TypeVar(other_id) if other_id == var_id => {
              println("DEBUG: Avoiding self-binding of TypeVar " + var_id.to_string() + " to itself");
              return false;
            }
            _ => {
              // Check occurs check to prevent infinite types
              if contains_type_var(actual, var_id) {
                println("DEBUG: Occurs check failed for TypeVar " + var_id.to_string() + " with type " + actual.to_string());
                return false;  // Prevent infinite type
              }
              println("DEBUG: TypeVar " + var_id.to_string() + " not bound, binding to: " + actual.to_string());
              self.type_vars.set(var_id, actual);
              return true;
            }
          }
        }
      }
    }
    _ => ()
  }
  
  // Handle GenericEnum case
  match expected {
    TypeKind::GenericEnum(name, type_args_expected) => {
      match actual {
        TypeKind::GenericEnum(actual_name, type_args_actual) if actual_name == name => {
          // Same enum name, check type arguments
          if type_args_expected.length() != type_args_actual.length() {
            return false
          }
          let mut i = 0
          while i < type_args_expected.length() {
            if !self.is_generic_compatible_with_cycle(type_args_expected[i], type_args_actual[i], new_visited) {
              return false
            }
            i = i + 1
          }
          return true
        }
        _ => {
          // Not a matching GenericEnum, fall back to normal compatibility check
          return self.is_type_compatible_with_cycle(expected, actual, new_visited)
        }
      }
    }
    TypeKind::GenericStruct(name, type_args_expected) => {
      match actual {
        TypeKind::GenericStruct(actual_name, type_args_actual) if actual_name == name => {
          // Same struct name, check type arguments
          if type_args_expected.length() != type_args_actual.length() {
            return false
          }
          let mut i = 0
          while i < type_args_expected.length() {
            if !self.is_generic_compatible_with_cycle(type_args_expected[i], type_args_actual[i], new_visited) {
              return false
            }
            i = i + 1
          }
          return true
        }
        _ => {
          // Not a matching GenericStruct, fall back to normal compatibility check
          return self.is_type_compatible_with_cycle(expected, actual, new_visited)
        }
      }
    }
    _ => ()
  }
  
  // Check if expected is a generic type parameter (empty struct)
  match expected {
    TypeKind::Struct(name) => {
       // Check if this is a generic type parameter
       // Generic type parameters are typically single uppercase letters like T, K, V, etc.
       // For simplicity, check if the name is a single uppercase letter
       let is_generic = name.length() == 1 && {
         // Check if it's one of the common generic parameter names
         name == "T" || name == "K" || name == "V" || name == "E" || name == "R" || 
         name == "A" || name == "B" || name == "C" || name == "D" || name == "F" ||
         name == "G" || name == "H" || name == "I" || name == "J" || name == "L" ||
         name == "M" || name == "N" || name == "O" || name == "P" || name == "Q" ||
         name == "S" || name == "U" || name == "W" || name == "X" || name == "Y" || name == "Z"
       }
       
       if is_generic {
         // This is a generic type parameter - we need to unify it with the actual type
         // First check if this generic parameter already has a binding
         println("DEBUG: Found generic type parameter " + name + ", checking bindings")
         
         // Check if we have a binding for this generic parameter
         match self.generic_type_bindings.get(name) {
           Some(bound_type) => {
             // Generic parameter already bound - check compatibility with the bound type
             println("DEBUG: " + name + " already bound to: " + bound_type.to_string())
             // Check if the actual type is the same as the bound type
             match actual {
               TypeKind::Struct(actual_name) if actual_name == name => {
                 // This is the same generic parameter - check if it's bound
                 match self.generic_type_bindings.get(actual_name) {
                   Some(bound_actual) => {
                     // Both are the same generic parameter and both are bound
                     // Check compatibility of their bindings
                     return self.is_generic_compatible_with_cycle(bound_type, bound_actual, new_visited)
                   }
                   None => {
                     // Both are the same unbound generic parameter - compatible
                     println("DEBUG: Both generic parameters " + name + " are unbound, compatible");
                     return true;
                   }
                 }
               }
               _ => return self.is_generic_compatible_with_cycle(bound_type, actual, new_visited)
             }
           }
           None => {
             // If we have any generic bindings at all, it means we're in a call site context
             // where we should use those bindings for compatibility checking
             if !self.generic_type_bindings.is_empty() {
               // We have some bindings, but not for this specific parameter
               // This might be a case where we're checking compatibility during call site checking
               // and we should fall back to normal compatibility check
               println("DEBUG: Checking with existing bindings, but " + name + " not bound, falling back to normal compatibility")
               return self.is_type_compatible_with_cycle(expected, actual, new_visited)
             }
             
             // If we're checking a generic function body, don't bind the generic parameter
             // Just check if the actual type is also the same generic parameter
             if self.checking_generic_function_body {
               println("DEBUG: Checking generic function body, not binding " + name)
               match actual {
                 TypeKind::Struct(actual_name) if actual_name == name => {
                   println("DEBUG: Both are " + name + ", compatible")
                   return true
                 }
                 _ => {
                   // If the actual type is structurally identical to the
                   // generic parameter itself (e.g. T vs T), do not record a
                   // self-binding like T -> T, which would later cause
                   // resolve_type_kind and substitution to spin forever.
                   if types_equal_simple(expected, actual) {
                     println("DEBUG: Skipping self-binding for generic parameter " + name + " with actual " + actual.to_string())
                     return true
                   }
                   // Check occurs check to prevent infinite types
                   if contains_generic_param(actual, name) {
                     println("DEBUG: Occurs check failed for generic parameter " + name + " with type " + actual.to_string());
                     return false;  // Prevent infinite type
                   }
                   // Generic parameter not bound yet - bind it to the actual type
                   println("DEBUG: " + name + " not bound, binding to: " + actual.to_string())
                   self.generic_type_bindings.set(name, actual)
                   return true
                 }
               }
             }
             // Outside of generic function body: similarly avoid recording
             // trivial self-bindings like T -> T.
             if types_equal_simple(expected, actual) {
               println("DEBUG: Skipping self-binding for generic parameter " + name + " with actual " + actual.to_string())
               return true
             }
             // Check occurs check to prevent infinite types
             if contains_generic_param(actual, name) {
               println("DEBUG: Occurs check failed for generic parameter " + name + " with type " + actual.to_string());
               return false;  // Prevent infinite type
             }
             // Generic parameter not bound yet - bind it to the actual type
             println("DEBUG: " + name + " not bound, binding to: " + actual.to_string())
             self.generic_type_bindings.set(name, actual)
             return true
           }
         }
       } else {
         // This is a regular struct - use the original logic
         match (expected, actual) {
           (TypeKind::Struct(name1), TypeKind::Struct(name2)) => return name1 == name2
           _ => return false
         }
       }
    }
    TypeKind::Array(elem_expected) => {
      // For Array[T] where T is generic, match with Array[ConcreteType]
      match actual {
        TypeKind::Array(elem_actual) => {
          return self.is_generic_compatible_with_cycle(elem_expected, elem_actual, new_visited)
        }
        _ => return false
      }
    }
    TypeKind::Tuple(types_expected) => {
      match actual {
        TypeKind::Tuple(types_actual) => {
          if types_expected.length() != types_actual.length() {
            return false
          }
          let mut i = 0
          while i < types_expected.length() {
            if !self.is_generic_compatible_with_cycle(types_expected[i], types_actual[i], new_visited) {
              return false
            }
            i = i + 1
          }
          return true
        }
        _ => return false
      }
    }
    TypeKind::Function(params_expected, ret_expected) => {
      match actual {
        TypeKind::Function(params_actual, ret_actual) => {
          if params_expected.length() != params_actual.length() {
            return false
          }
          let mut i = 0
          while i < params_expected.length() {
            if !self.is_generic_compatible_with_cycle(params_expected[i], params_actual[i], new_visited) {
              return false
            }
            i = i + 1
          }
          return self.is_generic_compatible_with_cycle(ret_expected, ret_actual, new_visited)
        }
        _ => return false
      }
    }
    _ => ()
  }
  
  // Fall back to normal type compatibility
  self.is_type_compatible_with_cycle(expected, actual, new_visited)
}

///| Infer generic type bindings by matching expected parameter type with actual argument type
pub fn Context::infer_generic_bindings(
  self : Context,
  expected : TypeKind,
  actual : TypeKind
) -> Unit {
  match expected {
    TypeKind::Struct(name) => {
      // Check if this is a generic type parameter
      // A generic type parameter is a single uppercase letter that is registered
      // in the current generic context or follows the common naming pattern
      let is_generic = name.length() == 1 && name >= "A" && name <= "Z" && {
        // Check if it's registered as a generic type parameter in the current context
        // or if we're in a generic function body where we should treat it as generic
        self.generic_type_bindings.get(name) is Some(_) || 
        self.checking_generic_function_body ||
        // Fallback to common generic parameter names for backward compatibility
        name == "T" || name == "K" || name == "V" || name == "E" || name == "R" || 
        name == "A" || name == "B" || name == "C" || name == "D" || name == "F" ||
        name == "G" || name == "H" || name == "I" || name == "J" || name == "L" ||
        name == "M" || name == "N" || name == "O" || name == "P" || name == "Q" ||
        name == "S" || name == "U" || name == "W" || name == "X" || name == "Y" || name == "Z"
      }
      
      if is_generic {
        // Only bind the generic parameter if it's not already bound
        match self.generic_type_bindings.get(name) {
          Some(_) => {
            // Already bound, don't rebind
            println("DEBUG: infer_generic_bindings: " + name + " already bound, skipping")
          }
          None => {
            // Not bound yet, bind it to the actual type
            println("DEBUG: infer_generic_bindings: binding " + name + " to " + actual.to_string())
            self.generic_type_bindings.set(name, actual)
          }
        }
      }
    }
    TypeKind::Array(expected_elem) => {
      match actual {
        TypeKind::Array(actual_elem) => {
          self.infer_generic_bindings(expected_elem, actual_elem)
        }
        _ => ()
      }
    }
    TypeKind::Tuple(expected_types) => {
      match actual {
        TypeKind::Tuple(actual_types) => {
          if expected_types.length() == actual_types.length() {
            let mut i = 0
            while i < expected_types.length() {
              self.infer_generic_bindings(expected_types[i], actual_types[i])
              i = i + 1
            }
          }
        }
        _ => ()
      }
    }
    TypeKind::Function(expected_params, expected_ret) => {
      match actual {
        TypeKind::Function(actual_params, actual_ret) => {
          if expected_params.length() == actual_params.length() {
            let mut i = 0
            while i < expected_params.length() {
              self.infer_generic_bindings(expected_params[i], actual_params[i])
              i = i + 1
            }
            self.infer_generic_bindings(expected_ret, actual_ret)
          }
        }
        _ => ()
      }
    }
    TypeKind::GenericEnum(expected_name, expected_args) => {
      match actual {
        TypeKind::GenericEnum(actual_name, actual_args) => {
          if expected_name == actual_name && expected_args.length() == actual_args.length() {
            let mut i = 0
            while i < expected_args.length() {
              self.infer_generic_bindings(expected_args[i], actual_args[i])
              i = i + 1
            }
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

///| Substitute generic type parameters with their concrete types
pub fn Context::substitute_type_kind_with_map(self : Context, ty : TypeKind, type_param_map : Map[String, TypeKind]) -> TypeKind {
  match ty {
    TypeKind::Struct(name) => {
      match type_param_map.get(name) {
        Some(concrete_type) => {
          println("DEBUG: substitute_type_kind_with_map: substituting " + name + " with " + concrete_type.to_string())
          // Avoid infinite substitutions such as mapping T -> T or
          // T -> List[T], which would cause resolve_type_kind and this
          // function to expand types without end.
          // 1) If the concrete type is structurally identical to the
          //    original ty, just return ty.
          if types_equal_simple(ty, concrete_type) {
            return ty
          }
          // 2) If the concrete type still contains this generic parameter
          //    name, skip the substitution entirely.
          if contains_generic_param(concrete_type, name) {
            println("DEBUG: substitute_type_kind_with_map: skipping infinite substitution " + name + " -> " + concrete_type.to_string())
            return ty
          }
          concrete_type
        }
        None => ty
      }
    }
    TypeKind::Array(elem_ty) => {
      TypeKind::Array(self.substitute_type_kind_with_map(elem_ty, type_param_map))
    }
    TypeKind::Tuple(types) => {
      let mut substituted_types : Array[TypeKind] = []
      let mut i = 0
      while i < types.length() {
        substituted_types = substituted_types + [self.substitute_type_kind_with_map(types[i], type_param_map)]
        i = i + 1
      }
      TypeKind::Tuple(substituted_types)
    }
    TypeKind::Function(param_types, ret_ty) => {
      let mut substituted_params : Array[TypeKind] = []
      let mut i = 0
      while i < param_types.length() {
        substituted_params = substituted_params + [self.substitute_type_kind_with_map(param_types[i], type_param_map)]
        i = i + 1
      }
      TypeKind::Function(substituted_params, self.substitute_type_kind_with_map(ret_ty, type_param_map))
    }
    TypeKind::GenericEnum(name, type_args) => {
      // Substitute type arguments recursively
      let mut substituted_args : Array[TypeKind] = []
      let mut i = 0
      while i < type_args.length() {
        substituted_args = substituted_args + [self.substitute_type_kind_with_map(type_args[i], type_param_map)]
        i = i + 1
      }
      TypeKind::GenericEnum(name, substituted_args)
    }
    TypeKind::GenericStruct(name, type_args) => {
      // Substitute type arguments recursively
      let mut substituted_args : Array[TypeKind] = []
      let mut i = 0
      while i < type_args.length() {
        substituted_args = substituted_args + [self.substitute_type_kind_with_map(type_args[i], type_param_map)]
        i = i + 1
      }
      TypeKind::GenericStruct(name, substituted_args)
    }
    _ => ty
  }
}
