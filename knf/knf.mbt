/// KNF 程序结构体
/// 
/// KNF (Kernel Normal Form) 是一种中间表示形式，特点：
/// - 所有复杂表达式都被分解为简单的原子操作
/// - 每个中间结果都有一个唯一的名字
/// - 控制流结构被简化
/// 
/// 这种形式便于后续的代码生成和优化
pub(all) struct KnfProgram {
  struct_defs : Map[String, KnfStructDef]  // 结构体定义
  enum_defs : Map[String, KnfEnumDef]      // 枚举定义
  top_lets : Map[String, KnfTopLet]        // 顶层 let 绑定
  functions : Map[String, KnfFunction]     // 函数定义
}

/// 将类型检查后的程序转换为 KNF 形式
/// 
/// 转换过程分为三个阶段：
/// 1. 转换结构体定义（其他部分可能依赖它们）
/// 2. 转换顶层 let 绑定（函数可能引用它们）
/// 3. 转换函数定义
/// 
/// 参数：
/// - prog: 类型检查后的程序
/// 
/// 返回：KNF 形式的程序
/// 
/// 异常：如果转换失败，抛出 KnfTransformError
pub fn Context::program_to_knf(
  self : Context,
  prog : @typecheck.Program,
) -> KnfProgram raise KnfTransformError {
  // 阶段 1：首先转换结构体定义，因为后续步骤可能依赖它们
  let struct_entries = prog.struct_defs.to_array()
  let knf_struct_defs : Map[String, KnfStructDef] = Map::new()
  let mut si = 0
  while si < struct_entries.length() {
    let (struct_name, struct_def) = struct_entries[si]
    let knf_struct = self.struct_def_to_knf(struct_def)
    knf_struct_defs.set(struct_name, knf_struct)
    si = si + 1
  }

  // 转换枚举定义
  let enum_entries = prog.enum_defs.to_array()
  let knf_enum_defs : Map[String, KnfEnumDef] = Map::new()
  let mut ei = 0
  while ei < enum_entries.length() {
    let (enum_name, enum_def) = enum_entries[ei]
    let knf_enum = self.enum_def_to_knf(enum_def)
    knf_enum_defs.set(enum_name, knf_enum)
    ei = ei + 1
  }

  // 阶段 2：转换顶层 let 绑定，使函数可以引用它们
  let top_let_entries = prog.top_lets.to_array()
  let knf_top_lets : Map[String, KnfTopLet] = Map::new()
  let mut li = 0
  while li < top_let_entries.length() {
    let (let_name, top_let) = top_let_entries[li]
    let knf_top_let = self.top_let_to_knf(top_let)
    knf_top_lets.set(let_name, knf_top_let)
    li = li + 1
  }

  // 阶段 3：转换顶层函数
  // 首先收集泛型函数（从 typecheck 阶段传递过来）
  let func_entries = prog.top_functions.to_array()
  let knf_functions : Map[String, KnfFunction] = Map::new()
  
  // 第一遍：转换非泛型函数，收集泛型函数
  let mut fi = 0
  while fi < func_entries.length() {
    let (func_name, func) = func_entries[fi]
    // 检查是否是泛型函数（通过检查参数类型中是否有空结构体）
    let is_generic = self.is_generic_function(func)
    
    if is_generic {
      // 保存泛型函数定义，稍后单态化
      self.generic_functions.set(func_name, func)
    } else {
      // 直接转换非泛型函数
      let knf_func = self.top_function_to_knf(func)
      knf_functions.set(func_name, knf_func)
    }
    fi = fi + 1
  }
  
  // 第二遍：添加所有单态化的函数
  let mono_entries = self.monomorphized_functions.to_array()
  let mut mi = 0
  while mi < mono_entries.length() {
    let (mono_name, mono_func) = mono_entries[mi]
    knf_functions.set(mono_name, mono_func)
    mi = mi + 1
  }

  KnfProgram::{
    struct_defs: knf_struct_defs,
    enum_defs: knf_enum_defs,
    top_lets: knf_top_lets,
    functions: knf_functions
  }
}

///|
pub fn knf_transform(
  prog : @typecheck.Program,
) -> KnfProgram raise KnfTransformError {
  let context = Context::new()
  
  // 设置枚举定义，用于后续查找字段类型
  for enum_name, enum_def in prog.enum_defs {
    context.enum_defs.set(enum_name, enum_def)
  }
  
  // I/O functions
  context.globals.set("read_int", Function([], Int))
  context.globals.set("print_int", Function([Int], Unit))
  context.globals.set("read_char", Function([], Int))
  context.globals.set("print_char", Function([Int], Unit))
  context.globals.set("print_endline", Function([], Unit))
  // Math functions
  context.globals.set("int_of_float", Function([Double], Int))
  context.globals.set("float_of_int", Function([Int], Double))
  context.globals.set("truncate", Function([Double], Int))
  context.globals.set("floor", Function([Double], Double))
  context.globals.set("abs_float", Function([Double], Double))
  context.globals.set("sqrt", Function([Double], Double))
  context.globals.set("sin", Function([Double], Double))
  context.globals.set("cos", Function([Double], Double))
  context.globals.set("atan", Function([Double], Double))
  
  // Enum constructors: register each variant as a global function
  // so that bare enum variants (e.g. Red, RGB) are treated as
  // functions from their payload types to the enum type.
  for enum_name, enum_def in prog.enum_defs {
    let enum_ret_ty = Type::Enum(enum_name)
    for variant in enum_def.variants {
      let mut param_types : Array[Type] = []
      let mut i = 0
      while i < variant.params.length() {
        let tk = variant.params[i]
        let knf_ty = context.typekind_to_knf(tk)
        param_types = param_types + [knf_ty]
        i = i + 1
      }
      context.globals.set(variant.name, Function(param_types, enum_ret_ty))
    }
  }
  
  // Register all top-level functions as globals
  for func_name, func in prog.top_functions {
    let param_types = func.param_list.map(fn(p) { context.typekind_to_knf(p.ty) })
    let ret_type = context.typekind_to_knf(func.ret_ty)
    context.globals.set(func_name, Function(param_types, ret_type))
  }
  
  context.program_to_knf(prog)
}

///|
pub impl Show for KnfProgram with output(self, logger) {
  for _, struct_def in self.struct_defs {
    logger.write_object(struct_def)
    logger.write_char('\n')
  }
  for _, top_let in self.top_lets {
    logger.write_object(top_let)
    logger.write_char('\n')
  }
  for _, func in self.functions {
    logger.write_object(func)
    logger.write_char('\n')
  }
}
