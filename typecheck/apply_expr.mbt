///|
pub(all) struct ApplyExpr {
  kind : ApplyExprKind
  ty : TypeKind
} derive(Show)

///|
pub(all) enum ApplyExprKind {
  AtomExpr(AtomExpr)
  ArrayAccess(ApplyExpr, Expr)
  FieldAccess(ApplyExpr, String)
  Call(ApplyExpr, Array[Expr])
  EnumVariantAccess(String, String) // EnumName::VariantName
} derive(Show)

// Helper function to convert TypeKind to string representation
fn Context::type_to_string(self : Self, ty : TypeKind) -> String {
  match ty {
    TypeKind::Unit => "Unit"
    TypeKind::Bool => "Bool"
    TypeKind::Int => "Int"
    TypeKind::Double => "Double"
    TypeKind::String => "String"
    TypeKind::TypeVar(id) => "TypeVar(" + id.to_string() + ")"
    TypeKind::Array(elem_ty) => "Array[" + self.type_to_string(elem_ty) + "]"
    TypeKind::Tuple(types) => {
      let mut result = "("
      let mut first = true
      for ty in types {
        if !first { result = result + ", " }
        result = result + self.type_to_string(ty)
        first = false
      }
      result + ")"
    }
    TypeKind::Function(param_types, ret_ty) => {
      let mut result = "("
      let mut first = true
      for ty in param_types {
        if !first { result = result + ", " }
        result = result + self.type_to_string(ty)
        first = false
      }
      result + ") -> " + self.type_to_string(ret_ty)
    }
    TypeKind::Struct(name) => name
    TypeKind::Enum(name) => name
    TypeKind::GenericEnum(name, type_args) => {
      let mut result = name + "["
      let mut first = true
      for arg in type_args {
        if !first { result = result + ", " }
        result = result + self.type_to_string(arg)
        first = false
      }
      result + "]"
    }
    TypeKind::GenericStruct(name, type_args) => {
      let mut result = name + "["
      let mut first = true
      for arg in type_args {
        if !first { result = result + ", " }
        result = result + self.type_to_string(arg)
        first = false
      }
      result + "]"
    }
    TypeKind::Any => "Any"
  }
}

///| Check if a type contains any generic parameters (single-letter struct names like T, K, etc.)
fn Context::contains_generic_parameter(self: Context, ty: TypeKind) -> Bool {
  match ty {
    TypeKind::TypeVar(_) => true
    TypeKind::Struct(name) => {
      // Check if this is a generic type parameter
      // Generic type parameters are typically single uppercase letters like T, K, V, etc.
      name.length() == 1 && {
        name == "T" || name == "K" || name == "V" || name == "E" || name == "R" || 
        name == "A" || name == "B" || name == "C" || name == "D" || name == "F" ||
        name == "G" || name == "H" || name == "I" || name == "J" || name == "L" ||
        name == "M" || name == "N" || name == "O" || name == "P" || name == "Q" ||
        name == "S" || name == "U" || name == "W" || name == "X" || name == "Y" || name == "Z"
      }
    }
    TypeKind::Array(elem_ty) => self.contains_generic_parameter(elem_ty)
    TypeKind::Tuple(types) => {
      let mut i = 0
      let mut found = false
      while i < types.length() && !found {
        found = self.contains_generic_parameter(types[i])
        i = i + 1
      }
      found
    }
    TypeKind::Function(param_types, ret_ty) => {
      let mut i = 0
      let mut found = false
      while i < param_types.length() && !found {
        found = self.contains_generic_parameter(param_types[i])
        i = i + 1
      }
      if !found {
        found = self.contains_generic_parameter(ret_ty)
      }
      found
    }
    TypeKind::GenericEnum(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = self.contains_generic_parameter(type_args[i])
        i = i + 1
      }
      found
    }
    TypeKind::GenericStruct(_, type_args) => {
      let mut i = 0
      let mut found = false
      while i < type_args.length() && !found {
        found = self.contains_generic_parameter(type_args[i])
        i = i + 1
      }
      found
    }
    _ => false
  }
}

