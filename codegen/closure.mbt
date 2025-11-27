///|
/// 闭包代码生成
/// 
/// 闭包表示为堆上的结构体：
/// - 第一个字段：函数指针
/// - 后续字段：捕获的变量
/// 
/// 闭包代码生成分为两个步骤：
/// 1. 生成闭包函数本身（带环境指针参数）
/// 2. 在当前函数中创建闭包结构体实例
pub fn Context::closure_codegen(
  self : Context,
  closure_def : @knf.KnfClosure,
) -> Unit raise {
  let closure_name = closure_def.name.to_string()
  
  // ============================================================
  // 第一步：生成闭包函数本身
  // ============================================================
  // 闭包函数的特殊之处：第一个参数是环境指针（指向闭包结构体）
  // 函数签名：(ptr env, param1, param2, ...) -> ret_ty
  
  // 构建参数类型列表：第一个是环境指针
  let env_ptr_ty = self.llvm_ctx.getPtrTy()
  let param_types : Array[&@llvm.Type] = [env_ptr_ty]
  
  // 添加闭包的实际参数类型
  closure_def.params.each(param => {
    // Unit type cannot be a function parameter in LLVM, use i8 instead
    let llvm_param_ty : &@llvm.Type = match param.1 {
      @knf.Type::Unit => (self.llvm_ctx.getInt8Ty() : &@llvm.Type)
      _ => self.type_codegen_opaque(param.1)
    }
    param_types.push(llvm_param_ty)
  })
  
  // 创建函数类型和函数
  // Unit return type should be void, not i8
  let llvm_ret_ty : &@llvm.Type = match closure_def.ret_ty {
    @knf.Type::Unit => (self.llvm_ctx.getVoidTy() : &@llvm.Type)
    _ => self.type_codegen_opaque(closure_def.ret_ty)
  }
  let llvm_fn_ty = self.llvm_ctx.getFunctionType(llvm_ret_ty, param_types)
  let llvm_func = self.llvm_mod.addFunction(llvm_fn_ty, closure_name)
  
  // 保存当前上下文（因为我们要切换到闭包函数的作用域）
  // 保存当前的插入点、变量映射和类型映射
  let saved_insert_block = self.builder.getInsertBlock()
  let saved_name_values : Map[@knf.Name, &@llvm.Value] = Map::new()
  let saved_name_types : Map[@knf.Name, @knf.Type] = Map::new()
  let saved_mutable_names = @hashset.new()
  for name, value in self.name_values {
    saved_name_values.set(name, value)
  }
  for name, ty in self.name_types {
    saved_name_types.set(name, ty)
  }
  for name in self.mutable_names {
    saved_mutable_names.add(name)
  }
  
  // 清除当前作用域，准备生成闭包函数体
  self.name_values.clear()
  self.name_types.clear()
  self.mutable_names.clear()
  
  // 创建闭包函数的入口基本块
  let entry_bb = llvm_func.addBasicBlock(name="entry")
  self.builder.setInsertPoint(entry_bb)
  
  // 获取环境指针（闭包函数的第一个参数）
  // 这个指针指向闭包结构体，包含捕获的变量
  let env_ptr = llvm_func.getArg(0).unwrap()
  
  // 保存当前闭包的环境指针和函数（用于递归调用）
  let saved_closure_env = self.current_closure_env
  let saved_closure_func = self.current_closure_func
  self.current_closure_env = Some(env_ptr)
  self.current_closure_func = Some(llvm_func)
  
  // 从环境指针中加载捕获的变量
  // 闭包结构体布局：[函数指针, 捕获变量1, 捕获变量2, ...]
  let captured_entries = closure_def.captured_vars.to_array()
  
  // 构建闭包结构体类型（用于 GEP 指令）
  // 结构体类型必须与实际创建的结构体一致
  // 注意：可变变量字段类型是指针，不可变变量字段类型是值
  let struct_field_types : Array[&@llvm.Type] = Array::new()
  struct_field_types.push(self.llvm_ctx.getPtrTy())  // 第0个字段：函数指针
  for j = 0; j < captured_entries.length(); j = j + 1 {
    let (captured_name, captured_ty) = captured_entries[j]
    let field_ty : &@llvm.Type = if saved_mutable_names.contains(captured_name) {
      (self.llvm_ctx.getPtrTy() : &@llvm.Type)  // 可变变量：指针类型
    } else {
      self.type_codegen_opaque(captured_ty)  // 不可变变量：值类型
    }
    struct_field_types.push(field_ty)
  }
  let struct_ty = self.llvm_ctx.getStructType(struct_field_types)
  
  let zero = self.llvm_ctx.getConstInt32(0)
  let mut field_index = 1  // 第0个字段是函数指针，从1开始是捕获的变量
  
  for i = 0; i < captured_entries.length(); i = i + 1 {
    let (captured_name, captured_ty) = captured_entries[i]
    
    // 使用 GEP (GetElementPtr) 获取结构体字段地址
    let idx = self.llvm_ctx.getConstInt32(field_index)
    
    // GEP 指令：获取结构体中第 field_index 个字段的指针
    // getelementptr struct_ty, ptr env_ptr, i32 0, i32 field_index
    let field_ptr = self.builder.createGEP(env_ptr, struct_ty, [zero, idx])
    
    // 从字段指针加载值
    let llvm_ty = self.type_codegen_opaque(captured_ty)
    
    // 如果捕获的变量在外层作用域中是可变的，它被捕获为指针
    // 直接使用这个指针，这样修改会反映到外层作用域
    if saved_mutable_names.contains(captured_name) {
      // 可变变量：字段中存储的是指针，直接加载并使用
      let ptr_value = self.builder.createLoad(self.llvm_ctx.getPtrTy(), field_ptr)
      self.name_values.set(captured_name, ptr_value)
      self.name_types.set(captured_name, captured_ty)
      self.mutable_names.add(captured_name)
    } else {
      // 不可变捕获变量，加载值并直接使用
      let field_value = self.builder.createLoad(llvm_ty, field_ptr)
      self.name_values.set(captured_name, field_value)
      self.name_types.set(captured_name, captured_ty)
    }
    
    field_index = field_index + 1
  }
  
  // Register the function itself so it can call itself recursively
  self.name_values.set(closure_def.name, (llvm_func : &@llvm.Value))
  self.name_types.set(closure_def.name, @knf.Type::Function(
    closure_def.params.map(fn(p) { p.1 }),
    closure_def.ret_ty
  ))
  
  // 设置闭包函数的参数（跳过第0个环境指针）
  // 参数索引：0 = 环境指针, 1 = 第一个实际参数, 2 = 第二个实际参数, ...
  let mut i = 0
  while i < closure_def.params.length() {
    let (param_name, param_ty) = closure_def.params[i]
    let llvm_arg = llvm_func.getArg(i + 1).unwrap()  // +1 跳过环境指针
    self.name_values.set(param_name, llvm_arg)
    self.name_types.set(param_name, param_ty)
    i = i + 1
  }
  
  // 生成闭包函数体的 IR 代码
  if closure_def.body.stmts.length() > 0 {
    let stmt_count = closure_def.body.stmts.length()
    if stmt_count > 1 {
      let mut j = 0
      while j < stmt_count - 1 {
        let stmt = closure_def.body.stmts[j]
        self.stmt_codegen(stmt)
        j = j + 1
      }
    }
    
    let last_stmt = closure_def.body.stmts[stmt_count - 1]
    match last_stmt {
      @knf.KnfStmt::Return(_) => self.stmt_codegen(last_stmt)
      @knf.KnfStmt::ReturnUnit => self.stmt_codegen(last_stmt)
      @knf.KnfStmt::ExprStmt(expr) => {
        match closure_def.ret_ty {
          @knf.Type::Unit => {
            let _ = self.expr_codegen(expr)
            let _ = self.builder.createRetVoid()
          }
          _ => {
            match self.expr_codegen(expr) {
              Some(value) => { let _ = self.builder.createRet(value) }
              None => {
                let current_bb = self.builder.getInsertBlock()
                match current_bb.getTerminator() {
                  Some(_) => ()
                  None => raise CodegenError("Tail expression does not produce a value in closure: " + closure_name)
                }
              }
            }
          }
        }
      }
      stmt => {
        self.stmt_codegen(stmt)
        match closure_def.ret_ty {
          @knf.Type::Unit => {
            let _ = self.builder.createRetVoid()
          }
          _ => raise CodegenError("Closure missing return for non-unit type: " + closure_name)
        }
      }
    }
  } else {
    match closure_def.ret_ty {
      @knf.Type::Unit => {
        let _ = self.builder.createRetVoid()
      }
      _ => raise CodegenError("Non-unit closure body missing return")
    }
  }
  
  // ============================================================
  // 第二步：在当前函数中，创建闭包结构体实例
  // ============================================================
  // 闭包函数已经生成完毕，现在需要创建闭包结构体
  // 并将其注册到当前作用域，使其可以被返回或调用
  
  // 恢复之前保存的上下文（回到外层函数）
  self.builder.setInsertPoint(saved_insert_block)
  self.name_values.clear()
  self.name_types.clear()
  self.mutable_names.clear()
  for name, value in saved_name_values {
    self.name_values.set(name, value)
  }
  for name, ty in saved_name_types {
    self.name_types.set(name, ty)
  }
  for name in saved_mutable_names {
    self.mutable_names.add(name)
  }
  
  // 恢复闭包环境
  self.current_closure_env = saved_closure_env
  self.current_closure_func = saved_closure_func
  
  // 构建闭包结构体类型
  // 结构体布局：{ ptr 函数指针, 捕获变量1类型, 捕获变量2类型, ... }
  // 注意：可变变量捕获为指针类型
  let struct_field_types : Array[&@llvm.Type] = Array::new()
  struct_field_types.push(self.llvm_ctx.getPtrTy())  // 第0个字段：函数指针
  for i = 0; i < captured_entries.length(); i = i + 1 {
    let (captured_name, captured_ty) = captured_entries[i]
    // 可变变量捕获为指针，不可变变量捕获为值
    let field_ty : &@llvm.Type = if self.mutable_names.contains(captured_name) {
      (self.llvm_ctx.getPtrTy() : &@llvm.Type)  // 可变变量：存储指针
    } else {
      self.type_codegen_opaque(captured_ty)  // 不可变变量：存储值
    }
    struct_field_types.push(field_ty)
  }
  let struct_ty = self.llvm_ctx.getStructType(struct_field_types)
  
  // 在堆上分配闭包结构体内存
  // 1. 获取结构体大小
  let data_layout = self.llvm_mod.getDataLayout()
  let struct_size = data_layout.getTypeAllocSize(struct_ty)
  let size_value = self.llvm_ctx.getConstInt32(struct_size)
  
  // 2. 调用 malloc 分配内存
  let malloc_func = match self.builtin_funcs.get("moonbit_malloc") {
    Some(func) => func
    None => raise CodegenError("Missing builtin function: moonbit_malloc")
  }
  let closure_ptr = self.builder.createCall(malloc_func, [size_value])
  
  // 填充闭包结构体
  let zero = self.llvm_ctx.getConstInt32(0)
  
  // 1. 存储函数指针到第0个字段
  let fn_ptr_field = self.builder.createGEP(closure_ptr, struct_ty, [zero, zero])
  let _ = self.builder.createStore((llvm_func : &@llvm.Value), fn_ptr_field)
  
  // 2. 存储捕获的变量到后续字段
  field_index = 1
  for i = 0; i < captured_entries.length(); i = i + 1 {
    let (captured_name, _captured_ty) = captured_entries[i]
    
    // 对于可变变量，捕获指针而不是值
    // 这样闭包内部的修改可以反映到外层作用域
    let captured_value = if self.mutable_names.contains(captured_name) {
      // 可变变量：捕获指针（AllocaInst）
      match self.name_values.get(captured_name) {
        Some(value) => value  // 直接使用 AllocaInst 指针
        None => raise CodegenError("Captured variable not found: " + captured_name.to_string())
      }
    } else {
      // 不可变变量：捕获值
      // 使用 resolve_value 来正确处理 AllocaInst（会自动加载）
      self.resolve_value(captured_name)
    }
    
    // 使用 GEP 获取字段地址并存储值/指针
    let idx = self.llvm_ctx.getConstInt32(field_index)
    let field_ptr = self.builder.createGEP(closure_ptr, struct_ty, [zero, idx])
    let _ = self.builder.createStore(captured_value, field_ptr)
    
    field_index = field_index + 1
  }
  
  // 注册闭包到当前作用域
  // 闭包被表示为结构体指针（ptr 类型）
  // 这个指针可以被返回、传递或调用
  self.name_values.set(closure_def.name, closure_ptr)
  self.name_types.set(closure_def.name, @knf.Type::Function(
    closure_def.params.map(fn(p) { p.1 }),
    closure_def.ret_ty
  ))
}
