/// 代码生成错误类型
pub(all) suberror CodegenError String derive(Show)

/// 代码生成上下文
/// 
/// 维护代码生成过程中需要的所有状态信息，包括：
/// - LLVM 上下文和模块
/// - IR 构建器
/// - 类型映射（结构体类型）
/// - 函数映射
/// - 变量映射（名字到值的映射）
/// - 内建函数
pub struct Context {
  llvm_ctx : @llvm.Context                          // LLVM 上下文
  llvm_mod : @llvm.Module                           // LLVM 模块
  builder : @llvm.IRBuilder                         // IR 构建器
  mut str_cnt : Int                                 // 字符串常量计数器
  struct_types : Map[String, @llvm.StructType]     // 结构体类型映射
  knf_struct_types : Map[String, @knf.KnfStructDef] // KNF 结构体定义
  enum_types : Map[String, @llvm.StructType]       // 枚举类型映射
  knf_enum_types : Map[String, @knf.KnfEnumDef]    // KNF 枚举定义
  functions : Map[String, @llvm.Function]           // 函数映射

  // 当前作用域的变量映射（在生成函数体时会修改）
  name_values : Map[@knf.Name, &@llvm.Value]       // 名字到 LLVM 值的映射
  name_types : Map[@knf.Name, @knf.Type]           // 名字到类型的映射
  mutable_names : @hashset.T[@knf.Name]            // 可变变量集合（用于检查赋值）
  builtin_funcs : Map[String, @llvm.Function]      // 内建函数映射
  
  // 全局变量（顶层 let 绑定）
  global_values : Map[@knf.Name, &@llvm.Value]     // 全局变量的值
  global_types : Map[@knf.Name, @knf.Type]         // 全局变量的类型
  
  // 当前闭包的环境指针（用于递归调用）
  mut current_closure_env : Option[&@llvm.Value]   // 当前闭包的环境指针
  mut current_closure_func : Option[@llvm.Function] // 当前闭包函数
}

/// 获取元组元素的指针和类型
/// 
/// 用于元组访问表达式的代码生成
/// 
/// 参数：
/// - tuple_name: 元组变量的名字
/// - index: 要访问的元素索引
/// 
/// 返回：(元素指针, 元素类型)
/// 
/// 异常：如果索引越界或类型不匹配，抛出 CodegenError
pub fn Context::tuple_element_ptr_and_type(
  self : Self,
  tuple_name : @knf.Name,
  index : Int,
) -> (&@llvm.Value, @knf.Type) raise {
  // 解析元组值
  let tuple_value = self.resolve_value(tuple_name)
  
  // 获取元组类型
  let tuple_ty = match self.name_types.get(tuple_name) {
    Some(ty) => ty
    None => raise CodegenError("Missing type information for tuple: " + tuple_name.to_string())
  }
  
  // 提取元素类型列表
  let elem_types = match tuple_ty {
    @knf.Type::Tuple(types) => types
    _ => raise CodegenError("Tuple access on non-tuple type")
  }
  
  // 检查索引是否越界
  guard index >= 0 && index < elem_types.length() else {
    raise CodegenError("Tuple index out of bounds")
  }
  
  // 构建 LLVM 元组类型（结构体）
  let llvm_elem_types = elem_types.map(elem_ty => self.type_codegen_concrete(elem_ty))
  let llvm_tuple_ty = self.llvm_ctx.getStructType(llvm_elem_types)
  
  // 使用 GEP 获取元素指针
  let zero = self.llvm_ctx.getConstInt32(0)
  let idx_val = self.llvm_ctx.getConstInt32(index)
  let elem_ptr = self.builder.createGEP(tuple_value, llvm_tuple_ty, [zero, idx_val])
  
  let elem_ty = elem_types[index]
  (elem_ptr, elem_ty)
}

