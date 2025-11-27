/// LLVM IR 代码生成入口函数
/// 
/// 将 KNF 形式的程序转换为 LLVM IR 代码
/// 
/// 代码生成过程分为三个阶段：
/// 1. 收集结构体类型定义
/// 2. 收集函数声明（创建函数签名）
/// 3. 生成函数体的 IR 代码
/// 
/// 参数：
/// - knf_prog: KNF 形式的程序
/// 
/// 返回：生成的 LLVM Module，包含完整的 IR 代码
/// 
/// 异常：如果代码生成失败，抛出 CodegenError
pub fn codegen(knf_prog : @knf.KnfProgram) -> @llvm.Module raise {
  // 创建代码生成上下文
  let codegen_ctx = Context::new("module")

  // 阶段 1：收集所有结构体类型定义
  // 这样在生成代码时可以引用这些类型
  codegen_ctx.collect_struct_types(knf_prog.struct_defs)
  
  // 收集所有枚举类型定义
  codegen_ctx.collect_enum_types(knf_prog.enum_defs)
  
  // 阶段 2：收集所有函数声明
  // 创建函数签名，使函数之间可以相互调用
  codegen_ctx.collect_func_values(knf_prog.functions)

  // 阶段 2.5：生成枚举构造器函数
  codegen_ctx.generate_enum_constructors(knf_prog.enum_defs)

  // 阶段 2.6：生成顶层 let 绑定（全局变量）
  for _, top_let in knf_prog.top_lets {
    codegen_ctx.top_let_codegen(top_let)
  }

  // 阶段 3：为每个函数生成完整的 IR 代码
  for _, func in knf_prog.functions {
    let _ = codegen_ctx.top_function_codegen(func)
  }

  // 返回生成的 LLVM Module
  codegen_ctx.llvm_mod
}
