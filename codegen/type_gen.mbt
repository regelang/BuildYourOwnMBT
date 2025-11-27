///|
pub fn Context::type_codegen_opaque(
  self : Context,
  knf_type : @knf.Type,
) -> &@llvm.Type {
  match knf_type {
    Int => (self.llvm_ctx.getInt32Ty() : &@llvm.Type)
    Bool => self.llvm_ctx.getInt1Ty()
    // Unit 在作为变量/字段/参数时，不能直接映射为 void，
    // 否则在构造结构体类型并查询 DataLayout 时会触发 VoidType 错误。
    // 这里使用 i8 作为占位类型。
    Unit => self.llvm_ctx.getInt8Ty()
    Double => self.llvm_ctx.getDoubleTy()
    Array(_) => self.llvm_ctx.getPtrTy()
    String(_) => self.llvm_ctx.getPtrTy()
    Tuple(_) => self.llvm_ctx.getPtrTy()
    Struct(_) => self.llvm_ctx.getPtrTy()
    Enum(_) => self.llvm_ctx.getPtrTy()  // 枚举作为指针类型
    Function(_) => self.llvm_ctx.getPtrTy()
  }
}

///|
pub fn Context::type_codegen_concrete(
  self : Context,
  knf_type : @knf.Type,
) -> &@llvm.Type raise {
  match knf_type {
    Int => (self.llvm_ctx.getInt32Ty() : &@llvm.Type)
    Bool => self.llvm_ctx.getInt1Ty()
    Unit => self.llvm_ctx.getVoidTy()
    Double => self.llvm_ctx.getDoubleTy()
    Array(_) => self.llvm_ctx.getPtrTy()
    String(_) => self.llvm_ctx.getPtrTy()
    Tuple(elem_types) => {
      // 元组在 LLVM 中用结构体表示，字段类型必须是实体类型，不能为 void。
      let llvm_elem_types = elem_types.map(elem_type => match elem_type {
        @knf.Type::Unit => (self.llvm_ctx.getInt8Ty() : &@llvm.Type)
        _ => self.type_codegen_concrete(elem_type)
      })
      self.llvm_ctx.getStructType(llvm_elem_types)
    }
    Struct(struct_name) => self.struct_types.get(struct_name).unwrap()
    Enum(enum_name) => self.enum_types.get(enum_name).unwrap()
    Function(param_types, return_type) => {
      // Convert Unit parameters to i8 (void is not allowed as parameter type)
      let llvm_param_types : Array[&@llvm.Type] = []
      for param_type in param_types {
        let llvm_ty : &@llvm.Type = match param_type {
          @knf.Type::Unit => (self.llvm_ctx.getInt8Ty() : &@llvm.Type)
          _ => self.type_codegen_concrete(param_type)
        }
        llvm_param_types.push(llvm_ty)
      }
      // 返回类型：Unit 映射为 void，其他类型使用 opaque 映射（不会是 void）。
      let llvm_return_type : &@llvm.Type = match return_type {
        @knf.Type::Unit => (self.llvm_ctx.getVoidTy() : &@llvm.Type)
        _ => self.type_codegen_opaque(return_type)
      }
      self.llvm_ctx.getFunctionType(llvm_return_type, llvm_param_types)
    }
  }
}

///|
///|
pub fn Context::collect_struct_types(
  self : Context,
  knf_structs : Map[String, @knf.KnfStructDef],
) -> Unit raise {
  for sname, knf_struct in knf_structs {
    // Skip empty structs (generic type placeholders)
    if knf_struct.fields.length() == 0 {
      // For generic types, we don't need to create an LLVM struct type
      // They will be treated as opaque pointers
      continue
    }
    
    let field_types : Array[&@llvm.Type] = Array::new()
    for field in knf_struct.fields {
      let llvm_field_type = self.type_codegen_opaque(field.2)
      field_types.push(llvm_field_type)
    }
    let llvm_struct_type = self.llvm_ctx.getStructType(field_types, name=sname)
    self.struct_types.set(sname, llvm_struct_type)
    self.knf_struct_types.set(sname, knf_struct)
  }
}

///|
pub fn Context::collect_func_values(
  self : Context,
  knf_funcs : Map[String, @knf.KnfFunction],
) -> Unit raise {
  let env_ptr_ty = self.llvm_ctx.getPtrTy()
  for fname, func in knf_funcs {
    let { params, ret_ty, .. } = func
    let param_types : Array[&@llvm.Type] = []
    if fname != "main" {
      param_types.push(env_ptr_ty)
    }
    params.each(param => {
      // Unit type cannot be a function parameter in LLVM, use i8 instead
      let llvm_param_ty : &@llvm.Type = match param.1 {
        @knf.Type::Unit => (self.llvm_ctx.getInt8Ty() : &@llvm.Type)
        _ => self.type_codegen_opaque(param.1)
      }
      param_types.push(llvm_param_ty)
    })
    let llvm_ret_ty : &@llvm.Type = match ret_ty {
      @knf.Type::Unit => (self.llvm_ctx.getVoidTy() : &@llvm.Type)
      _ => self.type_codegen_opaque(ret_ty)
    }
    let llvm_fn_ty = self.llvm_ctx.getFunctionType(llvm_ret_ty, param_types)
    // 为 main 函数添加 minimbt_ 前缀
    let llvm_fname = if fname == "main" { "minimbt_main" } else { fname }
    let llvm_func = try! self.llvm_mod.addFunction(llvm_fn_ty, llvm_fname)
    self.functions.set(fname, llvm_func)
  }
}

///| 收集枚举类型定义
///
/// 枚举使用 tagged union 表示：
/// struct EnumValue {
///   i32 tag;      // 变体标签
///   i64 field1;   // 第一个字段（使用 i64 以支持 Double）
///   i64 field2;   // 第二个字段
///   i64 field3;   // 第三个字段
///   ...
/// }
pub fn Context::collect_enum_types(
  self : Context,
  knf_enums : Map[String, @knf.KnfEnumDef],
) -> Unit raise {
  for enum_name, knf_enum in knf_enums {
    // 计算最大字段数
    let mut max_fields = 0
    for variant in knf_enum.variants {
      if variant.params.length() > max_fields {
        max_fields = variant.params.length()
      }
    }
    
    // 创建枚举结构：{ i32 tag, i64 field1, i64 field2, ... }
    let field_types : Array[&@llvm.Type] = Array::new()
    
    // 第一个字段是 tag
    field_types.push(self.llvm_ctx.getInt32Ty())
    
    // 添加数据字段（使用 i64 作为通用类型，可以存储 Double 和指针）
    let mut i = 0
    while i < max_fields {
      field_types.push(self.llvm_ctx.getInt64Ty())
      i = i + 1
    }
    
    let llvm_enum_type = self.llvm_ctx.getStructType(field_types, name=enum_name)
    self.enum_types.set(enum_name, llvm_enum_type)
    self.knf_enum_types.set(enum_name, knf_enum)
  }
}
