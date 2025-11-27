///|
pub(all) struct KnfStructDef {
  name : String
  // field name, is_mut, field type
  fields : Array[(String, Bool, Type)]
}

///|
pub fn Context::struct_def_to_knf(
  self : Context,
  struct_def : @typecheck.StructDef,
) -> KnfStructDef raise KnfTransformError {
  let mut knf_fields : Array[(String, Bool, Type)] = []
  let mut i = 0
  while i < struct_def.fields.length() {
    let field = struct_def.fields[i]
    let field_ty = self.type_to_knf(field.ty)
    knf_fields = knf_fields + [(field.name, field.ty.mutable, field_ty)]
    i = i + 1
  }

  KnfStructDef::{
    name: struct_def.name,
    fields: knf_fields,
  }
}

///|
pub fn KnfStructDef::get_field_index(
  self : KnfStructDef,
  field_name : String,
) -> Int? {
  for i, f in self.fields {
    let (name, _, _) = f
    if name == field_name {
      return Some(i)
    }
  }
  None
}

///|
pub impl Show for KnfStructDef with output(self, logger) {
  let { name, fields } = self
  logger.write_string("struct \{name} {\n")
  for field in fields {
    let (field_name, is_mut, field_type) = field
    let mutability = if is_mut { "mut " } else { "" }
    logger.write_string("  \{mutability}\{field_name}: \{field_type};\n")
  }
  logger.write_string("}\n")
}
