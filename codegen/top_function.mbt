///|
/// 顶层函数代码生成
/// 
/// 为 KNF 函数生成完整的 LLVM IR 代码，包括：
/// 1. 创建函数入口基本块
/// 2. 设置函数参数
/// 3. 生成函数体
/// 4. 添加返回指令
/// 
/// 注意：main 函数和其他函数的处理略有不同
/// - main 函数：第一个参数是 argc (i32)，不需要环境指针
/// - 其他函数：第一个参数是环境指针 (ptr)，用于支持闭包
pub fn Context::top_function_codegen(
  self : Self,
  func : @knf.KnfFunction,
) -> @llvm.Function raise {
  // 获取之前在 collect_func_values 中创建的函数声明
  let llvm_func = match self.functions.get(func.name) {
    Some(f) => f
    None => raise CodegenError("Function not collected: " + func.name)
  }

  // 清空变量映射，准备生成新函数
  self.name_values.clear()
  self.name_types.clear()
  self.mutable_names.clear()
  
  // 恢复全局变量（顶层 let 绑定）
  for name, value in self.global_values {
    self.name_values.set(name, value)
  }
  for name, ty in self.global_types {
    self.name_types.set(name, ty)
  }

  // 创建函数入口基本块
  let entry_bb = llvm_func.addBasicBlock(name="entry")
  self.builder.setInsertPoint(entry_bb)

  // 设置函数参数
  // 注意：参数索引从 1 开始，因为索引 0 是环境指针（或 main 的 argc）
  let mut i = 0
  while i < func.params.length() {
    let (param_name, param_ty) = func.params[i]
    let llvm_arg = llvm_func.getArg(i + 1).unwrap()  // +1 跳过第一个参数
    self.name_values.set(param_name, llvm_arg)
    self.name_types.set(param_name, param_ty)
    i = i + 1
  }

  // 生成函数体
  if func.body.stmts.length() > 0 {
    let stmt_count = func.body.stmts.length()
    
    // 生成除最后一条语句外的所有语句
    if stmt_count > 1 {
      let mut j = 0
      while j < stmt_count - 1 {
        let stmt = func.body.stmts[j]
        self.stmt_codegen(stmt)
        j = j + 1
      }
    }

    // 特殊处理最后一条语句（可能需要生成返回指令）
    let last_stmt = func.body.stmts[stmt_count - 1]
    match last_stmt {
      @knf.KnfStmt::Return(_) => 
        // 显式 return 语句，直接生成
        self.stmt_codegen(last_stmt)
      @knf.KnfStmt::ReturnUnit => 
        // 显式 return unit 语句
        self.stmt_codegen(last_stmt)
      @knf.KnfStmt::ExprStmt(expr) => {
        // 表达式语句作为尾部表达式
        match func.ret_ty {
          @knf.Type::Unit => {
            // 函数返回 Unit，执行表达式但不返回值
            let _ = self.expr_codegen(expr)
            // 检查是否已有终结指令
            let current_bb = self.builder.getInsertBlock()
            match current_bb.getTerminator() {
              Some(_) => ()  // 已有终结指令
              None => { let _ = self.builder.createRetVoid() }
            }
          }
          _ => {
            // 函数返回非 Unit，表达式的值作为返回值
            match self.expr_codegen(expr) {
              Some(value) => { 
                // 检查是否已有终结指令
                let current_bb = self.builder.getInsertBlock()
                match current_bb.getTerminator() {
                  Some(_) => ()  // 已有终结指令
                  None => { let _ = self.builder.createRet(value) }
                }
              }
              None => {
                // 表达式没有产生值，检查是否已有终结指令
                let current_bb = self.builder.getInsertBlock()
                match current_bb.getTerminator() {
                  Some(_) => ()  // 已有终结指令（如 if 表达式）
                  None => raise CodegenError("Tail expression does not produce a value in function: " + func.name)
                }
              }
            }
          }
        }
      }
      stmt => {
        // 其他类型的语句
        self.stmt_codegen(stmt)
        
        // 检查当前块是否已有终止指令
        let current_bb = self.builder.getInsertBlock()
        match current_bb.getTerminator() {
          Some(_) => ()  // 已有终止指令，不需要添加
          None => {
            // 没有终止指令，根据返回类型添加
            match func.ret_ty {
              @knf.Type::Unit => {
                let _ = self.builder.createRetVoid()
              }
              _ => raise CodegenError("Function missing return for non-unit type: " + func.name)
            }
          }
        }
      }
    }
  } else {
    // 函数体为空
    match func.ret_ty {
      @knf.Type::Unit => {
        let _ = self.builder.createRetVoid()
      }
      _ => raise CodegenError("Non-unit function body missing return")
    }
  }

  llvm_func
}