/// 创建新的代码生成上下文
/// 
/// 参数：
/// - mod_name: LLVM 模块的名字
/// 
/// 返回：初始化好的代码生成上下文
pub fn Context::new(mod_name : String) -> Context {
  let llvm_ctx = @llvm.Context::new()
  let llvm_mod = llvm_ctx.addModule(mod_name)
  let builder = llvm_ctx.createBuilder()
  let i32ty = llvm_ctx.getInt32Ty()
  let doublety = llvm_ctx.getDoubleTy()
  let boolty = llvm_ctx.getInt1Ty()
  let ptrty = llvm_ctx.getPtrTy()
  let voidty = llvm_ctx.getVoidTy()
  
  // Helper function to add prefix for evaluation platform
  // Set to true for submission, false for local testing
  let use_minimbt_prefix = true  // CHANGE THIS TO true FOR SUBMISSION
  fn builtin_name(name : String) -> String {
    if use_minimbt_prefix {
      "minimbt_" + name
    } else {
      name
    }
  }
  
  let moonbit_malloc_ty = try! llvm_ctx.getFunctionType(ptrty, [i32ty])
  let moonbit_malloc = try! llvm_mod.addFunction(
      moonbit_malloc_ty, builtin_name("malloc"),
    )
  let print_int_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [i32ty])
  let print_int = try! llvm_mod.addFunction(print_int_ty, builtin_name("print_int"))
  let println_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [i32ty])
  let println = try! llvm_mod.addFunction(println_ty, builtin_name("println"))
  let print_double_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [
      doublety,
    ])
  let print_double = try! llvm_mod.addFunction(print_double_ty, builtin_name("print_double"))
  let print_bool_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [
      boolty,
    ])
  let print_bool = try! llvm_mod.addFunction(print_bool_ty, builtin_name("print_bool"))
  
  // I/O functions
  let read_int_ty = try! llvm_ctx.getFunctionType(i32ty, [])
  let read_int = try! llvm_mod.addFunction(read_int_ty, builtin_name("read_int"))
  let read_char_ty = try! llvm_ctx.getFunctionType(i32ty, [])
  let read_char = try! llvm_mod.addFunction(read_char_ty, builtin_name("read_char"))
  let print_char_ty = try! llvm_ctx.getFunctionType(voidty, [i32ty])
  let print_char = try! llvm_mod.addFunction(print_char_ty, builtin_name("print_char"))
  let print_endline_ty = try! llvm_ctx.getFunctionType(voidty, [])
  let print_endline = try! llvm_mod.addFunction(print_endline_ty, builtin_name("print_endline"))
  
  // Math functions
  let int_of_float_ty = try! llvm_ctx.getFunctionType(i32ty, [doublety])
  let int_of_float = try! llvm_mod.addFunction(int_of_float_ty, builtin_name("int_of_float"))
  let float_of_int_ty = try! llvm_ctx.getFunctionType(doublety, [i32ty])
  let float_of_int = try! llvm_mod.addFunction(float_of_int_ty, builtin_name("float_of_int"))
  let truncate_ty = try! llvm_ctx.getFunctionType(i32ty, [doublety])
  let truncate = try! llvm_mod.addFunction(truncate_ty, builtin_name("truncate"))
  let floor_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let floor = try! llvm_mod.addFunction(floor_ty, builtin_name("floor"))
  let abs_float_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let abs_float = try! llvm_mod.addFunction(abs_float_ty, builtin_name("abs_float"))
  let sqrt_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let sqrt = try! llvm_mod.addFunction(sqrt_ty, builtin_name("sqrt"))
  let sin_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let sin = try! llvm_mod.addFunction(sin_ty, builtin_name("sin"))
  let cos_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let cos = try! llvm_mod.addFunction(cos_ty, builtin_name("cos"))
  let atan_ty = try! llvm_ctx.getFunctionType(doublety, [doublety])
  let atan = try! llvm_mod.addFunction(atan_ty, builtin_name("atan"))
  
  let make_int_array_ty = try! llvm_ctx.getFunctionType(ptrty, [i32ty, i32ty])
  let make_double_array_ty = try! llvm_ctx.getFunctionType(ptrty, [
      i32ty, doublety,
    ])
  let _make_bool_array_ty = try! llvm_ctx.getFunctionType(ptrty, [i32ty, i32ty])  // Use i32 for bool to match runtime
  let make_ptr_array_ty = try! llvm_ctx.getFunctionType(ptrty, [i32ty, ptrty])
  let get_array_length_ty = try! llvm_ctx.getFunctionType(i32ty, [ptrty])
  let array_int_push_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [
      ptrty, i32ty,
    ])
  let array_double_push_ty = try! llvm_ctx.getFunctionType(
      llvm_ctx.getVoidTy(),
      [ptrty, doublety],
    )
  let array_bool_push_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [
      ptrty, boolty,
    ])
  let array_ptr_push_ty = try! llvm_ctx.getFunctionType(llvm_ctx.getVoidTy(), [
      ptrty, ptrty,
    ])
  let array_int_get_ty = try! llvm_ctx.getFunctionType(i32ty, [ptrty, i32ty])
  let array_double_get_ty = try! llvm_ctx.getFunctionType(doublety, [
      ptrty, i32ty,
    ])
  let array_bool_get_ty = try! llvm_ctx.getFunctionType(boolty, [ptrty, i32ty])
  let array_ptr_get_ty = try! llvm_ctx.getFunctionType(ptrty, [ptrty, i32ty])
  let array_int_put_ty = try! llvm_ctx.getFunctionType(voidty, [
      ptrty, i32ty, i32ty,
    ])
  let array_double_put_ty = try! llvm_ctx.getFunctionType(voidty, [
      ptrty, i32ty, doublety,
    ])
  let array_bool_put_ty = try! llvm_ctx.getFunctionType(voidty, [
      ptrty, i32ty, boolty,
    ])
  let array_ptr_put_ty = try! llvm_ctx.getFunctionType(voidty, [
      ptrty, i32ty, ptrty,
    ])
  // Declare create_array once for both int and bool arrays (same signature)
  let create_array_fn = try! llvm_mod.addFunction(
      make_int_array_ty, builtin_name("create_array"),
    )
  let make_int_array = create_array_fn
  let make_bool_array = create_array_fn  // Reuse the same function
  
  let make_double_array = try! llvm_mod.addFunction(
      make_double_array_ty, builtin_name("create_float_array"),
    )
  let make_ptr_array = try! llvm_mod.addFunction(
      make_ptr_array_ty, builtin_name("create_ptr_array"),
    )
  let get_array_length = try! llvm_mod.addFunction(
      get_array_length_ty, builtin_name("get_array_length"),
    )
  let array_int_push = try! llvm_mod.addFunction(
      array_int_push_ty, builtin_name("array_int_push"),
    )
  let array_double_push = try! llvm_mod.addFunction(
      array_double_push_ty, builtin_name("array_double_push"),
    )
  let array_bool_push = try! llvm_mod.addFunction(
      array_bool_push_ty, builtin_name("array_bool_push"),
    )
  let array_ptr_push = try! llvm_mod.addFunction(
      array_ptr_push_ty, builtin_name("array_ptr_push"),
    )
  let array_int_get = try! llvm_mod.addFunction(
      array_int_get_ty, builtin_name("array_int_get"),
    )
  let array_double_get = try! llvm_mod.addFunction(
      array_double_get_ty, builtin_name("array_double_get"),
    )
  let array_bool_get = try! llvm_mod.addFunction(
      array_bool_get_ty, builtin_name("array_bool_get"),
    )
  let array_ptr_get = try! llvm_mod.addFunction(
      array_ptr_get_ty, builtin_name("array_ptr_get"),
    )
  let array_int_put = try! llvm_mod.addFunction(
      array_int_put_ty, builtin_name("array_int_put"),
    )
  let array_double_put = try! llvm_mod.addFunction(
      array_double_put_ty, builtin_name("array_double_put"),
    )
  let array_bool_put = try! llvm_mod.addFunction(
      array_bool_put_ty, builtin_name("array_bool_put"),
    )
  let array_ptr_put = try! llvm_mod.addFunction(
      array_ptr_put_ty, builtin_name("array_ptr_put"),
    )
  let builtin_funcs = {
    "moonbit_malloc": moonbit_malloc,
    "print_int": print_int,
    "println": println,
    "print_double": print_double,
    "print_bool": print_bool,
    "read_int": read_int,
    "read_char": read_char,
    "print_char": print_char,
    "print_endline": print_endline,
    "int_of_float": int_of_float,
    "float_of_int": float_of_int,
    "truncate": truncate,
    "floor": floor,
    "abs_float": abs_float,
    "sqrt": sqrt,
    "sin": sin,
    "cos": cos,
    "atan": atan,
    "make_int_array": make_int_array,
    "make_double_array": make_double_array,
    "make_bool_array": make_bool_array,
    "make_ptr_array": make_ptr_array,
    "get_array_length": get_array_length,
    "array_int_push": array_int_push,
    "array_double_push": array_double_push,
    "array_bool_push": array_bool_push,
    "array_ptr_push": array_ptr_push,
    "array_int_get": array_int_get,
    "array_double_get": array_double_get,
    "array_bool_get": array_bool_get,
    "array_ptr_get": array_ptr_get,
    "array_int_put": array_int_put,
    "array_double_put": array_double_put,
    "array_bool_put": array_bool_put,
    "array_ptr_put": array_ptr_put,
  }
  let ctx = Context::{
    llvm_ctx,
    llvm_mod,
    builder,
    str_cnt: 0,
    struct_types: Map::new(),
    knf_struct_types: Map::new(),
    enum_types: Map::new(),
    knf_enum_types: Map::new(),
    functions: Map::new(),
    name_values: Map::new(),
    name_types: Map::new(),
    mutable_names: @hashset.new(),
    builtin_funcs,
    global_values: Map::new(),
    global_types: Map::new(),
    current_closure_env: None,
    current_closure_func: None,
  }
  ctx.str_cnt += 1
  ctx
}

