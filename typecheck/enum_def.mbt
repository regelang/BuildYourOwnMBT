///| 枚举定义
pub(all) struct EnumDef {
  name : String
  type_params : Array[String]      // 泛型类型参数列表（如 ["T"]）
  variants : Array[EnumVariant]
} derive(Show)

///| 枚举变体
pub(all) struct EnumVariant {
  name : String
  params : Array[TypeKind]  // 变体参数类型
} derive(Show)

///| 检查枚举定义
pub fn Context::check_enum_def(
  self : Context,
  enum_def : @parser.EnumDef
) -> EnumDef raise TypeCheckError {
  // Create a temporary context for checking this enum with its type parameters
  let ctx = Context::{
    type_env: self.type_env,
    type_vars: self.type_vars,
    struct_defs: self.struct_defs,
    enum_defs: self.enum_defs,
    func_types: self.func_types,
    current_func_ret_ty: self.current_func_ret_ty,
    checking_structs: self.checking_structs,
    generic_functions: self.generic_functions,
    monomorphized_instances: self.monomorphized_instances,
    current_generic_type: self.current_generic_type,
    generic_type_bindings: self.generic_type_bindings,
    generic_recursion_counter: self.generic_recursion_counter,
    checking_generic_function_body: self.checking_generic_function_body,
  }
  
  // Register the generic type parameters in the context
  let mut i = 0
  while i < enum_def.type_params.length() {
    let param_name = enum_def.type_params[i]
    // Create a placeholder type for the generic parameter
    let generic_type = TypeKind::TypeVar(i)
    ctx.type_env.set(param_name, Type::{ kind: generic_type, mutable: false })
    ctx.func_types.set(param_name, generic_type)
    i = i + 1
  }
  
  // 检查变体
  let mut checked_variants : Array[EnumVariant] = []
  let mut j = 0
  while j < enum_def.variants.length() {
    let variant = enum_def.variants[j]
    
    // 检查变体参数类型
    let mut param_types : Array[TypeKind] = []
    let mut k = 0
    while k < variant.params.length() {
      let param_ty = ctx.check_parser_type(variant.params[k])
      param_types = param_types + [ctx.resolve_type_kind(param_ty.kind)]
      k = k + 1
    }
    
    checked_variants = checked_variants + [EnumVariant::{
      name: variant.name,
      params: param_types
    }]
    j = j + 1
  }
  
  EnumDef::{
    name: enum_def.name,
    type_params: enum_def.type_params,  // Include type parameters
    variants: checked_variants
  }
}