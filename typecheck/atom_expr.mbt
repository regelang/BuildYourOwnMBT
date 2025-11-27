///|
pub(all) struct AtomExpr {
  kind : AtomExprKind
  ty : TypeKind
} derive(Show)

///|
pub(all) enum AtomExprKind {
  Int(Int) // 1, 42, etc
  Double(Double) // 1.0, 3.14, etc
  Bool(Bool) // true | false
  String(String) // "hello", etc
  Ident(String) // var
  Unit // ()
  Paren(Expr) // (expr)
  Tuple(Array[Expr]) // (expr, expr, ...)
  Array(Array[Expr]) // [expr, expr, ...]
  ArrayMake(Expr, Expr) // Array::make(size, init)
  StructConstruct(StructConstructExpr) // StructName::{ field: expr, ... }
  EnumVariant(String, String) // EnumName::VariantName
} derive(Show)

///|
pub fn Context::check_atom_expr(
  self : Self,
  atom_expr : @parser.AtomExpr,
) -> AtomExpr raise TypeCheckError {
  match atom_expr.kind {
    @parser.AtomExprKind::EnumVariant(enum_name, variant_name) => {
      // 处理枚举变体表达式
      match self.enum_defs.get(enum_name) {
        Some(enum_def) => {
          // 检查变体是否存在
          let mut found = false
          let mut variant_opt : EnumVariant? = None
          for variant in enum_def.variants {
            if variant.name == variant_name {
              found = true
              variant_opt = Some(variant)
              break
            }
          }
          if !found {
            raise TypeCheckError("Unknown variant '" + variant_name + "' in enum '" + enum_name + "'")
          }
          
          // Determine the appropriate type for the enum variant
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
              println("DEBUG: EnumVariant for generic enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
              func_type
            } else {
              // Constructor with parameters: Cons : (T, Node[T]) -> Node[T]
              let func_type = TypeKind::Function(variant.params, enum_type)
              println("DEBUG: EnumVariant for generic enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
              func_type
            }
          } else {
            // For regular enums, use the simple Enum type
            let enum_type = TypeKind::Enum(enum_name)
            if variant.params.length() == 0 {
              // Simple constructor (no parameters): Red : Color
              println("DEBUG: EnumVariant for enum " + enum_name + "::" + variant_name + " has type " + enum_type.to_string())
              enum_type
            } else {
              // Constructor with parameters: RGB : (Int, Int, Int) -> Color
              let func_type = TypeKind::Function(variant.params, enum_type)
              println("DEBUG: EnumVariant for enum " + enum_name + "::" + variant_name + " has type " + func_type.to_string())
              func_type
            }
          }
          
          AtomExpr::{
            kind: AtomExprKind::EnumVariant(enum_name, variant_name),
            ty: expr_type
          }
        }
        None => raise TypeCheckError("Unknown enum: " + enum_name)
      }
    }
    @parser.AtomExprKind::Int(value) => {
      AtomExpr::{
        kind: AtomExprKind::Int(value),
        ty: TypeKind::Int
      }
    }
    @parser.AtomExprKind::Double(value) => {
      AtomExpr::{
        kind: AtomExprKind::Double(value),
        ty: TypeKind::Double
      }
    }
    @parser.AtomExprKind::Bool(value) => {
      AtomExpr::{
        kind: AtomExprKind::Bool(value),
        ty: TypeKind::Bool
      }
    }
    @parser.AtomExprKind::String(value) => {
      AtomExpr::{
        kind: AtomExprKind::String(value),
        ty: TypeKind::String
      }
    }
    @parser.AtomExprKind::Ident(name) => {
      let var_name = name
      match self.type_env.get(var_name) {
        Some(var_type) => {
          // Resolve the identifier's type so generic parameters use any current bindings.
          let resolved_kind = self.resolve_type_kind(var_type.kind)
          AtomExpr::{
            kind: AtomExprKind::Ident(var_name),
            ty: resolved_kind
          }
        }
        None => {
          // Check if it's a built-in function
          match self.func_types.get(var_name) {
            Some(func_type) => {
              AtomExpr::{
                kind: AtomExprKind::Ident(var_name),
                ty: func_type
              }
            }
            None => raise TypeCheckError("Unknown identifier: " + var_name)
          }
        }
      }
    }
    @parser.AtomExprKind::Unit => {
      AtomExpr::{
        kind: AtomExprKind::Unit,
        ty: TypeKind::Unit
      }
    }
    @parser.AtomExprKind::Paren(expr) => {
      let checked = self.check_expr(expr)
      AtomExpr::{
        kind: AtomExprKind::Paren(checked),
        ty: checked.ty
      }
    }
    @parser.AtomExprKind::Tuple(exprs) => {
      let (kind, ty) = self.check_tuple_expr(exprs)
      AtomExpr::{
        kind: kind,
        ty: ty
      }
    }
    @parser.AtomExprKind::Array(exprs) => {
      let (kind, ty) = self.check_array_expr(exprs)
      AtomExpr::{
        kind: kind,
        ty: ty
      }
    }
    @parser.AtomExprKind::ArrayMake(size_expr, init_expr) => {
      let (kind, ty) = self.check_array_make_expr(size_expr, init_expr)
      AtomExpr::{
        kind: kind,
        ty: ty
      }
    }
    @parser.AtomExprKind::StructConstruct(sc_expr) => {
      let (kind, ty) = self.check_struct_construct_expr(sc_expr)
      AtomExpr::{
        kind: kind,
        ty: ty
      }
    }
  }
}

