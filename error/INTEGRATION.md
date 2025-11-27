# 错误日志系统集成说明

## 概述

增强的错误日志系统已成功集成到 MiniMoonBit 编译器中。当 `make test` 失败时，编译器会显示详细的错误信息，包括：

- 错误发生的编译阶段（词法分析、语法分析、类型检查等）
- 错误消息
- 源代码上下文（如果可用）
- 调用堆栈（对于类型检查错误）
- 格式化的边框和清晰的视觉分隔

## 集成位置

错误处理已集成到 `bin/main.mbt` 中，这是编译器的主入口点。

### 关键函数

1. **handle_lexer_error** - 处理词法分析错误
2. **handle_parser_error** - 处理语法分析错误  
3. **handle_typecheck_error** - 处理类型检查错误（包含堆栈跟踪）

## 错误输出示例

### 1. 语法错误

```bash
$ moon run bin -- test.mbt --typecheck

╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Parsing                        ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Expected '{' after 'main'


╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at parsing stage                          ║
╚═══════════════════════════════════════════════════════════════╝
```

### 2. 类型错误

```bash
$ moon run bin -- test.mbt --typecheck

╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Type Checking                  ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Type mismatch in function call

Stack trace:
  1. check_program (typecheck/program.mbt)
  2. typecheck (typecheck/typechecker.mbt)
  3. main (bin/main.mbt)

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at type checking stage                    ║
╚═══════════════════════════════════════════════════════════════╝
```

## 测试流程

### 运行单个测试

```bash
# 创建测试文件
cat > /tmp/test.mbt << 'EOF'
fn main() -> Unit {
  let x = 10 + "hello"  // 类型错误
}
EOF

# 运行编译器
moon run bin -- /tmp/test.mbt --typecheck
```

### 运行完整测试套件

```bash
make test
```

当测试失败时，你会看到增强的错误输出，帮助快速定位问题。

## 与现有系统的兼容性

- ✅ 保持与现有测试脚本的兼容性
- ✅ 不影响成功编译的输出
- ✅ 错误时返回非零退出码
- ✅ 支持所有编译阶段的错误报告

## 错误处理流程

```
源代码
  ↓
词法分析 → [错误] → handle_lexer_error → 显示错误 → abort
  ↓
语法分析 → [错误] → handle_parser_error → 显示错误 → abort
  ↓
类型检查 → [错误] → handle_typecheck_error → 显示错误 → abort
  ↓
KNF 转换 → [错误] → 简单错误消息 → abort
  ↓
代码生成 → [错误] → 简单错误消息 → abort
  ↓
成功
```

## 未来改进

1. **添加位置信息**
   - 在词法分析阶段跟踪每个 token 的位置
   - 在错误消息中显示行号和列号
   - 使用 `^` 符号指示错误位置

2. **彩色输出**
   - 使用 ANSI 颜色代码高亮错误
   - 红色表示错误，黄色表示警告

3. **多错误收集**
   - 一次编译收集所有错误
   - 显示错误总数和详细列表

4. **修复建议**
   - 分析常见错误模式
   - 提供可能的修复建议

## 开发者指南

### 添加新的错误处理

如果需要为新的编译阶段添加错误处理：

```moonbit
// 在 bin/main.mbt 中添加新的处理函数
fn handle_new_stage_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - New Stage                      ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  println("File: \{filename}")
  println("")
  
  let context = @error.create_error_context(msg, code, None, None)
  println(context.format())
  
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at new stage                              ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

// 在 main 函数中使用
let result = try {
  new_stage_transform!(input)
} catch {
  NewStageError(msg) => {
    handle_new_stage_error(msg, code, input_file)
    abort("New stage error")
  }
}
```

### 添加位置信息

要添加位置信息到错误消息：

```moonbit
// 创建带位置的错误上下文
let location = @error.SourceLocation::new(line, column, offset, length)
let context = @error.ErrorContext::new(
  Some(location),
  code,
  msg,
  stack_trace
)
```

## 相关文件

- `error/error.mbt` - 错误上下文和格式化
- `error/location_tracker.mbt` - 位置跟踪 trait 和实现
- `bin/main.mbt` - 编译器入口和错误处理集成
- `error/README.md` - 错误系统功能概述
- `error/USAGE.md` - 使用指南和示例

## 测试

运行错误模块的测试：

```bash
moon test error
```

所有测试应该通过，确保错误处理系统正常工作。

## 总结

增强的错误日志系统现在已完全集成到编译器中，提供清晰、有用的错误消息，帮助开发者快速定位和修复问题。系统设计为可扩展的，可以轻松添加新的错误类型和改进。
