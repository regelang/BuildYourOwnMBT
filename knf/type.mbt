///|
pub(all) enum Type {
  Unit
  Int
  Bool
  Double
  String
  Array(Type)
  Struct(String)
  Enum(String)  // 枚举类型
  Tuple(Array[Type])
  Function(Array[Type], Type)
}

///|
pub impl Show for Type with output(self, logger) {
  let s = match self {
    Unit => "Unit"
    Int => "Int"
    Bool => "Bool"
    Double => "Double"
    String => "String"
    Array(elem_type) => "Array[\{elem_type}]"
    Struct(name) => "\{name}"
    Enum(name) => "\{name}"
    Tuple(elem_types) => {
      let elem_strs = elem_types.map(et => "\{et}").join(", ")
      "(\{elem_strs})"
    }
    Function(param_types, ret_type) => {
      let param_strs = param_types.map(pt => "\{pt}").join(", ")
      "(\{param_strs}) -> \{ret_type}"
    }
  }
  logger.write_string(s)
}

///|
pub fn Context::typekind_to_knf(
  self : Context,
  tk : @typecheck.TypeKind,
) -> Type raise KnfTransformError {
  // Apply type substitutions if any
  let substituted_tk = if self.type_substitutions.length() > 0 {
    self.apply_type_substitution_knf(tk)
  } else {
    tk
  }
  
  match substituted_tk {
    @typecheck.TypeKind::Unit => Type::Unit
    @typecheck.TypeKind::Bool => Type::Bool
    @typecheck.TypeKind::Int => Type::Int
    @typecheck.TypeKind::Double => Type::Double
    @typecheck.TypeKind::String => Type::String
    @typecheck.TypeKind::Tuple(types) => {
      let knf_types = types.map(fn(t) { self.typekind_to_knf(t) })
      Type::Tuple(knf_types)
    }
    @typecheck.TypeKind::Array(elem_ty) => {
      let knf_elem_ty = self.typekind_to_knf(elem_ty)
      Type::Array(knf_elem_ty)
    }
    @typecheck.TypeKind::Struct(name) => Type::Struct(name)
    @typecheck.TypeKind::Enum(name) => Type::Enum(name)
    @typecheck.TypeKind::GenericEnum(name, type_args) => {
      // For now, convert generic enums to regular enums in KNF
      // In a full implementation, we would need to handle monomorphization
      Type::Enum(name)
    }
    @typecheck.TypeKind::GenericStruct(name, type_args) => {
      // For now, convert generic structs to regular structs in KNF
      // In a full implementation, we would need to handle monomorphization
      Type::Struct(name)
    }
    @typecheck.TypeKind::Function(param_types, ret_ty) => {
      let knf_param_types = param_types.map(fn(t) { self.typekind_to_knf(t) })
      let knf_ret_ty = self.typekind_to_knf(ret_ty)
      Type::Function(knf_param_types, knf_ret_ty)
    }
    @typecheck.TypeKind::Any => Type::Unit // Any类型转换为Unit
    @typecheck.TypeKind::TypeVar(_) => {
      // Debug: print the offending substituted type for easier tracing
      println("KNF ERROR: encountered TypeVar while converting to KNF type: " + substituted_tk.to_string())
      raise KnfTransformError("TypeVar not supported in KNF")
    }
  }
}

///|
pub fn Context::type_to_knf(
  self : Context,
  t : @typecheck.Type,
) -> Type raise KnfTransformError {
  self.typekind_to_knf(t.kind)
}


///| Apply type substitution recursively (KNF version)
fn Context::apply_type_substitution_knf(
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
      let substituted_elem = self.apply_type_substitution_knf(elem_ty)
      @typecheck.TypeKind::Array(substituted_elem)
    }
    @typecheck.TypeKind::Tuple(types) => {
      let substituted_types = types.map(fn(t) { self.apply_type_substitution_knf(t) })
      @typecheck.TypeKind::Tuple(substituted_types)
    }
    @typecheck.TypeKind::Function(params, ret) => {
      let substituted_params = params.map(fn(t) { self.apply_type_substitution_knf(t) })
      let substituted_ret = self.apply_type_substitution_knf(ret)
      @typecheck.TypeKind::Function(substituted_params, substituted_ret)
    }
    @typecheck.TypeKind::GenericEnum(name, type_args) => {
      let substituted_args = type_args.map(fn(t) { self.apply_type_substitution_knf(t) })
      @typecheck.TypeKind::GenericEnum(name, substituted_args)
    }
    @typecheck.TypeKind::GenericStruct(name, type_args) => {
      let substituted_args = type_args.map(fn(t) { self.apply_type_substitution_knf(t) })
      @typecheck.TypeKind::GenericStruct(name, substituted_args)
    }
    @typecheck.TypeKind::TypeVar(id) => {
      // Check if this type variable has a substitution
      match self.type_substitutions.get("TypeVar(" + id.to_string() + ")") {
        Some(substituted) => substituted
        None => ty
      }
    }
    _ => ty
  }
}
