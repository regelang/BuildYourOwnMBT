/// 源代码位置信息
pub(all) struct SourceLocation {
  line : Int?       // 行号（从 1 开始），None 表示未知
  column : Int?     // 列号（从 1 开始），None 表示未知
  offset : Int      // 在源文件中的字节偏移量
  length : Int      // Token 或表达式的长度
  function : String? // 所在函数名，None 表示未知
} derive(Show, Eq)

/// 创建新的源代码位置（完整信息）
pub fn SourceLocation::new(line : Int, column : Int, offset : Int, length : Int) -> SourceLocation {
  SourceLocation::{ 
    line: Some(line), 
    column: Some(column), 
    offset, 
    length,
    function: None
  }
}

/// 创建只有行号的位置
pub fn SourceLocation::with_line(line : Int) -> SourceLocation {
  SourceLocation::{ 
    line: Some(line), 
    column: None, 
    offset: 0, 
    length: 0,
    function: None
  }
}

/// 创建只有函数名的位置
pub fn SourceLocation::with_function(function : String) -> SourceLocation {
  SourceLocation::{ 
    line: None, 
    column: None, 
    offset: 0, 
    length: 0,
    function: Some(function)
  }
}

/// 为位置添加函数信息
pub fn SourceLocation::set_function(self : SourceLocation, func : String) -> SourceLocation {
  SourceLocation::{ 
    line: self.line, 
    column: self.column, 
    offset: self.offset, 
    length: self.length,
    function: Some(func)
  }
}

/// 错误上下文信息
pub(all) struct ErrorContext {
  location : SourceLocation?  // 错误发生的位置（行列号）
  line_only : Int?            // 只有行号（没有列号时）
  function_name : String?     // 函数名（没有行号时）
  filename : String           // 文件名（始终有）
  source_code : String        // 完整的源代码
  message : String            // 错误消息
  stack_trace : Array[String] // 调用堆栈
} derive(Show)

