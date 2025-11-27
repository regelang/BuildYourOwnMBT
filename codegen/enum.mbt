///| 枚举构造器代码生成
///
/// 为枚举变体生成构造器函数
/// 构造器函数的签名：
/// - 无参数变体：fn Red() -> Color
/// - 带参数变体：fn RGB(r: Int, g: Int, b: Int) -> Color
pub fn Context::generate_enum_constructors(
  self : Context,
  knf_enums : Map[String, @knf.KnfEnumDef],
) -> Unit raise {
  for enum_name, knf_enum in knf_enums {
    let enum_type = match self.enum_types.get(enum_name) {
      Some(ty) => ty
      None => raise CodegenError("Enum type not found: " + enum_name)
    }
    
    // 为每个变体生成构造器函数
    for variant in knf_enum.variants {
      self.generate_constructor(enum_name, enum_type, variant)
    }
  }
}

///| 生成单个构造器函数
fn Context::generate_constructor(
  self : Context,
  _enum_name : String,
  enum_type : @llvm.StructType,
  variant : @knf.KnfEnumVariant,
) -> Unit raise {
  // 构造器函数签名
  let param_types : Array[&@llvm.Type] = []
  
  // 添加环境指针（如果不是 main）
  let env_ptr_ty = self.llvm_ctx.getPtrTy()
  param_types.push(env_ptr_ty)
  
  // 添加变体参数
  for param_ty in variant.params {
    param_types.push(self.type_codegen_opaque(param_ty))
  }
  
  // 返回类型是枚举类型的指针
  let ret_ty = self.llvm_ctx.getPtrTy()
  
  // 创建函数
  let func_ty = self.llvm_ctx.getFunctionType(ret_ty, param_types)
  let func = try! self.llvm_mod.addFunction(func_ty, variant.name)
  
  // 注册函数
  self.functions.set(variant.name, func)
  
  // 生成函数体
  let entry_bb = func.addBasicBlock(name="entry")
  self.builder.setInsertPoint(entry_bb)
  
  // 分配枚举值的内存
  let data_layout = self.llvm_mod.getDataLayout()
  let enum_size = data_layout.getTypeAllocSize(enum_type)
  let size_val = self.llvm_ctx.getConstInt32(enum_size)
  
  let malloc_func = match self.builtin_funcs.get("moonbit_malloc") {
    Some(f) => f
    None => raise CodegenError("moonbit_malloc not found")
  }
  
  let enum_ptr = self.builder.createCall(malloc_func, [size_val])
  
  // 设置标签
  let zero = self.llvm_ctx.getConstInt32(0)
  let tag_val = self.llvm_ctx.getConstInt32(variant.tag)
  let tag_ptr = self.builder.createGEP(enum_ptr, enum_type, [zero, zero])
  let _ = self.builder.createStore(tag_val, tag_ptr)
  
  // 设置字段值
  let mut i = 0
  while i < variant.params.length() {
    // 参数索引：0 是环境指针，1+ 是实际参数
    let param_val = match func.getArg(i + 1) {
      Some(arg) => (arg : &@llvm.Value)
      None => raise CodegenError("Missing parameter")
    }
    
    // 字段索引：0 是 tag，1+ 是数据字段
    let field_idx = self.llvm_ctx.getConstInt32(i + 1)
    let field_ptr = self.builder.createGEP(enum_ptr, enum_type, [zero, field_idx])
    
    // 根据参数类型进行转换并存储
    let param_ty = variant.params[i]
    match param_ty {
      @knf.Type::Int => {
        // Int (i32) -> i64
        let i64_val = self.builder.createSExt(param_val, self.llvm_ctx.getInt64Ty())
        let _ = self.builder.createStore(i64_val, field_ptr)
      }
      @knf.Type::Bool => {
        // Bool (i1) -> i64
        let i64_val = self.builder.createZExt(param_val, self.llvm_ctx.getInt64Ty())
        let _ = self.builder.createStore(i64_val, field_ptr)
      }
      @knf.Type::Double => {
        // Double -> i64 (bitcast)
        let i64_val = self.builder.createBitCast(param_val, self.llvm_ctx.getInt64Ty())
        let _ = self.builder.createStore(i64_val, field_ptr)
      }
      _ => {
        // 其他类型（指针等）-> i64
        let i64_val = self.builder.createPtrToInt(param_val, self.llvm_ctx.getInt64Ty())
        let _ = self.builder.createStore(i64_val, field_ptr)
      }
    }
    
    i = i + 1
  }
  
  // 返回枚举指针
  let _ = self.builder.createRet(enum_ptr)
}