///| Check if a function name is an enum constructor
fn Context::is_enum_constructor(self : Context, name : String) -> Bool {
  // Check all enum types to see if this name is a variant
  for _enum_name, knf_enum in self.knf_enum_types {
    for variant in knf_enum.variants {
      if variant.name == name {
        return true
      }
    }
  }
  false
}

///| Create a wrapper function for a regular function to be used as a closure
///
/// This creates:
/// 1. A wrapper function that takes (ptr env, ...args) and calls the original function with (...args)
/// 2. A closure struct containing the wrapper function pointer
///
/// Returns: The closure struct pointer
fn Context::create_function_wrapper(
  self : Context,
  original_func : @llvm.Function,
  func_name : String
) -> &@llvm.Value raise {
  let ptr_ty = self.llvm_ctx.getPtrTy()
  
  // Get original function type
  let orig_func_ty = original_func.getFunctionType()
  let orig_param_types = orig_func_ty.getParamTypes()
  let orig_return_ty = orig_func_ty.getReturnType()
  
  // Check if this is a builtin function (doesn't have env pointer as first param)
  // Builtin functions don't have env pointer, so we don't skip the first parameter
  let is_builtin = func_name.starts_with("make_") || func_name.starts_with("array_") || 
                   func_name.starts_with("get_") || func_name == "moonbit_malloc" ||
                   func_name == "read_int" || func_name == "print_int" || 
                   func_name == "read_char" || func_name == "print_char" ||
                   func_name == "print_endline" || func_name == "int_of_float" ||
                   func_name == "float_of_int" || func_name == "truncate" ||
                   func_name == "floor" || func_name == "abs_float" ||
                   func_name == "sqrt" || func_name == "sin" || func_name == "cos" || func_name == "atan"
  
  // Create wrapper function type: (ptr wrapper_env, ...actual_params) -> original return
  // For user functions: Original has (ptr orig_env, ...params), wrapper has (ptr wrapper_env, ...params)
  // For builtin functions: Original has (...params), wrapper has (ptr wrapper_env, ...params)
  let wrapper_param_types : Array[&@llvm.Type] = [(ptr_ty : &@llvm.Type)]
  let param_start_index = if is_builtin { 0 } else { 1 }  // Skip env for user functions only
  let mut i = param_start_index
  while i < orig_param_types.length() {
    wrapper_param_types.push(orig_param_types[i])
    i = i + 1
  }
  let wrapper_func_ty = try! self.llvm_ctx.getFunctionType(orig_return_ty, wrapper_param_types)
  
  // Create wrapper function with a unique name
  let wrapper_name = "wrapper_" + func_name
  let wrapper_func = try! self.llvm_mod.addFunction(wrapper_func_ty, wrapper_name)
  
  // Save current insert point
  let saved_bb = self.builder.getInsertBlock()
  
  // Generate wrapper function body
  let entry_bb = wrapper_func.addBasicBlock()
  self.builder.setInsertPoint(entry_bb)
  
  // Prepare call arguments for original function
  // For user functions:
  //   Wrapper signature: (ptr wrapper_env, param1, param2, ...)
  //   Original signature: (ptr orig_env, param1, param2, ...)
  //   Call: original(null, param1, param2, ...)
  // For builtin functions:
  //   Wrapper signature: (ptr wrapper_env, param1, param2, ...)
  //   Original signature: (param1, param2, ...)
  //   Call: original(param1, param2, ...)
  let call_args : Array[&@llvm.Value] = []
  
  if !is_builtin {
    // For user functions: add null env pointer as first argument
    let null_ptr = self.llvm_ctx.getConstPointerNull(ptr_ty)
    call_args.push(null_ptr)
  }
  
  // Forward remaining arguments from wrapper (starting at index 1, skipping wrapper env)
  let mut i = 1  // Start from index 1 (skip wrapper env at 0)
  let param_count = wrapper_param_types.length()  // This includes wrapper env
  while i < param_count {
    match wrapper_func.getArg(i) {
      Some(arg) => call_args.push(arg)
      None => raise CodegenError("Missing wrapper parameter at index \{i}")
    }
    i = i + 1
  }
  
  // Call original function with forwarded arguments
  match orig_return_ty.asTypeEnum() {
    @llvm.TypeEnum::VoidType(_) => {
      let _ = self.builder.createCall(original_func, call_args)
      let _ = self.builder.createRetVoid()
    }
    _ => {
      let result = self.builder.createCall(original_func, call_args)
      let _ = self.builder.createRet(result)
    }
  }
  
  // Restore insert point
  self.builder.setInsertPoint(saved_bb)
  
  // Create closure struct: { wrapper_func_ptr }
  let closure_struct_ty = self.llvm_ctx.getStructType([ptr_ty])
  
  // Allocate closure struct
  let data_layout = self.llvm_mod.getDataLayout()
  let closure_size = data_layout.getTypeAllocSize(closure_struct_ty)
  let closure_size_val = self.llvm_ctx.getConstInt32(closure_size)
  
  let malloc_func = match self.builtin_funcs.get("moonbit_malloc") {
    Some(f) => f
    None => raise CodegenError("moonbit_malloc not found")
  }
  
  let closure_ptr = self.builder.createCall(malloc_func, [closure_size_val])
  
  // Store wrapper function pointer in closure struct
  let zero = self.llvm_ctx.getConstInt32(0)
  let func_ptr_field = self.builder.createGEP(closure_ptr, closure_struct_ty, [zero, zero])
  let _ = self.builder.createStore((wrapper_func : &@llvm.Value), func_ptr_field)
  
  (closure_ptr : &@llvm.Value)
}

