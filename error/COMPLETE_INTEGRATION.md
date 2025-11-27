# 完整的错误处理集成

## 概述

增强的错误日志系统已完全集成到 MiniMoonBit 编译器的**所有编译阶段**，从词法分析到代码生成，任何阶段发生错误都会调用统一的错误处理接口。

## 集成的编译阶段

### 1. 词法分析 (Lexical Analysis)

**错误处理函数**: `handle_lexer_error`

**触发条件**: 
- 无效的字符
- 未终止的字符串
- 非法的数字格式

**错误输出示例**:
```
╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Lexical Analysis               ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Unexpected character: '@'

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at lexical analysis stage                 ║
╚═══════════════════════════════════════════════════════════════╝
```

### 2. 语法分析 (Parsing)

**错误处理函数**: `handle_parser_error`

**触发条件**:
- 缺少必需的语法元素（如 `{`, `}`, `;`）
- 语法结构不正确
- Token 顺序错误

**错误输出示例**:
```
╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Parsing                        ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Expected '{' after function signature

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at parsing stage                          ║
╚═══════════════════════════════════════════════════════════════╝
```

### 3. 类型检查 (Type Checking)

**错误处理函数**: `handle_typecheck_error`

**触发条件**:
- 类型不匹配
- 未定义的变量或函数
- 参数数量或类型错误
- 循环依赖

**错误输出示例**:
```
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

### 4. KNF 转换 (KNF Transformation)

**错误处理函数**: `handle_knf_error`

**触发条件**:
- KNF 转换过程中的内部错误
- 不支持的语言特性

**错误输出示例**:
```
╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - KNF Transformation             ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Failed to transform expression to KNF

Stack trace:
  1. knf_transform (knf/knf.mbt)
  2. main (bin/main.mbt)

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at KNF transformation stage               ║
╚═══════════════════════════════════════════════════════════════╝
```

### 5. 代码生成 (Code Generation)

**错误处理函数**: `handle_codegen_error`

**触发条件**:
- LLVM IR 生成错误
- 不支持的操作
- 内部代码生成错误

**错误输出示例**:
```
╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Code Generation                ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt

Error: Failed to generate LLVM IR for function

Stack trace:
  1. codegen (codegen/codegen.mbt)
  2. main (bin/main.mbt)

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed at code generation stage                  ║
╚═══════════════════════════════════════════════════════════════╝
```

### 6. 文件 I/O (File Operations)

**错误处理函数**: `handle_io_error`

**触发条件**:
- 文件不存在
- 权限不足
- 磁盘空间不足
- 写入失败

**错误输出示例**:
```
╔═══════════════════════════════════════════════════════════════╗
║           FILE I/O ERROR                                     ║
╚═══════════════════════════════════════════════════════════════╝

File: test.mbt
Operation: reading input file

Error: No such file or directory

╔═══════════════════════════════════════════════════════════════╗
║ Compilation failed due to I/O error                          ║
╚═══════════════════════════════════════════════════════════════╝
```

## 错误处理流程图

```
┌─────────────────┐
│  读取源文件      │
└────────┬────────┘
         │ [I/O Error] → handle_io_error → abort
         ↓
┌─────────────────┐
│  词法分析        │
└────────┬────────┘
         │ [TokenizeError] → handle_lexer_error → abort
         ↓
┌─────────────────┐
│  语法分析        │
└────────┬────────┘
         │ [ParseError] → handle_parser_error → abort
         ↓
┌─────────────────┐
│  类型检查        │
└────────┬────────┘
         │ [TypeCheckError] → handle_typecheck_error → abort
         ↓
┌─────────────────┐
│  KNF 转换       │
└────────┬────────┘
         │ [KnfTransformError] → handle_knf_error → abort
         ↓
┌─────────────────┐
│  代码生成        │
└────────┬────────┘
         │ [CodegenError] → handle_codegen_error → abort
         ↓
┌─────────────────┐
│  写入输出文件    │
└────────┬────────┘
         │ [I/O Error] → handle_io_error → abort
         ↓
┌─────────────────┐
│  编译成功 ✓     │
└─────────────────┘
```

## 实现细节

### 错误处理函数签名

所有错误处理函数遵循统一的接口：

```moonbit
fn handle_xxx_error(msg : String, code : String, filename : String) -> Unit
```

参数说明：
- `msg`: 错误消息
- `code`: 完整的源代码（用于显示上下文）
- `filename`: 源文件名

### 错误上下文创建

```moonbit
let context = @error.create_error_context(msg, code, None, None)
// 或者带堆栈跟踪
let context = @error.ErrorContext::new(None, code, msg, stack_trace)
```

### 统一的错误输出格式

所有错误都使用统一的格式：
1. 顶部边框 + 错误类型标题
2. 文件名
3. 错误消息和上下文
4. 堆栈跟踪（如果有）
5. 底部边框 + 失败阶段说明

## 测试

### 运行完整测试

```bash
./test_all_error_stages.sh
```

这个脚本会测试所有编译阶段的错误处理。

### 手动测试单个阶段

```bash
# 测试词法错误
cat > test.mbt << 'EOF'
fn main() -> Unit {
  let x = @invalid
}
EOF
moon run bin -- test.mbt --typecheck

# 测试语法错误
cat > test.mbt << 'EOF'
fn main() -> Unit {
  let x = 10 +
}
EOF
moon run bin -- test.mbt --typecheck

# 测试类型错误
cat > test.mbt << 'EOF'
fn takes_int(x : Int) -> Int { x }
fn main() -> Unit {
  takes_int("hello")
}
EOF
moon run bin -- test.mbt --typecheck

# 测试 I/O 错误
moon run bin -- nonexistent.mbt --typecheck
```

## 与 make test 的集成

当运行 `make test` 时，如果任何测试用例编译失败，会自动显示增强的错误信息：

```bash
make test
```

输出示例：
```
Testing test_case_1.mbt ... 
╔═══════════════════════════════════════════════════════════════╗
║           COMPILATION ERROR - Type Checking                  ║
╚═══════════════════════════════════════════════════════════════╝

File: test_case_1.mbt

Error: Type mismatch...

[FAIL]
```

## 代码位置

所有错误处理函数都在 `bin/main.mbt` 中实现：

- `handle_lexer_error` (行 9-23)
- `handle_parser_error` (行 26-40)
- `handle_typecheck_error` (行 43-62)
- `handle_knf_error` (行 65-82)
- `handle_codegen_error` (行 85-102)
- `handle_io_error` (行 105-118)

## 扩展性

添加新的编译阶段错误处理非常简单：

```moonbit
/// 处理新阶段错误
fn handle_new_stage_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - New Stage                      ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  println("File: \{filename}")
  println("")
  
  let stack_trace = ["new_stage (new/stage.mbt)", "main (bin/main.mbt)"]
  let context = @error.ErrorContext::new(None, code, msg, stack_trace)
  println(context.format())
  
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at new stage                              ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

// 在 main 函数中使用
let result = try {
  new_stage_process!(input)
} catch {
  NewStageError(msg) => {
    handle_new_stage_error(msg, code, input_file)
    abort("New stage error")
  }
}
```

## 优势

1. **统一性**: 所有阶段使用相同的错误格式
2. **完整性**: 覆盖从输入到输出的所有阶段
3. **可维护性**: 集中管理错误处理逻辑
4. **可扩展性**: 易于添加新的错误类型
5. **用户友好**: 清晰的错误消息和视觉分隔

## 总结

增强的错误日志系统现在完全集成到编译器的所有阶段，确保无论在哪个阶段发生错误，用户都能获得清晰、有用的错误信息，大大提升了调试体验和开发效率。
