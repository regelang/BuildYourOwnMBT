# 增强的错误日志系统

本模块为 MiniMoonBit 编译器提供增强的错误日志输出功能，包括：

## 功能特性

### 1. 源代码位置跟踪
- **行号和列号**：精确定位错误发生的位置
- **字节偏移量**：记录在源文件中的准确位置
- **长度信息**：标记错误涉及的代码范围

### 2. 源代码上下文显示
错误输出会显示：
- 错误行及其前后各 2 行的代码
- 行号标注
- 使用 `^` 符号精确指示错误位置

示例输出：
```
Error: Type mismatch: cannot add Int and String

  --> at line 4, column 11

   2 | let x = 10
   3 | let y = "hello"
   4 | let z = x + y  // 类型错误
     |           ^^^^^
   5 | }
```

### 3. 调用堆栈跟踪
显示错误发生时的函数调用链，帮助定位问题根源：

```
Stack trace:
  1. check_binary_expr (typecheck/expr.mbt:45)
  2. check_expr (typecheck/expr.mbt:12)
  3. check_let_stmt (typecheck/let_stmt.mbt:15)
  4. check_block_expr (typecheck/block_expr.mbt:20)
  5. check_top_function (typecheck/top_function.mbt:30)
```

### 4. 完整源文件显示
在需要时，可以显示完整的源文件内容，方便调试复杂问题。

## 核心类型

### SourceLocation
记录源代码中的位置信息：
```moonbit
struct SourceLocation {
  line : Int       // 行号（从 1 开始）
  column : Int     // 列号（从 1 开始）
  offset : Int     // 字节偏移量
  length : Int     // Token/表达式长度
}
```

### ErrorContext
错误上下文信息：
```moonbit
struct ErrorContext {
  location : SourceLocation?  // 错误位置
  source_code : String        // 完整源代码
  message : String            // 错误消息
  stack_trace : Array[String] // 调用堆栈
}
```

### 增强的错误类型
- `EnhancedTokenizeError`：词法分析错误
- `EnhancedParseError`：语法分析错误
- `EnhancedTypeCheckError`：类型检查错误

## 使用方法

### 1. 带位置信息的词法分析
```moonbit
let code = "let x = 42"
let tokens = tokenize_with_location(code)

for token in tokens {
  println("Token: \{token.kind}")
  println("  位置: 行 \{token.location.line}, 列 \{token.location.column}")
}
```

### 2. 创建和格式化错误
```moonbit
let location = SourceLocation::new(line=10, column=5, offset=100, length=3)
let context = ErrorContext::new(
  Some(location),
  source_code,
  "Type mismatch error",
  ["function1", "function2"]
)

println(context.format())
```

### 3. 捕获和处理增强错误
```moonbit
try {
  let tokens = tokenize_with_location(code)
  // ... 处理 tokens
} catch {
  EnhancedTokenizeError(err) => {
    println(err.context.format())
  }
}
```

## 实现细节

### LocationTracker
内部使用 `LocationTracker` 跟踪词法分析过程中的位置：
- 自动处理换行符，更新行号和列号
- 记录字节偏移量
- 支持批量前进多个字符

### 错误格式化
`ErrorContext::format()` 方法生成友好的错误输出：
1. 显示错误消息
2. 标注错误位置（行号、列号）
3. 显示源代码上下文（前后各 2 行）
4. 使用 `^` 符号指示错误位置
5. 显示调用堆栈

## 与现有系统集成

本模块设计为与现有的错误处理系统兼容：
- 可以逐步迁移现有代码
- 保留原有的简单错误类型
- 提供更详细的错误信息选项

## 测试

运行测试：
```bash
moon test error
```

查看示例：
```moonbit
demo_enhanced_error()
demo_tokenize_with_location()
```

## 未来改进

1. **彩色输出**：使用 ANSI 颜色代码高亮错误
2. **多错误收集**：一次编译收集所有错误
3. **建议修复**：提供可能的修复建议
4. **IDE 集成**：生成 LSP 兼容的诊断信息
5. **性能优化**：减少位置跟踪的开销

## 示例

完整示例请参见 `error/example.mbt`。