/// 创建新的错误上下文（旧接口，保持兼容）
pub fn ErrorContext::new(
  location : SourceLocation?,
  source_code : String,
  message : String,
  stack_trace : Array[String]
) -> ErrorContext {
  ErrorContext::{ 
    location, 
    line_only: None,
    function_name: None,
    filename: "",
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建带文件名的错误上下文
pub fn ErrorContext::with_file(
  location : SourceLocation?,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location, 
    line_only: None,
    function_name: None,
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建只有行号的错误上下文
pub fn ErrorContext::with_line_only(
  line : Int,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location: None, 
    line_only: Some(line),
    function_name: None,
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建只有函数名的错误上下文
pub fn ErrorContext::with_function_only(
  function : String,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location: None, 
    line_only: None,
    function_name: Some(function),
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建只有文件名的错误上下文
pub fn ErrorContext::file_only(
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location: None, 
    line_only: None,
    function_name: None,
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建带文件名的错误上下文
pub fn ErrorContext::with_filename(
  location : SourceLocation?,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location, 
    line_only: None,
    function_name: None,
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建只有行号的错误上下文
pub fn ErrorContext::with_line(
  line : Int,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location: None,
    line_only: Some(line),
    function_name: None,
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 创建只有函数名的错误上下文
pub fn ErrorContext::with_function(
  function_name : String,
  source_code : String,
  message : String,
  stack_trace : Array[String],
  filename : String
) -> ErrorContext {
  ErrorContext::{ 
    location: None,
    line_only: None,
    function_name: Some(function_name),
    filename,
    source_code, 
    message, 
    stack_trace 
  }
}

/// 辅助函数：显示完整源代码（限制行数）
fn show_full_source(output : StringBuilder, lines : Array[String], max_lines : Int) -> Unit {
  let display_lines = if lines.length() > max_lines { max_lines } else { lines.length() }
  
  let mut i = 1
  while i <= display_lines {
    let line_num_str = i.to_string()
    let padding = if i < 10 { "  " } else if i < 100 { " " } else { "" }
    
    output.write_string("   ")
    output.write_string(padding)
    output.write_string(line_num_str)
    output.write_string(" | ")
    
    if i <= lines.length() {
      output.write_string(lines[i - 1])
    }
    output.write_char('\n')
    
    i = i + 1
  }
  
  if lines.length() > max_lines {
    output.write_string("     | ... (\{lines.length() - max_lines} more lines)\n")
  }
  
  output.write_char('\n')
}

/// 辅助函数：显示源代码并尝试标记可能的错误位置
fn show_full_source_with_hints(output : StringBuilder, lines : Array[String], error_msg : String, max_lines : Int) -> Unit {
  let display_lines = if lines.length() > max_lines { max_lines } else { lines.length() }
  
  // 尝试从错误消息中找到关键词来猜测错误位置
  let keywords = extract_keywords_from_error(error_msg)
  
  let mut i = 1
  while i <= display_lines {
    let line_num_str = i.to_string()
    let padding = if i < 10 { "  " } else if i < 100 { " " } else { "" }
    
    // 检查这一行是否可能包含错误
    let line_content = if i <= lines.length() { lines[i - 1] } else { "" }
    let might_be_error = line_contains_keywords(line_content, keywords)
    let marker = if might_be_error { " ? " } else { "   " }
    
    output.write_string(marker)
    output.write_string(padding)
    output.write_string(line_num_str)
    output.write_string(" | ")
    output.write_string(line_content)
    output.write_char('\n')
    
    // 如果可能是错误行，添加提示
    if might_be_error {
      output.write_string("     | ")
      let mut j = 0
      while j < line_content.length() {
        output.write_char('~')
        j = j + 1
      }
      output.write_string(" (possible error location)\n")
    }
    
    i = i + 1
  }
  
  if lines.length() > max_lines {
    output.write_string("     | ... (\{lines.length() - max_lines} more lines)\n")
  }
  
  output.write_char('\n')
  output.write_string("Note: '?' marks lines that might contain the error\n\n")
}

/// 从错误消息中提取关键词
fn extract_keywords_from_error(msg : String) -> Array[String] {
  let keywords : Array[String] = []
  
  // 常见的错误关键词
  if msg.contains("Expected") {
    if msg.contains("'{'") { keywords.push("{") }
    if msg.contains("'}'") { keywords.push("}") }
    if msg.contains("';'") { keywords.push(";") }
    if msg.contains("'('") { keywords.push("(") }
    if msg.contains("')'") { keywords.push(")") }
  }
  
  if msg.contains("after") {
    if msg.contains("main") { keywords.push("main") }
    if msg.contains("fn") { keywords.push("fn") }
    if msg.contains("let") { keywords.push("let") }
  }
  
  keywords
}

/// 检查行是否包含关键词
fn line_contains_keywords(line : String, keywords : Array[String]) -> Bool {
  if keywords.length() == 0 {
    return false
  }
  
  let mut i = 0
  while i < keywords.length() {
    if line.contains(keywords[i]) {
      return true
    }
    i = i + 1
  }
  false
}

/// 辅助函数：将字符串分割成行数组
pub fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current_line = StringBuilder::new()
  let mut i = 0
  
  while i < s.length() {
    match s.get(i) {
      Some(ch_code) => {
        let ch = ch_code.unsafe_to_char()
        if ch == '\n' {
          lines.push(current_line.to_string())
          current_line.reset()
        } else {
          current_line.write_char(ch)
        }
      }
      None => break
    }
    i = i + 1
  }
  
  // 添加最后一行（如果有内容）
  let last = current_line.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  
  lines
}

/// 格式化错误信息，包含源代码上下文
pub fn ErrorContext::format(self : ErrorContext) -> String {
  let output = StringBuilder::new()
  
  // 错误标题
  output.write_string("Error: ")
  output.write_string(self.message)
  output.write_char('\n')
  
  // 显示文件名（如果有）
  if self.filename.length() > 0 {
    output.write_string("File: ")
    output.write_string(self.filename)
    output.write_char('\n')
  }
  output.write_char('\n')
  
  // 按优先级显示位置信息和源代码
  if self.source_code.length() > 0 {
    let lines_array = split_lines(self.source_code)
    
    // 优先级 1: 精确位置（行号 + 列号）
    match self.location {
      Some(loc) => {
        match (loc.line, loc.column) {
          (Some(line), Some(column)) => {
            // 有行号和列号
            output.write_string("  --> at line ")
            output.write_string(line.to_string())
            output.write_string(", column ")
            output.write_string(column.to_string())
            output.write_char('\n')
            output.write_char('\n')
            
            let start_line = if line > 2 { line - 2 } else { 1 }
            let end_line = if line + 2 < lines_array.length() { line + 2 } else { lines_array.length() }
            
            let mut i = start_line
            while i <= end_line {
              let line_num_str = i.to_string()
              let padding = if i < 10 { "  " } else if i < 100 { " " } else { "" }
              
              output.write_string(padding)
              output.write_string(line_num_str)
              output.write_string(" | ")
              
              if i <= lines_array.length() {
                output.write_string(lines_array[i - 1])
              }
              output.write_char('\n')
              
              // 如果是错误行，添加指示符
              if i == line {
                output.write_string("     | ")
                let mut j = 1
                while j < column {
                  output.write_char(' ')
                  j = j + 1
                }
                let mut k = 0
                while k < loc.length {
                  output.write_char('^')
                  k = k + 1
                }
                output.write_char('\n')
              }
              
              i = i + 1
            }
            output.write_char('\n')
          }
          (Some(line), None) => {
            // 优先级 2: 只有行号
            output.write_string("  --> at line ")
            output.write_string(line.to_string())
            output.write_char('\n')
            output.write_char('\n')
            
            let start_line = if line > 2 { line - 2 } else { 1 }
            let end_line = if line + 2 < lines_array.length() { line + 2 } else { lines_array.length() }
            
            let mut i = start_line
            while i <= end_line {
              let line_num_str = i.to_string()
              let padding = if i < 10 { "  " } else if i < 100 { " " } else { "" }
              let marker = if i == line { " > " } else { "   " }
              
              output.write_string(marker)
              output.write_string(padding)
              output.write_string(line_num_str)
              output.write_string(" | ")
              
              if i <= lines_array.length() {
                output.write_string(lines_array[i - 1])
              }
              output.write_char('\n')
              
              i = i + 1
            }
            output.write_char('\n')
          }
          _ => {
            // 优先级 3: 有函数名
            match loc.function {
              Some(func) => {
                output.write_string("  --> in function '")
                output.write_string(func)
                output.write_string("'\n\n")
                show_full_source(output, lines_array, 20)
              }
              None => {
                // 优先级 4: 只有文件名 - 显示更多行数
                output.write_string("Source code:\n\n")
                show_full_source(output, lines_array, 1024)
              }
            }
          }
        }
      }
      None => {
        // 检查 line_only
        match self.line_only {
          Some(line) => {
            // 优先级 2: 只有行号
            output.write_string("  --> at line ")
            output.write_string(line.to_string())
            output.write_char('\n')
            output.write_char('\n')
            
            let start_line = if line > 2 { line - 2 } else { 1 }
            let end_line = if line + 2 < lines_array.length() { line + 2 } else { lines_array.length() }
            
            let mut i = start_line
            while i <= end_line {
              let line_num_str = i.to_string()
              let padding = if i < 10 { "  " } else if i < 100 { " " } else { "" }
              let marker = if i == line { " > " } else { "   " }
              
              output.write_string(marker)
              output.write_string(padding)
              output.write_string(line_num_str)
              output.write_string(" | ")
              
              if i <= lines_array.length() {
                output.write_string(lines_array[i - 1])
              }
              output.write_char('\n')
              
              i = i + 1
            }
            output.write_char('\n')
          }
          None => {
            // 检查 function_name
            match self.function_name {
              Some(func) => {
                // 优先级 3: 只有函数名
                output.write_string("  --> in function '")
                output.write_string(func)
                output.write_string("'\n\n")
                show_full_source(output, lines_array, 20)
              }
              None => {
                // 优先级 4: 只有文件名 - 显示更多行数
                output.write_string("Source code:\n\n")
                show_full_source(output, lines_array, 1024)
              }
            }
          }
        }
      }
    }
  }
  
  // 显示堆栈跟踪
  if self.stack_trace.length() > 0 {
    output.write_string("Stack trace:\n")
    let mut i = 0
    while i < self.stack_trace.length() {
      output.write_string("  ")
      output.write_string((i + 1).to_string())
      output.write_string(". ")
      output.write_string(self.stack_trace[i])
      output.write_char('\n')
      i = i + 1
    }
  }
  
  output.to_string()
}

/// 将简单错误消息转换为增强的错误上下文
pub fn create_error_context(
  message : String,
  source_code : String,
  line : Int?,
  column : Int?,
  filename : String
) -> ErrorContext {
  match (line, column) {
    (Some(l), Some(c)) => {
      let loc = SourceLocation::new(l, c, 0, 1)
      ErrorContext::with_file(Some(loc), source_code, message, [], filename)
    }
    (Some(l), None) => {
      ErrorContext::with_line_only(l, source_code, message, [], filename)
    }
    _ => {
      ErrorContext::file_only(source_code, message, [], filename)
    }
  }
}

/// 添加堆栈跟踪到错误上下文
pub fn ErrorContext::with_stack_trace(
  self : ErrorContext,
  stack : Array[String]
) -> ErrorContext {
  ErrorContext::new(self.location, self.source_code, self.message, stack)
}

/// Trait: 可以跟踪位置的类型
pub trait Locatable {
  get_location(Self) -> SourceLocation?
  with_location(Self, SourceLocation) -> Self
}

/// 为 ErrorContext 实现 Locatable trait
pub impl Locatable for ErrorContext with get_location(self) {
  self.location
}

pub impl Locatable for ErrorContext with with_location(self, loc) {
  ErrorContext::new(Some(loc), self.source_code, self.message, self.stack_trace)
}