///|
pub fn Context::resolve_value(
  self : Self,
  name : @knf.Name,
) -> &@llvm.Value raise {
  match self.name_values.get(name) {
    Some(value) =>
      match value.asValueEnum() {
        @llvm.ValueEnum::AllocaInst(_) => {
          // 对于局部变量，我们需要返回加载的值
          // 对于写入，assign_stmt_codegen会直接从name_values获取指针
          let knf_ty = match self.name_types.get(name) {
            Some(t) => t
            None =>
              raise CodegenError(
                "Missing type information for " + name.to_string(),
              )
          }
          let llvm_ty = self.type_codegen_opaque(knf_ty)
          self.builder.createLoad(llvm_ty, value)
        }
        _ => {
          // 检查是否是可变变量（从闭包捕获的指针）
          // 对于可变变量，我们需要返回加载的值，就像普通变量一样
          // 对于写入，我们需要特殊处理
          if self.mutable_names.contains(name) {
            // 可变变量：需要加载指针指向的值
            let knf_ty = match self.name_types.get(name) {
              Some(t) => t
              None =>
                raise CodegenError(
                  "Missing type information for " + name.to_string(),
                )
            }
            let llvm_ty = self.type_codegen_opaque(knf_ty)
            self.builder.createLoad(llvm_ty, value)
          } else {
            // 不可变变量或其他值：直接使用
            value
          }
        }
      }
    None => {
      // Try to find in top-level functions
      let name_str = name.to_string()
      match self.functions.get(name_str) {
        Some(func) => {
          // Check if this is an enum constructor
          // Enum constructors should NOT be wrapped in closure structures
          let is_enum_constructor = self.is_enum_constructor(name_str)
          
          if is_enum_constructor {
            // Enum constructor - return the function directly without wrapping
            (func : &@llvm.Value)
          } else {
            // This is a top-level function being used as a value
            // We need to create a wrapper function and closure structure
            self.create_function_wrapper(func, name_str)
          }
        }
        None => {
          // Try to find in builtin functions
          match self.builtin_funcs.get(name_str) {
            Some(func) => {
              // This is a builtin function being used as a value
              // Create a wrapper function and closure structure
              self.create_function_wrapper(func, name_str)
            }
            None => raise CodegenError("Unknown identifier: " + name.to_string())
          }
        }
      }
    }
  }
}

