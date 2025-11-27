/// MiniMoonBit 编译器入口
/// 
/// 根据评测平台要求实现的编译器入口
/// 支持的命令：
/// - moon run src/bin/main.mbt -- --typecheck <input>  # 类型检查
/// - moon run src/bin/main.mbt -- <input> -o <output> # 代码生成

/// 尝试从错误消息中提取位置信息
fn extract_location_from_message(msg : String) -> (Int?, Int?) {
  // 尝试匹配 "at line X" 或 "line X" 模式
  let mut line : Int? = None
  let col : Int? = None
  
  // 简单的字符串搜索来找行号
  if msg.contains("line") {
    // 将字符串分割成数组
    let parts : Array[String] = []
    for part in msg.split(" ") {
      parts.push(part.to_string())
    }
    
    // 尝试提取行号
    let mut i = 0
    while i < parts.length() {
      if parts[i] == "line" && i + 1 < parts.length() {
        // 尝试解析下一个部分为数字
        let num_str = parts[i + 1]
            // 尝试解析下一个部分为数字。先尝试原样解析；如果失败，逐步去掉末尾字符再尝试（最多 3 次）。
            let mut clean_str = num_str
            let mut attempts = 0
            while attempts < 3 {
              try {
                let n = @strconv.parse_int(clean_str)
                line = Some(n)
                break
              } catch {
                _ => {
                  // 删除最后一个字符并重试
                  if clean_str.length() > 0 {
                    clean_str = clean_str.unsafe_substring(start = 0, end = clean_str.length() - 1)
                  }
                  attempts = attempts + 1
                }
              }
            }
        break
      }
      i = i + 1
    }
  }
  
  (line, col)
}

