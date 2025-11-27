# 使用指南

## 快速开始

### 1. 基本错误报告

```moonbit
let source = "let x = 10 + \"hello\""
let location = SourceLocation::new(1, 14, 13, 7)
let context = ErrorContext::new(
  Some(location),
  source,
  "Type error: cannot add Int and String",
  []
)

println(context.format())
```

输出：
```
Error: Type error: cannot add Int and String

  --> at line 1, column 14

   1 | let x = 10 + "hello"
     |              ^^^^^^^
```

### 2. 在词法分析中使用 LocationTracker

```moonbit
fn tokenize_with_tracking(code : String) -> Array[Token] {
  let tracker = SimpleLocationTracker::new()
  let tokens : Array[Token] = []
  
  // 遍历代码
  let mut i = 0
  while i < code.length() {
    let start_loc = tracker.snapshot(0)
    
    // 解析 token...
    match code.get(i) {
      Some(ch_code) => {
        let ch = ch_code.unsafe_to_char()
        tracker.advance(ch)
        
        // 创建带位置的 token
        let token_length = tracker.get_offset() - start_loc.offset
        let token_loc = SourceLocation::new(
          start_loc.line,
          start_loc.column,
          start_loc.offset,
          token_length
        )
        // tokens.push(Token::new(kind, token_loc))
      }
      None => break
    }
    i = i + 1
  }
  
  tokens
}
```

### 3. 在类型检查中使用

```moonbit
fn check_binary_expr(
  left : Expr,
  op : BinaryOp,
  right : Expr,
  source : String
) -> Expr raise TypeCheckError {
  if left.ty != right.ty {
    let location = SourceLocation::new(
      op.line,
      op.column,
      op.offset,
      op.length
    )
    
    let stack = [
      "check_binary_expr (typecheck.mbt:45)",
      "check_expr (typecheck.mbt:20)",
      "check_function (typecheck.mbt:10)"
    ]
    
    let context = ErrorContext::new(
      Some(location),
      source,
      "Type mismatch in binary expression",
      stack
    )
    
    println(context.format())
    raise TypeCheckError("Type mismatch")
  }
  
  // ...
}
```

### 4. 使用 CachedLocationTracker 进行回溯

```moonbit
fn try_parse_with_backtrack(code : String) -> Result[Expr, String] {
  let tracker = CachedLocationTracker::new()
  
  // 保存当前位置
  tracker.save_position()
  
  // 尝试解析
  match try_parse_expr(code, tracker) {
    Ok(expr) => {
      tracker.clear_saved()
      Ok(expr)
    }
    Err(_) => {
      // 回溯到保存的位置
      let _ = tracker.restore_position()
      // 尝试其他解析方式
      try_parse_alternative(code, tracker)
    }
  }
}
```

### 5. 实现自定义的 LocationTracker

```moonbit
// 带性能统计的位置跟踪器
struct ProfilingLocationTracker {
  mut line : Int
  mut column : Int
  mut offset : Int
  mut advance_count : Int  // 统计 advance 调用次数
} derive(Show)

impl LocationTracker for ProfilingLocationTracker with get_line(self) {
  self.line
}

impl LocationTracker for ProfilingLocationTracker with get_column(self) {
  self.column
}

impl LocationTracker for ProfilingLocationTracker with get_offset(self) {
  self.offset
}

impl LocationTracker for ProfilingLocationTracker with advance(self, ch) {
  self.advance_count = self.advance_count + 1
  if ch == '\n' {
    self.line = self.line + 1
    self.column = 1
  } else {
    self.column = self.column + 1
  }
  self.offset = self.offset + 1
}

impl LocationTracker for ProfilingLocationTracker with snapshot(self, length) {
  SourceLocation::new(self.line, self.column, self.offset, length)
}
```

### 6. 使用 Locatable trait

```moonbit
// 为自定义错误类型实现 Locatable
struct MyError {
  message : String
  location : SourceLocation?
} derive(Show)

impl Locatable for MyError with get_location(self) {
  self.location
}

impl Locatable for MyError with with_location(self, loc) {
  MyError::{ message: self.message, location: Some(loc) }
}

// 使用
fn process() -> Unit {
  let error = MyError::{ message: "Something went wrong", location: None }
  let loc = SourceLocation::new(10, 5, 100, 3)
  let error_with_loc = error.with_location(loc)
  
  match error_with_loc.get_location() {
    Some(l) => println("Error at line \{l.line}, column \{l.column}")
    None => println("Error with no location")
  }
}
```

## 最佳实践

### 1. 在词法分析阶段收集位置信息

在 tokenize 时就记录每个 token 的位置，这样后续阶段可以直接使用。

### 2. 传递源代码

在错误上下文中保存完整的源代码，这样可以显示上下文。

### 3. 构建堆栈跟踪

在每个检查函数中添加函数名到堆栈，便于调试。

```moonbit
fn check_expr(expr : Expr, stack : Array[String]) -> Expr {
  let new_stack = stack + ["check_expr (typecheck.mbt:42)"]
  match expr {
    BinaryExpr(left, op, right) => check_binary_expr(left, op, right, new_stack)
    // ...
  }
}
```

### 4. 使用有意义的错误消息

```moonbit
// 不好
"Type error"

// 好
"Type mismatch: expected Int but got String"

// 更好
"Type mismatch in binary expression: cannot add Int and String"
```

### 5. 提供修复建议（未来功能）

```moonbit
let context = ErrorContext::new(
  Some(location),
  source,
  "Undefined variable 'x'. Did you mean 'y'?",
  stack
)
```

## 性能考虑

1. **LocationTracker 开销**：每次 `advance()` 调用都会更新位置，对于大文件可能有性能影响
2. **优化建议**：
   - 只在需要时创建 `SourceLocation`
   - 使用 `advance_count()` 批量前进
   - 考虑使用 `CachedLocationTracker` 只在关键点保存位置

## 与现有代码集成

### 渐进式迁移

1. 先在新代码中使用增强的错误系统
2. 逐步将旧的错误处理迁移到新系统
3. 保持向后兼容性

### 包装现有错误

```moonbit
try {
  old_function()
} catch {
  OldError(msg) => {
    let context = create_error_context(msg, source_code, None, None)
    println(context.format())
  }
}
```

## 运行示例

```bash
# 运行所有测试
moon test error

# 查看示例输出（需要添加 main 函数）
moon run error
```

## 扩展功能

### 未来可能添加的功能

1. **彩色输出**：使用 ANSI 颜色代码
2. **多错误收集**：一次编译收集所有错误
3. **错误级别**：Error, Warning, Info
4. **修复建议**：自动建议可能的修复
5. **IDE 集成**：生成 LSP 兼容的诊断信息
6. **国际化**：支持多语言错误消息

## 参考

- [README.md](README.md) - 功能概述
- [demo.mbt](demo.mbt) - 完整示例
- [error_test.mbt](error_test.mbt) - 测试用例
