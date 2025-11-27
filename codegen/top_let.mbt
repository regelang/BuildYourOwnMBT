///|
/// 顶层 let 绑定代码生成
/// 
/// 将顶层 let 绑定注册为常量值
/// 
/// 参数：
/// - top_let: KNF 形式的顶层 let 绑定
/// 
/// 异常：如果代码生成失败，抛出 CodegenError
pub fn Context::top_let_codegen(
  self : Self,
  top_let : @knf.KnfTopLet,
) -> Unit raise {
  // 获取初始化表达式的值
  // 对于顶层 let，表达式必须是常量
  let init_value = match top_let.expr {
    @knf.KnfExpr::Int(i) => (self.llvm_ctx.getConstInt32(i) : &@llvm.Value)
    @knf.KnfExpr::Double(d) => (self.llvm_ctx.getConstDouble(d) : &@llvm.Value)
    @knf.KnfExpr::Bool(b) => {
      let val = if b { self.llvm_ctx.getConstTrue() } else { self.llvm_ctx.getConstFalse() }
      (val : &@llvm.Value)
    }
    @knf.KnfExpr::Unit => {
      // Unit type: use a dummy i8 value
      (self.llvm_ctx.getConstInt8(0) : &@llvm.Value)
    }
    _ => raise CodegenError("Top-level let initializer must be a constant expression")
  }
  
  // 注册到全局变量存储中
  self.global_values.set(top_let.name, init_value)
  self.global_types.set(top_let.name, top_let.ty)
}
