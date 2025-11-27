///|
pub(all) struct LetStmt {
  pattern : Pattern
  ty : TypeKind
  expr : Expr
} derive(Show)

///|
pub(all) struct Pattern {
  kind : PatternKind
} derive(Show, Eq)

///|
pub(all) enum PatternKind {
  Wildcard
  Ident(String)
  Tuple(Array[Pattern])
  Constructor(String, Array[Pattern])  // 枚举构造器模式
} derive(Show, Eq)

///|
pub fn Context::check_let_stmt(
  self : Context,
  let_stmt : @parser.LetStmt,
) -> LetStmt raise TypeCheckError {
  let checked_expr = self.check_expr(let_stmt.expr)
  let resolved_expr = Expr::{
    kind: checked_expr.kind,
    ty: self.resolve_type_kind(checked_expr.ty)
  }

  let final_kind = match let_stmt.ty {
    Some(parser_ty) => {
      let annotated_type = self.check_parser_type(parser_ty)
      if !self.is_type_compatible(annotated_type.kind, resolved_expr.ty) {
        raise TypeCheckError("Expression type does not match annotation in let")
      }
      self.resolve_type_kind(annotated_type.kind)
    }
    None => resolved_expr.ty
  }

  let final_expr = Expr::{ kind: resolved_expr.kind, ty: final_kind }
  let checked_pattern = self.check_pattern(let_stmt.pattern, final_kind, false)

  LetStmt::{
    pattern: checked_pattern,
    ty: final_kind,
    expr: final_expr
  }
}