///|
pub fn Context::check_apply_expr(
  self : Self,
  apply_expr : @parser.ApplyExpr,
) -> ApplyExpr raise TypeCheckError {
  match apply_expr.kind {
    @parser.ApplyExprKind::EnumVariantAccess(enum_expr, variant_name) => {
      // First check the enum expression (should be an identifier)
      let enum_apply_expr = self.check_apply_expr(enum_expr)
      match enum_apply_expr.kind {
        ApplyExprKind::AtomExpr(atom_expr) => {
          match atom_expr.kind {
            AtomExprKind::Ident(enum_name) => {
              // Check if the enum exists
              match self.enum_defs.get(enum_name) {
                Some(enum_def) => {
                  // Check if the variant exists
                  let mut found = false
                  let mut variant_opt : EnumVariant? = None
                  for v in enum_def.variants {
                    if v.name == variant_name {
                      found = true
                      variant_opt = Some(v)
                      break
                    }
                  }
                  if !found {
                    raise TypeCheckError("Unknown variant '" + variant_name + "' in enum '" + enum_name + "'")
                  }
                  
                  // Determine the appropriate type for the enum variant access
                  let variant = variant_opt.unwrap()
                  let expr_type = if enum_def.type_params.length() > 0 {
                    // For generic enums, create a GenericEnum type with type variables
                    let mut type_args: Array[TypeKind] = []
                    let mut i = 0
                    while i < enum_def.type_params.length() {
                      type_args = type_args + [TypeKind::TypeVar(i)]
                      i = i + 1
                    }
                    let enum_type = TypeKind::GenericEnum(enum_name, type_args)
                    
                    // For enum constructors, we need to return a function type
                    if variant.params.length() == 0 {
                      // Simple constructor (no parameters): Nil : () -> Node[T]
                      let func_type = TypeKind::Function([], enum_type)
                      println("DEBUG: EnumVariantAccess for generic enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
                      func_type
                    } else {
                      // Constructor with parameters: Cons : (T, Node[T]) -> Node[T]
                      let func_type = TypeKind::Function(variant.params, enum_type)
                      println("DEBUG: EnumVariantAccess for generic enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
                      func_type
                    }
                  } else {
                    // For regular enums, use the simple Enum type or function type for constructors
                    let enum_type = TypeKind::Enum(enum_name)
                    if variant.params.length() == 0 {
                      // Simple constructor (no parameters): Red : () -> Color
                      let func_type = TypeKind::Function([], enum_type)
                      println("DEBUG: EnumVariantAccess for enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
                      func_type
                    } else {
                      // Constructor with parameters: RGB : (Int, Int, Int) -> Color
                      let func_type = TypeKind::Function(variant.params, enum_type)
                      println("DEBUG: EnumVariantAccess for enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
                      func_type
                    }
                  }
                  
                  ApplyExpr::{
                    kind: ApplyExprKind::EnumVariantAccess(enum_name, variant_name),
                    ty: expr_type
                  }
                }
                None => raise TypeCheckError("Unknown enum: " + enum_name)
              }
            }
            _ => raise TypeCheckError("Expected enum name before ::")
          }
        }
        _ => raise TypeCheckError("Expected enum name before ::")
      }
    }
    @parser.ApplyExprKind::AtomExpr(atom_expr) => {
      let checked_atom = self.check_atom_expr(atom_expr)
      ApplyExpr::{
        kind: ApplyExprKind::AtomExpr(checked_atom),
        ty: checked_atom.ty
      }
    }
    @parser.ApplyExprKind::ArrayAccess(array_expr, index_expr) => {
      let checked_array = self.check_apply_expr(array_expr)
      let checked_index = self.check_expr(index_expr)

      if !self.is_type_compatible(checked_index.ty, TypeKind::Int) {
        let actual_ty = self.type_to_string(checked_index.ty)
        raise TypeCheckError("Array index must be Int, but got: " + actual_ty)
      }

      let resolved_index = Expr::{
        kind: checked_index.kind,
        ty: self.resolve_type_kind(checked_index.ty)
      }

      let mut array_ty = self.resolve_type_kind(checked_array.ty)
      if array_ty is TypeKind::TypeVar(_) {
        let elem_var = self.allocate_fresh_type_var()
        if !self.is_type_compatible(checked_array.ty, TypeKind::Array(elem_var)) {
          let actual_ty = self.type_to_string(checked_array.ty)
          raise TypeCheckError("Array access expects an Array type, but got: " + actual_ty)
        }
        array_ty = self.resolve_type_kind(checked_array.ty)
      }

      let element_ty = match array_ty {
        TypeKind::Array(elem_ty) => self.resolve_type_kind(elem_ty)
        TypeKind::Any => TypeKind::Any
        _ => {
          let actual_ty = self.type_to_string(array_ty)
          raise TypeCheckError("Array access expects an Array type, but got: " + actual_ty)
        }
      }

      let resolved_array = ApplyExpr::{
        kind: checked_array.kind,
        ty: array_ty
      }

      ApplyExpr::{
        kind: ApplyExprKind::ArrayAccess(resolved_array, resolved_index),
        ty: element_ty
      }
    }
    @parser.ApplyExprKind::FieldAccess(object_expr, field_name) => {
      let checked_object = self.check_apply_expr(object_expr)
      let object_ty = self.resolve_type_kind(checked_object.ty)
      println("DEBUG: field_access: object has type " + object_ty.to_string())

      if object_ty is TypeKind::TypeVar(_) {
        raise TypeCheckError("Cannot determine type for field access - type variable not resolved")
      }

      println("DEBUG: field_access: object has type " + object_ty.to_string())
      let field = field_name
      let field_ty = match object_ty {
        TypeKind::Struct(struct_name) => {
          println("DEBUG: field_access: handling Struct " + struct_name)
          // Check if this is a generic type parameter (like "T")
          // If so, we need to look up the actual struct type from the context
          if self.checking_generic_function_body && self.contains_generic_parameter(object_ty) {
            println("DEBUG: field_access: this is a generic parameter in a generic function")
            // In a generic function, we can't directly access fields of a generic parameter
            // We need to defer the field access until monomorphization
            TypeKind::Any
          } else {
            match self.struct_defs.get(struct_name) {
              Some(struct_def) => {
                match struct_def.get_field_type(field) {
                  Some(field_type) => {
                    println("DEBUG: field_access: found field " + field + " with type " + field_type.kind.to_string())
                    // For generic structs in generic functions, we need to substitute type parameters
                    if struct_def.type_params.length() > 0 {
                      println("DEBUG: field_access: struct " + struct_name + " has type parameters " + struct_def.type_params.to_string())
                      // Check if we're in a generic function body and have generic bindings
                      if self.checking_generic_function_body {
                        println("DEBUG: field_access: in generic function body")
                        // Create a mapping from type parameters to their bindings
                        let type_param_map : Map[String, TypeKind] = Map::new()
                        let mut i = 0
                        while i < struct_def.type_params.length() {
                          let param = struct_def.type_params[i]
                          match self.generic_type_bindings.get(param) {
                            Some(bound_type) => {
                              println("DEBUG: field_access: mapping " + param + " to bound type " + bound_type.to_string())
                              type_param_map.set(param, bound_type)
                            }
                            None => {
                              println("DEBUG: field_access: no binding for " + param)
                            }
                          }
                          i = i + 1
                        }
                        
                        // Substitute type parameters in the field type
                        let substituted = self.substitute_type_kind_with_map(field_type.kind, type_param_map)
                        println("DEBUG: field_access: substituted field type is " + substituted.to_string())
                        substituted
                      } else {
                        field_type.kind
                      }
                    } else {
                      field_type.kind
                    }
                  }
                  None => raise TypeCheckError("Unknown field '" + field + "' on struct " + struct_name)
                }
              }
              None => raise TypeCheckError("Unknown struct: " + struct_name)
            }
          }
        }
        TypeKind::GenericStruct(struct_name, type_args) => {
          println("DEBUG: field_access: handling GenericStruct " + struct_name + " with type_args " + type_args.to_string())
          // For generic structs, we need to substitute type parameters with concrete types
          match self.struct_defs.get(struct_name) {
            Some(struct_def) => {
              match struct_def.get_field_type(field) {
                Some(field_type) => {
                  println("DEBUG: field_access: found field " + field + " with type " + field_type.kind.to_string())
                  // Create a mapping from type parameters to concrete types
                  let type_param_map : Map[String, TypeKind] = Map::new()
                  let mut i = 0
                  while i < struct_def.type_params.length() && i < type_args.length() {
                    println("DEBUG: field_access: mapping " + struct_def.type_params[i] + " to " + type_args[i].to_string())
                    type_param_map.set(struct_def.type_params[i], type_args[i])
                    i = i + 1
                  }
                  
                  // Substitute type parameters in the field type
                  let substituted = self.substitute_type_kind_with_map(field_type.kind, type_param_map)
                  println("DEBUG: field_access: substituted field type is " + substituted.to_string())
                  substituted
                }
                None => raise TypeCheckError("Unknown field '" + field + "' on struct " + struct_name)
              }
            }
            None => raise TypeCheckError("Unknown struct: " + struct_name)
          }
        }
        TypeKind::Array(elem_ty) => {
          let resolved_elem = self.resolve_type_kind(elem_ty)
          match field {
            "push" => TypeKind::Function([resolved_elem], TypeKind::Unit)
            "length" => TypeKind::Function([], TypeKind::Int)
            _ => raise TypeCheckError("Unknown array method: " + field)
          }
        }
        TypeKind::Any => TypeKind::Any
        _ => raise TypeCheckError("Field access expects a struct or array")
      }

      ApplyExpr::{
        kind: ApplyExprKind::FieldAccess(ApplyExpr::{ kind: checked_object.kind, ty: object_ty }, field),
        ty: field_ty
      }
    }
    @parser.ApplyExprKind::Call(callee_expr, arg_exprs) => {
      // Extract function name if this is a simple identifier
      let func_name_opt = match callee_expr.kind {
        @parser.ApplyExprKind::AtomExpr(atom) => match atom.kind {
          @parser.AtomExprKind::Ident(name) => Some(name)
          _ => None
        }
        _ => None
      }
      
      println("DEBUG: Processing call expression, checking callee...")
      let checked_callee = self.check_apply_expr(callee_expr)
      let mut callee_ty = self.resolve_type_kind(checked_callee.ty)
      println("DEBUG: Call expression - callee type: " + callee_ty.to_string())
      
      // Add more debugging information
      println("DEBUG: Callee kind: " + checked_callee.kind.to_string())
      
      if callee_ty is TypeKind::TypeVar(_) {
        let mut inferred_params : Array[TypeKind] = []
        let mut idx = 0
        while idx < arg_exprs.length() {
          inferred_params = inferred_params + [self.allocate_fresh_type_var()]
          idx = idx + 1
        }
        let inferred_ret = self.allocate_fresh_type_var()
        if !self.is_type_compatible(checked_callee.ty, TypeKind::Function(inferred_params, inferred_ret)) {
          raise TypeCheckError("Function call expects a callable value")
        }
        callee_ty = self.resolve_type_kind(checked_callee.ty)
      }

      match callee_ty {
        TypeKind::Function(param_types, ret_ty) => {
          if param_types.length() != arg_exprs.length() {
            raise TypeCheckError("Function expects " + 
              param_types.length().to_string() + " arguments, but got " + 
              arg_exprs.length().to_string())
          }

          // For generic functions, try to infer type bindings from arguments
          match func_name_opt {
            Some(func_name) => {
              if self.generic_functions.get(func_name) is Some(_) {
                // Save current bindings
                let old_bindings = self.generic_type_bindings.copy()
                // Clear generic type bindings before checking arguments
                self.clear_generic_type_bindings()
                
                // Try to infer generic type bindings from argument types
                let mut i = 0
                while i < arg_exprs.length() {
                  let arg_checked = self.check_expr(arg_exprs[i])
                  // Try to infer bindings by matching parameter type with argument type
                  self.infer_generic_bindings(param_types[i], arg_checked.ty)
                  i = i + 1
                }
                
                // Restore previous bindings after inference
                self.generic_type_bindings = old_bindings
              }
            }
            None => ()
          }

          let mut checked_args : Array[Expr] = []
          let mut concrete_types : Array[TypeKind] = []
          let mut i = 0
          while i < arg_exprs.length() {
            let arg_checked = self.check_expr(arg_exprs[i])

            // Start from resolved kinds for both parameter and argument.
            let mut expected_param_kind = self.resolve_type_kind(param_types[i])
            let mut arg_kind = self.resolve_type_kind(arg_checked.ty)

            // When inside a generic function/struct body with concrete bindings
            // (e.g. T -> Int), apply those bindings to both sides so that we
            // compare concrete types like Int vs Int instead of Int vs T.
            if self.checking_generic_function_body && !self.generic_type_bindings.is_empty() {
              let type_param_map = self.generic_type_bindings.copy()
              expected_param_kind = self.substitute_type_kind_with_map(expected_param_kind, type_param_map)
              arg_kind = self.substitute_type_kind_with_map(arg_kind, type_param_map)
            }

            // Decide whether we need generic compatibility logic or a strict
            // concrete type compatibility check. Use generic compatibility
            // when the parameter type contains any generic type parameters
            // (like T, K, etc.) or TypeVars.
            let use_generic = self.contains_generic_parameter(expected_param_kind) || arg_kind.to_string().contains("TypeVar(")

            let is_compatible = if use_generic {
              // For generic compatibility checking, temporarily preserve current
              // bindings so this check does not mutate global generic bindings.
              let old_bindings = self.generic_type_bindings.copy()
              let result = self.is_generic_compatible(expected_param_kind, arg_kind)
              self.generic_type_bindings = old_bindings
              result
            } else {
              self.is_type_compatible(expected_param_kind, arg_kind)
            }
            
            if !is_compatible {
              let expected = self.type_to_string(expected_param_kind)
              let actual = self.type_to_string(arg_kind)
              raise TypeCheckError("Type mismatch in argument " + (i + 1).to_string() + 
                ": expected " + expected + ", got " + actual)
            }

            println("DEBUG: apply_expr: arg " + i.to_string() + " has type " + arg_kind.to_string())
            checked_args = checked_args + [Expr::{ kind: arg_checked.kind, ty: arg_kind }]
            concrete_types = concrete_types + [arg_kind]
            i = i + 1
          }
          println("DEBUG: apply_expr: concrete_types = " + concrete_types.to_string())
          
          // Special handling for generic enum constructors
          let final_ret_ty = match ret_ty {
            TypeKind::GenericEnum(enum_name, type_args) => {
              // Check if this is a generic enum constructor call
              match func_name_opt {
                Some(func_name) => {
                  // Check if the function name matches an enum variant
                  match self.enum_defs.get(enum_name) {
                    Some(enum_def) => {
                      // Check if func_name is a variant of this enum
                      let mut is_variant = false
                      for variant in enum_def.variants {
                        if variant.name == func_name {
                          is_variant = true
                          break
                        }
                      }
                      
                      if is_variant && type_args.length() == 1 && type_args[0] is TypeKind::TypeVar(_) {
                        // This is a generic enum constructor with one TypeVar parameter
                        // Instantiate it with the concrete type from the argument
                        if concrete_types.length() == 1 {
                          TypeKind::GenericEnum(enum_name, [concrete_types[0]])
                        } else {
                          ret_ty
                        }
                      } else {
                        ret_ty
                      }
                    }
                    None => ret_ty
                  }
                }
                None => ret_ty
              }
            }
            _ => ret_ty
          }
          
          // Record generic instantiation if this is a generic function and
          // rewrite the callee to the monomorphized name when available.
          let mut callee_override_name : String? = None
          match func_name_opt {
            Some(func_name) => {
              if self.generic_functions.get(func_name) is Some(_) {
                self.record_generic_instantiation(func_name, concrete_types)
                match self.monomorphized_instances.get(func_name) {
                  Some(instances) => {
                    let mut mi = 0
                    while mi < instances.length() {
                      let (existing_types, existing_name) = instances[mi]
                      if self.type_arrays_equal(existing_types, concrete_types) {
                        // We'll prefer to call the monomorphized function directly
                        callee_override_name = Some(existing_name)
                        break
                      }
                      mi = mi + 1
                    }
                  }
                  None => ()
                }
              }
            }
            None => ()
          }

          // Before recording instantiation, reconcile any unresolved TypeVars
          // in the concrete_types with the callee's expected parameter types.
          let mut j = 0
          while j < concrete_types.length() {
            let ct = concrete_types[j]
            if ct.to_string().contains("TypeVar(") {
              // Replace with the expected parameter type from callee if available
              if j < param_types.length() {
                concrete_types[j] = self.substitute_type_kind(self.resolve_type_kind(param_types[j]))
              } else {
                concrete_types[j] = self.substitute_type_kind(ct)
              }
            }
            j = j + 1
          }

          // Default final callee is the checked one; allow overriding to monomorphized name
          let mut final_callee = checked_callee
          match callee_override_name {
            Some(ovname_val) => {
              // rewrite callee to the monomorphized identifier
              let ov = ovname_val
              let ov_ty = match self.func_types.get(ov) {
                Some(t) => t
                None => TypeKind::Any
              }
              let atom = AtomExpr::{ kind: AtomExprKind::Ident(ov), ty: ov_ty }
              let new_callee = ApplyExpr::{ kind: ApplyExprKind::AtomExpr(atom), ty: ov_ty }
              // assign overriding callee
              final_callee = new_callee
            }
            None => ()
          }

          // Determine the resolved return type. Prefer to use an instantiated
          // monomorphized function return type if available. The previous
          // heuristic that treated an empty-struct as a "generic" and used
          // the first argument's type caused incorrect behavior when the
          // callee was a local function value (e.g., a parameter). Only
          // apply that heuristic when the callee is a known top-level
          // generic function name.
          let resolved_ret =
            if func_name_opt is Some(func_n) && self.monomorphized_instances.get(func_n) is Some(_) {
              // Try to find the instantiated name for these concrete_types
              match func_name_opt {
                Some(func_n2) => {
                  match self.monomorphized_instances.get(func_n2) {
                    Some(instances) => {
                      let mut found_ret : TypeKind? = None
                      let mut ii = 0
                      while ii < instances.length() {
                        let (existing_types, existing_name) = instances[ii]
                        if self.type_arrays_equal(existing_types, concrete_types) {
                          // If we have a func_types entry for the instantiated name, use its ret
                          match self.func_types.get(existing_name) {
                            Some(TypeKind::Function(_, r)) => { found_ret = Some(r); break }
                            Some(other) => { found_ret = Some(other); break }
                            None => ()
                          }
                        }
                        ii = ii + 1
                      }
                      match found_ret {
                        Some(r) => r
                        None => self.resolve_type_kind(final_ret_ty)
                      }
                    }
                    None => self.resolve_type_kind(final_ret_ty)
                  }
                }
                None => self.resolve_type_kind(final_ret_ty)
              }
            } else {
              // Not a named top-level generic function call: just resolve normally.
              self.resolve_type_kind(final_ret_ty)
            }
          
          ApplyExpr::{
            kind: ApplyExprKind::Call(ApplyExpr::{ kind: final_callee.kind, ty: self.resolve_type_kind(final_callee.ty) }, checked_args),
            ty: resolved_ret
          }
        }
        // Handle generic enum constructors
        TypeKind::GenericEnum(enum_name, type_args) => {
          println("DEBUG: Handling generic enum constructor: " + enum_name)
          // This is a generic enum constructor being called directly
          // We need to infer the concrete types from the arguments and instantiate the enum
          
          // Get the enum definition to check the variant
          match self.enum_defs.get(enum_name) {
            Some(enum_def) => {
              // For a generic enum constructor call, we expect exactly one argument
              // (the value being wrapped in the enum)
              if arg_exprs.length() != 1 {
                raise TypeCheckError("Generic enum constructor expects exactly one argument")
              }
              
              // Check the argument
              let arg_checked = self.check_expr(arg_exprs[0])
              let arg_type = self.resolve_type_kind(arg_checked.ty)
              
              // Create the instantiated enum type
              let instantiated_enum_type = TypeKind::GenericEnum(enum_name, [arg_type])
              
              // Create the result expression
              let checked_args = [Expr::{ kind: arg_checked.kind, ty: arg_type }]
              
              ApplyExpr::{
                kind: ApplyExprKind::Call(checked_callee, checked_args),
                ty: instantiated_enum_type
              }
            }
            None => raise TypeCheckError("Unknown enum: " + enum_name)
          }
        }
        TypeKind::Any => {
          let mut checked_args : Array[Expr] = []
          let mut i = 0
          while i < arg_exprs.length() {
            let arg_checked = self.check_expr(arg_exprs[i])
            checked_args = checked_args + [arg_checked]
            i = i + 1
          }
          ApplyExpr::{
            kind: ApplyExprKind::Call(checked_callee, checked_args),
            ty: TypeKind::Any
          }
        }
        _ => raise TypeCheckError("Expected function type for call, got: " + self.type_to_string(callee_ty))
      }
    }
  }
}
