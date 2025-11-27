///| KNF 枚举定义
pub(all) struct KnfEnumDef {
  name : String
  variants : Array[KnfEnumVariant]
}

///| KNF 枚举变体
pub(all) struct KnfEnumVariant {
  name : String
  tag : Int  // 变体的标签值
  params : Array[Type]  // 参数类型
}

///| 将类型检查后的枚举定义转换为 KNF 形式
pub fn Context::enum_def_to_knf(
  self : Context,
  enum_def : @typecheck.EnumDef
) -> KnfEnumDef raise KnfTransformError {
  let mut knf_variants : Array[KnfEnumVariant] = []
  let mut i = 0
  while i < enum_def.variants.length() {
    let variant = enum_def.variants[i]
    
    // 转换参数类型
    let mut param_types : Array[Type] = []
    let mut j = 0
    while j < variant.params.length() {
      param_types = param_types + [self.typekind_to_knf(variant.params[j])]
      j = j + 1
    }
    
    knf_variants = knf_variants + [KnfEnumVariant::{
      name: variant.name,
      tag: i,  // 使用索引作为标签
      params: param_types
    }]
    i = i + 1
  }
  
  KnfEnumDef::{
    name: enum_def.name,
    variants: knf_variants
  }
}