pub fn Context::check_tuple_expr(
  self : Context,
  exprs : Array[@parser.Expr],
) -> (AtomExprKind, TypeKind) raise TypeCheckError {
  let mut types : Array[TypeKind] = []
  let mut checked_exprs : Array[Expr] = []

  let mut i = 0
  while i < exprs.length() {
    let checked = self.check_expr(exprs[i])
    println("DEBUG: check_tuple_expr: element " + i.to_string() + " has type " + checked.ty.to_string())
    let resolved_ty = self.resolve_type_kind(checked.ty)
    println("DEBUG: check_tuple_expr: after resolve, element " + i.to_string() + " has type " + resolved_ty.to_string())
    checked_exprs = checked_exprs + [Expr::{ kind: checked.kind, ty: resolved_ty }]
    types = types + [resolved_ty]
    i = i + 1
  }

  println("DEBUG: check_tuple_expr: final tuple type is " + TypeKind::Tuple(types).to_string())
  (AtomExprKind::Tuple(checked_exprs), TypeKind::Tuple(types))
}

pub fn Context::check_array_expr(
  self : Context,
  exprs : Array[@parser.Expr],
) -> (AtomExprKind, TypeKind) raise TypeCheckError {
  if exprs.length() == 0 {
    let ty_var = self.allocate_fresh_type_var()
    return (AtomExprKind::Array([]), TypeKind::Array(ty_var))
  }

  let mut checked_exprs : Array[Expr] = []
  let first_checked = self.check_expr(exprs[0])
  let mut element_type = self.resolve_type_kind(first_checked.ty)
  checked_exprs = checked_exprs + [Expr::{ kind: first_checked.kind, ty: element_type }]

  let mut i = 1
  while i < exprs.length() {
    let checked = self.check_expr(exprs[i])
    let item_type = self.resolve_type_kind(checked.ty)
    if !self.is_type_compatible(element_type, item_type) {
      raise TypeCheckError("Array elements must have compatible types")
    }
    let resolved_item_type = self.resolve_type_kind(item_type)
    element_type = self.resolve_type_kind(element_type)
    if element_type is TypeKind::TypeVar(_) {
      element_type = resolved_item_type
    }
    checked_exprs = checked_exprs + [Expr::{ kind: checked.kind, ty: resolved_item_type }]
    i = i + 1
  }

  element_type = self.resolve_type_kind(element_type)
  (AtomExprKind::Array(checked_exprs), TypeKind::Array(element_type))
}

