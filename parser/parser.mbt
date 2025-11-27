/// 程序结构体
/// 
/// 表示解析后的完整程序，包含：
/// - top_lets: 顶层 let 绑定（全局变量）
/// - top_functions: 顶层函数定义
/// - struct_defs: 结构体定义
pub(all) struct Program {
  top_lets : Map[String, TopLet]           // 顶层 let 绑定
  top_functions : Map[String, TopFunction] // 顶层函数
  struct_defs : Map[String, StructDef]     // 结构体定义
  enum_defs : Map[String, EnumDef]         // 枚举定义
} derive(Show)

/// 解析 token 流，生成 AST
/// 
/// 这是语法分析的入口函数，将 token 流转换为抽象语法树（AST）
/// 
/// 参数：
/// - tokens: 词法分析产生的 token 数组
/// 
/// 返回：解析后的程序 AST
/// 
/// 异常：如果遇到语法错误，抛出 ParseError///|
pub fn parse(tokens : Array[Token]) -> Program raise ParseError {
  println("parse: starting");
  let top_lets = Map::new()
  let top_functions = Map::new()
  let struct_defs = Map::new()
  let enum_defs = Map::new()
  
  // 将数组转换为 ArrayView 用于解析
  let mut remaining_tokens = tokens[:]
  
  // 辅助函数：跳过空白符（如果有的话）
  fn skip_whitespace(tokens: ArrayView[Token]) -> ArrayView[Token] {
    let mut i = 0
    while i < tokens.length() {
      match tokens[i].kind {
        // 跳过空白符 token（如果词法分析器产生了的话）
        _ => break
      }
      i = i + 1
    }
    tokens[i:]
  }
  
  // 循环解析所有顶层声明
  while remaining_tokens.length() > 0 {
    // 跳过前导空白符
    remaining_tokens = skip_whitespace(remaining_tokens)
    if remaining_tokens.length() == 0 {
      break
    }
    
    // 根据第一个 token 的类型决定解析什么
    match remaining_tokens[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Fn) => {
        // 解析顶层函数定义
        let (func, new_tokens) = parse_top_function(remaining_tokens)
        // 将函数添加到映射中
        top_functions[func.fname] = func
        remaining_tokens = new_tokens
      }
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) => {
        // 解析顶层 let 绑定
        let (let_binding, new_tokens) = parse_top_let(remaining_tokens)
        top_lets[let_binding.name] = let_binding
        remaining_tokens = new_tokens
      }
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Struct) => {
        // Parse struct definition
        let (struct_def, new_tokens) = parse_struct_def(remaining_tokens)
        struct_defs[struct_def.name] = struct_def
        remaining_tokens = new_tokens
      }
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Enum) => {
        // Parse enum definition
        let (enum_def, new_tokens) = parse_enum_def(remaining_tokens)
        enum_defs[enum_def.name] = enum_def
        remaining_tokens = new_tokens
      }
      @moonbitlang/MiniMoonbit/lexer.TokenKind::EOF => {
        // End of input
        break
      }
      _ => {
        // Skip unknown tokens (could be whitespace or comments handled by the lexer)
        if remaining_tokens.length() > 1 {
          remaining_tokens = remaining_tokens[1:]
        } else {
          break
        }
      }
    }
  }
  
  Program::{
    top_lets: top_lets,
    top_functions: top_functions,
    struct_defs: struct_defs,
    enum_defs: enum_defs
  }
}