///|
pub fn Context::struct_field_ptr_and_type(
  self : Self,
  struct_name : @knf.Name,
  field_name : String,
) -> (&@llvm.Value, @knf.Type) raise {
  let struct_value = self.resolve_value(struct_name)
  let struct_ty = match self.name_types.get(struct_name) {
    Some(ty) => ty
    None =>
      raise CodegenError(
        "Missing type information for struct: " + struct_name.to_string(),
      )
  }
  let struct_name_str = match struct_ty {
    @knf.Type::Struct(name) => name
    _ => raise CodegenError("Field access on non-struct type")
  }
  let llvm_struct_ty = match self.struct_types.get(struct_name_str) {
    Some(ty) => ty
    None => raise CodegenError("Unknown struct type: " + struct_name_str)
  }
  let knf_struct = match self.knf_struct_types.get(struct_name_str) {
    Some(def) => def
    None =>
      raise CodegenError(
        "Missing KNF struct definition for: " + struct_name_str,
      )
  }
  let field_idx = match knf_struct.get_field_index(field_name) {
    Some(i) => i
    None =>
      raise CodegenError(
        "Unknown field " + field_name + " in struct " + struct_name_str,
      )
  }
  let zero = self.llvm_ctx.getConstInt32(0)
  let idx_val = self.llvm_ctx.getConstInt32(field_idx)
  let field_ptr = self.builder.createGEP(struct_value, llvm_struct_ty, [
    zero, idx_val,
  ])
  let (_, _, field_ty) = knf_struct.fields[field_idx]
  (field_ptr, field_ty)
}