fn Context::check_pattern(
  self : Context,
  pattern : @parser.Pattern,
  value_ty : TypeKind,
  mutable : Bool,
) -> Pattern raise TypeCheckError {
  let resolved_value = self.resolve_type_kind(value_ty)
  match pattern.kind {
    @parser.PatternKind::Wildcard => {
      Pattern::{ kind: PatternKind::Wildcard }
    }
    @parser.PatternKind::Ident(name) => {
      println("DEBUG: Binding pattern variable " + name + " to type " + resolved_value.to_string())
      self.type_env.set(name, Type::{ kind: resolved_value, mutable: mutable })
      Pattern::{ kind: PatternKind::Ident(name) }
    }
    @parser.PatternKind::Constructor(constructor_name, sub_patterns) => {
      // 检查构造器是否存在
      let enum_name_opt = self.find_enum_for_constructor(constructor_name)
      let enum_name = match enum_name_opt {
        Some(name) => name
        None => raise TypeCheckError("Unknown constructor: " + constructor_name)
      }
      
      // 获取枚举定义
      let enum_def = match self.enum_defs.get(enum_name) {
        Some(def) => def
        None => raise TypeCheckError("Enum not found: " + enum_name)
      }
      
      // 找到对应的变体。这里既支持裸变体名（例如 "Nil"），也支持
      // 带枚举前缀的形式（例如 "Node::Nil"）。
      let mut variant_opt : EnumVariant? = None
      let mut i = 0
      while i < enum_def.variants.length() {
        let vname = enum_def.variants[i].name
        let qualified = enum_name + "::" + vname
        if vname == constructor_name || qualified == constructor_name {
          variant_opt = Some(enum_def.variants[i])
          break
        }
        i = i + 1
      }
      
      let variant = match variant_opt {
        Some(v) => v
        None => raise TypeCheckError("Constructor not found: " + constructor_name)
      }
      
      // 检查参数数量
      // 特殊情况：如果只有一个参数且是通配符，则展开为所有字段的通配符
      let actual_sub_patterns = if sub_patterns.length() == 1 && 
                                    sub_patterns[0].kind == @parser.PatternKind::Wildcard &&
                                    variant.params.length() > 1 {
        // 展开单个通配符为多个通配符
        let mut wildcards : Array[@parser.Pattern] = []
        let mut k = 0
        while k < variant.params.length() {
          wildcards = wildcards + [@parser.Pattern::{ kind: @parser.PatternKind::Wildcard }]
          k = k + 1
        }
        wildcards
      } else {
        sub_patterns
      }
      
      if variant.params.length() != actual_sub_patterns.length() {
        raise TypeCheckError("Constructor " + constructor_name + " expects " + 
                           variant.params.length().to_string() + " arguments, but got " +
                           actual_sub_patterns.length().to_string())
      }
      
      // 检查值类型是否匹配枚举类型，并处理泛型枚举的类型实例化
      let (expected_enum_type, instantiated_param_types) = match value_ty {
        TypeKind::GenericEnum(scrutinee_name, concrete_args) => {
          // For generic enums, we need to instantiate the pattern parameter types
          // with the concrete types from the scrutinee
          if scrutinee_name != enum_name {
            raise TypeCheckError("Pattern type mismatch: expected " + enum_name + ", got " + scrutinee_name)
          }
          
          println("DEBUG: Pattern matching - concrete_args: " + concrete_args.to_string())
          
          // Instantiate the variant parameter types with concrete types
          // For TypeVar(i), substitute with concrete_args[i]
          // For Struct(name) where name is a generic type parameter, substitute with concrete_args[...]
          let mut instantiated_params : Array[TypeKind] = []
          let mut j = 0
          while j < variant.params.length() {
            let instantiated = match variant.params[j] {
              TypeKind::TypeVar(id) => {
                // For generic enums, the TypeVar(id) corresponds to the id-th type parameter
                // of the enum. We need to substitute it with the corresponding concrete type
                // from the scrutinee's type arguments.
                println("DEBUG: Pattern matching - TypeVar(" + id.to_string() + ") with concrete_args length " + concrete_args.length().to_string())
                println("DEBUG: Pattern matching - variant.params[j]: " + variant.params[j].to_string())
                if id < concrete_args.length() {
                  println("DEBUG: Pattern matching - substituting with concrete_args[" + id.to_string() + "] = " + concrete_args[id].to_string())
                  concrete_args[id]
                } else {
                  println("DEBUG: Pattern matching - fallback to original")
                  variant.params[j]  // Fallback to original if index out of bounds
                }
              }
              TypeKind::Struct(name) => {
                // Check if this is a generic type parameter (single uppercase letter)
                if name.length() == 1 && {
                  name == "T" || name == "K" || name == "V" || name == "E" || name == "R" || 
                  name == "A" || name == "B" || name == "C" || name == "D" || name == "F" ||
                  name == "G" || name == "H" || name == "I" || name == "J" || name == "L" ||
                  name == "M" || name == "N" || name == "O" || name == "P" || name == "Q" ||
                  name == "S" || name == "U" || name == "W" || name == "X" || name == "Y" || name == "Z"
                } {
                  // This is a generic type parameter - we need to map it to the concrete type
                  // First, check if we have a binding for this type parameter in the current context
                  match self.get_generic_type_binding(name) {
                    Some(binding) => {
                      println("DEBUG: Pattern matching - Struct(" + name + ") substituting with generic binding: " + binding.to_string())
                      binding
                    }
                    None => {
                      // If we're in a generic function body and don't have a binding,
                      // we should leave the type parameter as is for now
                      if self.checking_generic_function_body {
                        println("DEBUG: Pattern matching - Struct(" + name + ") in generic function body, leaving as is")
                        variant.params[j]
                      } else {
                        // Find the index of this type parameter in the enum's type parameters
                        let mut param_index = -1
                        let mut k = 0
                        while k < enum_def.type_params.length() {
                          if enum_def.type_params[k] == name {
                            param_index = k
                            break
                          }
                          k = k + 1
                        }
                        
                        if param_index >= 0 && param_index < concrete_args.length() {
                          println("DEBUG: Pattern matching - Struct(" + name + ") substituting with concrete_args[" + param_index.to_string() + "] = " + concrete_args[param_index].to_string())
                          concrete_args[param_index]
                        } else {
                          println("DEBUG: Pattern matching - Struct(" + name + ") fallback to original")
                          variant.params[j]  // Fallback to original if not found
                        }
                      }
                    }
                  }
                } else {
                  println("DEBUG: Pattern matching - Struct(" + name + ") not a generic parameter")
                  variant.params[j]  // Not a generic type parameter, keep as is
                }
              }
              _ => {
                println("DEBUG: Pattern matching - not a TypeVar or generic Struct: " + variant.params[j].to_string())
                variant.params[j]  // For non-TypeVar types, keep as is
              }
            }
            println("DEBUG: Pattern matching - instantiated parameter " + j.to_string() + ": " + instantiated.to_string())
            instantiated_params = instantiated_params + [instantiated]
            j = j + 1
          }
          
          (value_ty, instantiated_params)
        }
        _ => {
          // For non-generic enums, use the original parameter types
          (TypeKind::Enum(enum_name), variant.params)
        }
      }
      
      println("DEBUG: Pattern matching - value_ty: " + value_ty.to_string() + ", expected_enum_type: " + expected_enum_type.to_string() + ", enum_name: " + enum_name)
      if !self.is_type_compatible(expected_enum_type, value_ty) {
        raise TypeCheckError("Pattern type mismatch: expected " + enum_name)
      }
      
      // 检查子模式
      let mut checked_sub_patterns : Array[Pattern] = []
      let mut j = 0
      while j < actual_sub_patterns.length() {
        let sub_pattern = self.check_pattern(actual_sub_patterns[j], instantiated_param_types[j], mutable)
        checked_sub_patterns = checked_sub_patterns + [sub_pattern]
        j = j + 1
      }
      
      Pattern::{ kind: PatternKind::Constructor(constructor_name, checked_sub_patterns) }
    }
    @parser.PatternKind::Tuple(sub_patterns) => {
      let tuple_types = match resolved_value {
        TypeKind::Tuple(existing_types) => {
          if existing_types.length() != sub_patterns.length() {
            raise TypeCheckError("Tuple pattern length mismatch")
          }
          let mut resolved_types : Array[TypeKind] = []
          let mut i = 0
          while i < existing_types.length() {
            resolved_types = resolved_types + [self.resolve_type_kind(existing_types[i])]
            i = i + 1
          }
          resolved_types
        }
        TypeKind::Any => {
          let mut any_types : Array[TypeKind] = []
          let mut i = 0
          while i < sub_patterns.length() {
            any_types = any_types + [TypeKind::Any]
            i = i + 1
          }
          any_types
        }
        TypeKind::TypeVar(_) => {
          let mut fresh_types : Array[TypeKind] = []
          let mut i = 0
          while i < sub_patterns.length() {
            fresh_types = fresh_types + [self.allocate_fresh_type_var()]
            i = i + 1
          }
          if !self.is_type_compatible(value_ty, TypeKind::Tuple(fresh_types)) {
            raise TypeCheckError("Tuple pattern type mismatch")
          }
          let mut resolved_types : Array[TypeKind] = []
          let mut j = 0
          while j < fresh_types.length() {
            resolved_types = resolved_types + [self.resolve_type_kind(fresh_types[j])]
            j = j + 1
          }
          resolved_types
        }
        _ => raise TypeCheckError("Tuple pattern requires tuple value")
      }

      if tuple_types.length() != sub_patterns.length() {
        raise TypeCheckError("Tuple pattern length mismatch")
      }

      let mut checked_patterns : Array[Pattern] = []
      let mut idx = 0
      while idx < sub_patterns.length() {
        let sub_pattern = self.check_pattern(sub_patterns[idx], tuple_types[idx], mutable)
        checked_patterns = checked_patterns + [sub_pattern]
        idx = idx + 1
      }

      Pattern::{ kind: PatternKind::Tuple(checked_patterns) }
    }
  }
}