pub fn Context::resolve_type_kind(self : Context, ty : TypeKind) -> TypeKind {
  let mut current_ty = ty
  if self.checking_generic_function_body && !self.generic_type_bindings.is_empty() {
    let binding_map = self.generic_type_bindings.copy()
    current_ty = self.substitute_type_kind_with_map(current_ty, binding_map)
  }

  match current_ty {
    TypeKind::TypeVar(id) => {
      let resolved = self.resolve_type_var(id)
      match resolved {
        TypeKind::TypeVar(other_id) if other_id == id => resolved
        _ => self.resolve_type_kind(resolved)
      }
    }
    TypeKind::Struct(name) => {
      // If this struct name corresponds to a generic type parameter, use any
      // existing binding regardless of whether we're currently checking a generic
      // function body. This allows monomorphized bodies to see the concrete type
      // while still leaving truly unbound generics untouched.
      match self.generic_type_bindings.get(name) {
        Some(bound_type) => {
          println("DEBUG: resolve_type_kind: resolving " + name + " to " + bound_type.to_string())
          // If the bound type is structurally identical to the current type
          // (e.g. T mapped to T itself), do not recurse.
          if types_equal_simple(current_ty, bound_type) {
            return current_ty
          }
          // If the bound type still contains this generic parameter name
          // (e.g. T -> List[T]), avoid resolving it further to prevent
          // infinite expansion.
          if contains_generic_param(bound_type, name) {
            println("DEBUG: resolve_type_kind: skipping infinite resolution " + name + " -> " + bound_type.to_string())
            return current_ty
          }
          self.resolve_type_kind(bound_type)
        }
        None => {
          if self.checking_generic_function_body {
            println("DEBUG: resolve_type_kind: in generic function body, " + name + " has no binding yet")
          }
          ty
        }
      }
    }
    TypeKind::Array(elem_ty) => {
      TypeKind::Array(self.resolve_type_kind(elem_ty))
    }
    TypeKind::Tuple(types) => {
      let mut resolved_types : Array[TypeKind] = []
      let mut i = 0
      while i < types.length() {
        resolved_types = resolved_types + [self.resolve_type_kind(types[i])]
        i = i + 1
      }
      TypeKind::Tuple(resolved_types)
    }
    TypeKind::Function(param_types, ret_ty) => {
      let mut resolved_params : Array[TypeKind] = []
      let mut i = 0
      while i < param_types.length() {
        resolved_params = resolved_params + [self.resolve_type_kind(param_types[i])]
        i = i + 1
      }
      TypeKind::Function(resolved_params, self.resolve_type_kind(ret_ty))
    }
    TypeKind::GenericEnum(name, type_args) => {
      // Resolve type arguments recursively
      let mut resolved_args : Array[TypeKind] = []
      let mut i = 0
      while i < type_args.length() {
        resolved_args = resolved_args + [self.resolve_type_kind(type_args[i])]
        i = i + 1
      }
      TypeKind::GenericEnum(name, resolved_args)
    }
    TypeKind::GenericStruct(name, type_args) => {
      // Resolve type arguments recursively
      let mut resolved_args : Array[TypeKind] = []
      let mut i = 0
      while i < type_args.length() {
        resolved_args = resolved_args + [self.resolve_type_kind(type_args[i])]
        i = i + 1
      }
      TypeKind::GenericStruct(name, resolved_args)
    }
    _ => ty
  }
}

pub fn Context::check_array_make_expr(
  self : Context,
  size_expr : @parser.Expr,
  init_expr : @parser.Expr,
) -> (AtomExprKind, TypeKind) raise TypeCheckError {
  let checked_size = self.check_expr(size_expr)
  match checked_size.ty {
    TypeKind::Int => ()
    _ => raise TypeCheckError("Array::make size must be Int")
  }

  let checked_init = self.check_expr(init_expr)
  let resolved_init_ty = self.resolve_type_kind(checked_init.ty)
  (
    AtomExprKind::ArrayMake(checked_size, Expr::{ kind: checked_init.kind, ty: resolved_init_ty }),
    TypeKind::Array(resolved_init_ty)
  )
}