///| 生成枚举字段访问
///
/// 从枚举值中提取指定字段，并转换为正确的类型
pub fn Context::enum_field_access(
  self : Context,
  enum_name : @knf.Name,
  field_index : Int,
  target_type : @knf.Type,
) -> &@llvm.Value raise {
  let enum_value = self.resolve_value(enum_name)
  
  // 获取枚举类型
  let enum_ty = match self.name_types.get(enum_name) {
    Some(@knf.Type::Enum(name)) => {
      match self.enum_types.get(name) {
        Some(ty) => ty
        None => raise CodegenError("Enum type not found: " + name)
      }
    }
    _ => raise CodegenError("Field access on non-enum type")
  }
  
  // 使用 GEP 获取字段指针
  // 字段索引：0 是 tag，1+ 是数据字段
  let zero = self.llvm_ctx.getConstInt32(0)
  let field_idx = self.llvm_ctx.getConstInt32(field_index + 1)
  let field_ptr = self.builder.createGEP(enum_value, enum_ty, [zero, field_idx])
  
  // 加载字段值（i64）
  let i64_val = self.builder.createLoad(self.llvm_ctx.getInt64Ty(), field_ptr)
  
  // 根据目标类型进行转换
  match target_type {
    @knf.Type::Int => {
      // i64 -> i32
      self.builder.createTrunc(i64_val, self.llvm_ctx.getInt32Ty())
    }
    @knf.Type::Bool => {
      // i64 -> i1
      self.builder.createTrunc(i64_val, self.llvm_ctx.getInt1Ty())
    }
    @knf.Type::Double => {
      // i64 -> Double (bitcast)
      self.builder.createBitCast(i64_val, self.llvm_ctx.getDoubleTy())
    }
    @knf.Type::Enum(_) | @knf.Type::Struct(_) | @knf.Type::Array(_) | @knf.Type::Function(_, _) => {
      // i64 -> 指针 (for enums, structs, arrays, functions)
      self.builder.createIntToPtr(i64_val)
    }
    _ => {
      // 其他类型也转换为指针
      self.builder.createIntToPtr(i64_val)
    }
  }
}

///| 生成枚举标签访问
///
/// 从枚举值中获取标签
pub fn Context::enum_tag_access(
  self : Context,
  enum_name : @knf.Name,
) -> &@llvm.Value raise {
  let enum_value = self.resolve_value(enum_name)
  
  // 获取枚举类型
  let enum_ty = match self.name_types.get(enum_name) {
    Some(@knf.Type::Enum(name)) => {
      match self.enum_types.get(name) {
        Some(ty) => ty
        None => raise CodegenError("Enum type not found: " + name)
      }
    }
    _ => raise CodegenError("Tag access on non-enum type")
  }
  
  // 使用 GEP 获取 tag 字段指针
  let zero = self.llvm_ctx.getConstInt32(0)
  let tag_ptr = self.builder.createGEP(enum_value, enum_ty, [zero, zero])
  
  // 加载 tag 值
  let tag_val = self.builder.createLoad(self.llvm_ctx.getInt32Ty(), tag_ptr)
  tag_val
}

///| 查找构造器的标签值
pub fn Context::find_constructor_tag(
  self : Context,
  constructor_name : String
) -> Int? {
  // 遍历所有枚举定义，查找匹配的构造器
  for enum_name, knf_enum in self.knf_enum_types {
    let mut i = 0
    while i < knf_enum.variants.length() {
      let variant = knf_enum.variants[i]
      if variant.name == constructor_name {
        return Some(variant.tag)
      }
      i = i + 1
    }
  }
  None
}