/// 处理词法分析错误
fn handle_lexer_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - Lexical Analysis               ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  
  let (line, _col) = extract_location_from_message(msg)
  let context = @error.create_error_context(msg, code, line, None, filename)
  println(context.format())
  
  // 添加提示信息
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at lexical analysis stage                 ║")
  println("║                                                               ║")
  println("║ Common lexical errors:                                       ║")
  println("║ - Invalid character in source code                           ║")
  println("║ - Unterminated string literal                                ║")
  println("║ - Invalid number format                                      ║")
  println("║ - Invalid escape sequence in string                          ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

/// 处理语法分析错误
fn handle_parser_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - Parsing                        ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  
  let (line, _col) = extract_location_from_message(msg)
  let context = @error.create_error_context(msg, code, line, None, filename)
  println(context.format())
  
  // 添加提示信息
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at parsing stage                          ║")
  println("║                                                               ║")
  println("║ Common syntax errors:                                        ║")
  println("║ - Missing semicolon ';' at end of statement                  ║")
  println("║ - Mismatched brackets (), [], or {}                          ║")
  println("║ - Missing 'fn' keyword before function definition            ║")
  println("║ - Invalid expression or statement syntax                     ║")
  println("║ - Missing type annotation where required                     ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

/// 处理类型检查错误
fn handle_typecheck_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - Type Checking                  ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  
  let stack_trace = [
    "check_program (typecheck/program.mbt)",
    "typecheck (typecheck/typechecker.mbt)",
    "main (bin/main.mbt)"
  ]
  let (line, _col) = extract_location_from_message(msg)
  let context = if line.is_empty() {
    @error.ErrorContext::with_file(None, code, msg, stack_trace, filename)
  } else {
    @error.ErrorContext::with_line_only(line.unwrap(), code, msg, stack_trace, filename)
  }
  println(context.format())
  
  // 添加提示信息
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at type checking stage                    ║")
  println("║                                                               ║")
  println("║ Common type errors:                                          ║")
  println("║ - Type mismatch (e.g., Int vs Double)                        ║")
  println("║ - Undefined variable or function                             ║")
  println("║ - Wrong number of function arguments                         ║")
  println("║ - Invalid operation on types                                 ║")
  println("║ - Return type doesn't match function signature               ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

/// 处理 KNF 转换错误
fn handle_knf_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - KNF Transformation             ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")

  let stack_trace = [
    "knf_transform (knf/knf.mbt)",
    "main (bin/main.mbt)"
  ]
  let (line, _col) = extract_location_from_message(msg)
  let context = if line.is_empty() {
    @error.ErrorContext::with_file(None, code, msg, stack_trace, filename)
  } else {
    @error.ErrorContext::with_line_only(line.unwrap(), code, msg, stack_trace, filename)
  }
  println(context.format())

  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at KNF transformation stage               ║")
  println("║                                                               ║")
  println("║ This is an internal compiler error during intermediate       ║")
  println("║ representation transformation. Please report this bug.       ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

/// 处理代码生成错误
fn handle_codegen_error(msg : String, code : String, filename : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           COMPILATION ERROR - Code Generation                ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  
  let stack_trace = [
    "codegen (codegen/codegen.mbt)",
    "main (bin/main.mbt)"
  ]
  let (line, _col) = extract_location_from_message(msg)
  let context = if line.is_empty() {
    @error.ErrorContext::with_file(None, code, msg, stack_trace, filename)
  } else {
    @error.ErrorContext::with_line_only(line.unwrap(), code, msg, stack_trace, filename)
  }
  println(context.format())
  
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed at code generation stage                  ║")
  println("║                                                               ║")
  println("║ Common code generation issues:                               ║")
  println("║ - Unsupported language feature                               ║")
  println("║ - Internal compiler error                                    ║")
  println("║ - Invalid intermediate representation                        ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

/// 处理文件 I/O 错误
fn handle_io_error(msg : String, filename : String, operation : String) -> Unit {
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║           FILE I/O ERROR                                     ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println("")
  println("File: \{filename}")
  println("Operation: \{operation}")
  println("")
  println("Error: \{msg}")
  println("")
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║ Compilation failed due to I/O error                          ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
}

fn main {
  println("main: starting");
  let args = @sys.get_cli_args()
  
  // 使用 ArgParser 解析命令行参数
  let typecheck_only = { val: false }
  let output_file = { val: "" }
  let input_files : Array[String] = []
  
  let speclist = [
    ("--typecheck", "", @ArgParser.Set(typecheck_only), "Type check only"),
    ("-o", "", @ArgParser.Set_string(output_file), "Output file")
  ]
  
  let rest : (String) -> Unit raise = fn(arg) { input_files.push(arg) }
  let usage_msg = "Usage: minimoonbit [--typecheck] <input> [-o <output>]"
  
  let args_array = Array::new(capacity=args.length() - 1)
  for i = 1; i < args.length(); i = i + 1 {
    args_array.push(args[i])
  }
  
  try {
    @ArgParser.parse(speclist, rest, usage_msg, args_array)
  } catch {
    @ArgParser.ErrorMsg(msg) => {
      println(msg)
      @sys.exit(1)
    }
    _ => {
      println("Error parsing arguments")
      @sys.exit(1)
    }
  }
  
  if input_files.length() == 0 {
    println("Error: No input file specified")
    println(usage_msg)
    @sys.exit(1)
  }
  
  let input_file = input_files[0]
  println("main: reading file \{input_file}");
  
  // 读取源代码
  let code = try {
    @fs.read_file_to_string(input_file)
  } catch {
    @fs.IOError(msg) => {
      handle_io_error(msg, input_file, "reading input file")
      abort("Failed to read input file")
    }
  }
  
  println("main: tokenizing");
  // 词法分析
  let tokens = try {
    @lexer.tokenize(code)
  } catch {
    @lexer.TokenizeError(msg) => {
      handle_lexer_error(msg, code, input_file)
      abort("Lexer error")
    }
  }
  
  println("main: parsing");
  // 语法分析
  let prog = try {
    @parser.parse(tokens)
  } catch {
    @parser.ParseError(msg) => {
      handle_parser_error(msg, code, input_file)
      abort("Parse error")
    }
  }
  
  println("main: typechecking");
  // 类型检查
  let checked_prog = try {
    @typecheck.typecheck(prog)
  } catch {
    @typecheck.TypeCheckError(msg) => {
      handle_typecheck_error(msg, code, input_file)
      abort("Type check error")
    }
  }
  
  // 如果只需要类型检查，到此结束
  if typecheck_only.val {
    // 类型检查成功，正常退出
    return
  }
  
  // 检查输出文件
  if output_file.val == "" {
    println("Error: No output file specified (use -o <output>)")
    @sys.exit(1)
  }
  
  // 输出源码
  println("\n╔═══════════════════════════════════════════════════════════════╗")
  println("║                    SOURCE CODE                                ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println(code)
  println("")
  
  // KNF 转换
  let knf_prog = try {
    @knf.knf_transform(checked_prog)
  } catch {
    @knf.KnfTransformError(msg) => {
      handle_knf_error(msg, code, input_file)
      abort("KNF transform error")
    }
  }
  
  // 输出 KNF
  println("\n╔═══════════════════════════════════════════════════════════════╗")
  println("║                    KNF CODE                                   ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println(knf_prog.to_string())
  println("")
  
  // 代码生成
  let llvm_module = try {
    @codegen.codegen(knf_prog)
  } catch {
    @codegen.CodegenError(msg) => {
      handle_codegen_error(msg, code, input_file)
      abort("Codegen error")
    }
    e => {
      // 处理未知错误
      let error_msg = "Unknown error during code generation: \{e}"
      handle_codegen_error(error_msg, code, input_file)
      abort("Unknown codegen error")
    }
  }
  
  // 输出 LLVM IR
  let ir_code = llvm_module.to_string()
  
  println("╔═══════════════════════════════════════════════════════════════╗")
  println("║                    LLVM IR CODE                               ║")
  println("╚═══════════════════════════════════════════════════════════════╝")
  println(ir_code)
  println("")
  
  try {
    @fs.write_string_to_file(output_file.val, ir_code) |> ignore
  } catch {
    @fs.IOError(msg) => {
      handle_io_error(msg, output_file.val, "writing output file")
      abort("Failed to write output file")
    }
  }
}
