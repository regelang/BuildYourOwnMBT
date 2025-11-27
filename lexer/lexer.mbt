/// 将字符的 ASCII 码转换为对应的数字值
/// 
/// 参数：
/// - ch: 字符的 ASCII 码（48-57 对应 '0'-'9'）
/// 
/// 返回：对应的数字值（0-9）
fn char_to_digit(ch: Int) -> Int {
  match ch {
    48 => 0  // '0'
    49 => 1  // '1'
    50 => 2  // '2'
    51 => 3  // '3'
    52 => 4  // '4'
    53 => 5  // '5'
    54 => 6  // '6'
    55 => 7  // '7'
    56 => 8  // '8'
    57 => 9  // '9'
    _ => 0   // 不应该发生，因为我们已经验证过是数字
  }
}

/// 获取字符的 ASCII 码
/// 
/// 参数：
/// - ch: 字符（'0'-'9'）
/// 
/// 返回：对应的 ASCII 码（48-57）
fn char_code(ch: Char) -> Int {
  match ch {
    '0' => 48
    '1' => 49
    '2' => 50
    '3' => 51
    '4' => 52
    '5' => 53
    '6' => 54
    '7' => 55
    '8' => 56
    '9' => 57
    _ => 0  // 不应该发生，因为我们已经验证过是数字
  }
}


/// 词法分析错误类型
pub(all) suberror TokenizeError String derive(Show)

/// 关键字枚举
/// 
/// 包含 MiniMoonBit 语言的所有关键字
pub(all) enum Keyword {
  Fn      // 函数定义
  Struct  // 结构体定义
  Enum    // 枚举定义
  Let     // 变量绑定
  Mut     // 可变变量
  If      // 条件语句
  Else    // else 分支
  While   // 循环语句
  For     // for 循环
  Return  // 返回语句
  Match   // 模式匹配
} derive(Show, Eq)

/// 二元运算符枚举
/// 
/// 包含所有支持的二元运算符，分为以下几类：
/// - 算术运算符：+, -, *, /, %
/// - 位运算符：<<, >>, &, |
/// - 比较运算符：==, !=, <, >, <=, >=
/// - 逻辑运算符：&&, ||
pub(all) enum BinaryOp {
  Add        // + 加法
  Sub        // - 减法
  Mul        // * 乘法
  Div        // / 除法
  Mod        // % 取模
  ShiftLeft  // << 左移
  ShiftRight // >> 右移
  Eq         // == 等于
  NE         // != 不等于
  LT         // < 小于
  GT         // > 大于
  LE         // <= 小于等于
  GE         // >= 大于等于
  And        // && 逻辑与
  Or         // || 逻辑或
  BitAnd     // & 按位与
  BitOr      // | 按位或
} derive(Eq)

///|
pub impl Show for BinaryOp with output(self, logger) {
  let s = match self {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
    Mod => "%"
    ShiftLeft => "<<"
    ShiftRight => ">>"
    Eq => "=="
    NE => "!="
    LT => "<"
    GT => ">"
    LE => "<="
    GE => ">="
    And => "&&"
    Or => "||"
    BitAnd => "&"
    BitOr => "|"
  }
  logger.write_string(s)
}

/// 赋值运算符枚举
/// 
/// 包含所有支持的赋值运算符
pub(all) enum AssignOp {
  Assign      // = 赋值
  PlusAssign  // += 加法赋值
  MinusAssign // -= 减法赋值
  MultAssign  // *= 乘法赋值
  DivAssign   // /= 除法赋值
  ModAssign   // %= 取模赋值
} derive(Show, Eq, ToJson)

/// Token 结构体
/// 
/// 表示词法分析产生的一个 token
/// 包含 token 的类型信息
pub struct Token {
  kind : TokenKind  // Token 的类型
  // 可以扩展添加位置信息等
} derive(Show, Eq)

/// 创建新的 Token
/// 
/// 参数：
/// - kind: Token 的类型
/// 
/// 返回：新创建的 Token
pub fn Token::new(kind : TokenKind) -> Token {
  Token::{ kind, }
}

/// Token 类型枚举
/// 
/// 定义了所有可能的 token 类型，包括：
/// - 字面量：Bool, Int, Double, String
/// - 标识符：Ident
/// - 关键字：Keyword
/// - 运算符：BinaryOp, AssignOp, UnaryOp
/// - 分隔符：LParen, RParen, LBrace, RBrace, 等
pub(all) enum TokenKind {
  Bool(Bool)     // 布尔字面量：true, false
  Int(Int)       // 整数字面量：1, 42, -100
  Double(Double) // 浮点数字面量：3.14, -0.5
  String(String) // "hello", "world"
  Keyword(Keyword)
  Upper(String)
  Lower(String)
  BinaryOp(BinaryOp) // +, -, *, /, %, =, ==, !=, <, >, <=, >=, &&, ||
  AssignOp(AssignOp) // =, +=, -=, *=, /=, %=
  Not // !
  Bracket(Char) // (, ), [, ], {, }
  Symbol(String) // . , ; : :: -> => 
  Wildcard // _
  EOF
} derive(Show, Eq)

///|
// String builder is built into MoonBit's standard library

///|
pub fn tokenize(code : String) -> Array[Token] raise TokenizeError {
  println("tokenize: starting");
  let tokens : Array[Token] = Array::new()
  let mut view = skip_trivia(code[:])
  
  // Use while loop instead of recursion to avoid stack overflow on large files
  while view.length() > 0 {
    view = tokenize_one_token(view, tokens)
  }
  
  tokens.push(Token::new(EOF))
  tokens
}

///|
fn tokenize_one_token(view : StringView, tokens : Array[Token]) -> StringView raise TokenizeError {
  match view {
    [] => view  // Return empty view, will exit loop
    [.."//", ..rest] => skip_trivia(skip_line_comment(rest))
    [.."::", ..rest] => tokenize_with_token(Symbol("::"), rest, tokens)
    [.."->", ..rest] => tokenize_with_token(Symbol("->"), rest, tokens)
    [.."=>", ..rest] => tokenize_with_token(Symbol("=>"), rest, tokens)
    [.."+=", ..rest] => tokenize_with_token(AssignOp(AssignOp::PlusAssign), rest, tokens)
    [.."-=", ..rest] => tokenize_with_token(AssignOp(AssignOp::MinusAssign), rest, tokens)
    [.."*=", ..rest] => tokenize_with_token(AssignOp(AssignOp::MultAssign), rest, tokens)
    [.."/=", ..rest] => tokenize_with_token(AssignOp(AssignOp::DivAssign), rest, tokens)
    [.."%=", ..rest] => tokenize_with_token(AssignOp(AssignOp::ModAssign), rest, tokens)
    [.."==", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Eq), rest, tokens)
    [.."!=", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::NE), rest, tokens)
    [.."<=", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::LE), rest, tokens)
    [..">=", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::GE), rest, tokens)
    [.."&&", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::And), rest, tokens)
    [.."||", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Or), rest, tokens)
    [.."<<", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::ShiftLeft), rest, tokens)
    [..">>", ..rest] => tokenize_with_token(BinaryOp(BinaryOp::ShiftRight), rest, tokens)
    ['(', ..rest] => tokenize_with_token(Bracket('('), rest, tokens)
    [')', ..rest] => tokenize_with_token(Bracket(')'), rest, tokens)
    ['[', ..rest] => tokenize_with_token(Bracket('['), rest, tokens)
    [']', ..rest] => tokenize_with_token(Bracket(']'), rest, tokens)
    ['{', ..rest] => tokenize_with_token(Bracket('{'), rest, tokens)
    ['}', ..rest] => tokenize_with_token(Bracket('}'), rest, tokens)
    ['.', ..rest] => tokenize_with_token(Symbol("."), rest, tokens)
    [',', ..rest] => tokenize_with_token(Symbol(","), rest, tokens)
    [':', ..rest] => tokenize_with_token(Symbol(":"), rest, tokens)
    [';', ..rest] => tokenize_with_token(Symbol(";"), rest, tokens)
    ['+', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Add), rest, tokens)
    ['-', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Sub), rest, tokens)
    ['*', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Mul), rest, tokens)
    ['/', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Div), rest, tokens)
    ['%', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::Mod), rest, tokens)
    ['=', ..rest] => tokenize_with_token(AssignOp(AssignOp::Assign), rest, tokens)
    ['<', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::LT), rest, tokens)
    ['>', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::GT), rest, tokens)
    ['&', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::BitAnd), rest, tokens)
    ['|', ..rest] => tokenize_with_token(BinaryOp(BinaryOp::BitOr), rest, tokens)
    ['!', ..rest] => tokenize_with_token(Not, rest, tokens)
    ['_', ..rest] => {
      // Check if this is part of an identifier (e.g., _var) or a standalone underscore
      match rest {
        [next, ..] if is_identifier_continue(next) => {
          // It's part of an identifier, consume it as an identifier
          let (ident, rest_after_ident) = consume_identifier('_', rest)
          tokens.push(Token::new(classify_identifier(ident, false)))
          skip_trivia(rest_after_ident)
        }
        _ => tokenize_with_token(Wildcard, rest, tokens)
      }
    }
    ['"', ..rest] => {
      let (str_lit, rest_after_str) = consume_string_literal(rest, false, StringBuilder::new())
      tokens.push(Token::new(String(str_lit)))
      skip_trivia(rest_after_str)
    }
    ['0'..='9', ..] => {
      // First consume the integer part
      let (int_part, rest_after_int) = consume_digits(view)
      
      // Check if there's a decimal point
      match rest_after_int {
        ['.', next, ..next_rest] => {
          // We have a floating point number
          // Check if there are digits after the decimal point
          if is_digit(next) {
            // Handle numbers like 3.14
            let (frac_part, rest_after_frac) = consume_digits(next_rest)
            
            // Build the complete number string
            let mut num_str = ""
            for i = 0; i < int_part.length(); i = i + 1 {
              num_str = num_str + int_part.get(i).unwrap().unsafe_to_char().to_string()
            }
            num_str = num_str + "."
            num_str = num_str + next.to_string()
            for i = 0; i < frac_part.length(); i = i + 1 {
              num_str = num_str + frac_part.get(i).unwrap().unsafe_to_char().to_string()
            }
            
            // Use parse_double for accurate conversion
            let value = try {
              @strconv.parse_double(num_str)
            } catch {
              _ => raise TokenizeError("Invalid float number: " + num_str)
            }
            
            tokens.push(Token::new(Double(value)))
            skip_trivia(rest_after_frac)
          } else {
            // Handle case like "42." (no digits after decimal point)
            let mut int_val = 0
            for i = 0; i < int_part.length(); i = i + 1 {
              let ch = int_part.get(i).unwrap()
              int_val = int_val * 10 + char_to_digit(ch)
            }
            tokens.push(Token::new(Double(int_val.to_double())))
            skip_trivia(next_rest)
          }
        }
        _ => {
          // It's just an integer
          if int_part == "" {
            raise TokenizeError("Invalid number format")
          }
          // Convert string to integer
          let mut value = 0
          for i = 0; i < int_part.length(); i = i + 1 {
            let ch = int_part.get(i).unwrap()
            value = value * 10 + char_to_digit(ch)
          }
          tokens.push(Token::new(Int(value)))
          skip_trivia(rest_after_int)
        }
      }
    }
    [ch, ..rest] if ch == '\'' => {
      // Handle character codes
      match rest {
        [next_ch, '\'', ..rest2] => {
          tokens.push(Token::new(Int(char_code(next_ch))))
          skip_trivia(rest2)
        }
        _ => raise TokenizeError("Invalid character code")
      }
    }
    [first, ..rest] if is_identifier_start(first) => {
      let (ident, rest_after_ident) = consume_identifier(first, rest)
      // Only pass is_upper as true if the first character is an uppercase letter
      let is_upper = first != '_' && is_upper_ascii(first)
      tokens.push(Token::new(classify_identifier(ident, is_upper)))
      skip_trivia(rest_after_ident)
    }
    [ch, ..] => raise TokenizeError("Unexpected character: " + ch.to_string())
  }
}

///|
fn tokenize_with_token(kind : TokenKind, rest : StringView, tokens : Array[Token]) -> StringView {
  tokens.push(Token::new(kind))
  skip_trivia(rest)
}

///|
fn skip_trivia(view : StringView) -> StringView {
  match view {
    [' ' | '\n' | '\t' | '\r', ..rest] => skip_trivia(rest)
    ['/', '/', ..rest] => skip_trivia(skip_line_comment(rest))
    _ => view
  }
}

///|
fn skip_line_comment(view : StringView) -> StringView {
  match view {
    ['\n', ..rest] => rest
    [] => []
    [_, ..rest] => skip_line_comment(rest)
  }
}

///|
fn consume_identifier_loop(acc: StringBuilder, remaining: StringView) -> (StringBuilder, StringView) {
  match remaining {
    [ch, ..next] => {
      if is_identifier_continue(ch) {
        acc.write_char(ch)
        consume_identifier_loop(acc, next)
      } else {
        (acc, remaining)
      }
    }
    _ => (acc, remaining)
  }
}

fn consume_identifier(first : Char, rest : StringView) -> (String, StringView) {
  let acc = StringBuilder::new()
  acc.write_char(first)
  let (result, remaining) = consume_identifier_loop(acc, rest)
  (result.to_string(), remaining)
}

///|
fn consume_digits_loop(acc: StringBuilder, remaining: StringView) -> (StringBuilder, StringView) {
  match remaining {
    [next_ch, ..next_rest] => {
      if is_digit(next_ch) {
        acc.write_char(next_ch)
        consume_digits_loop(acc, next_rest)
      } else {
        (acc, remaining)
      }
    }
    _ => (acc, remaining)
  }
}

fn consume_digits(view : StringView) -> (String, StringView) {
  match view {
    [ch, ..rest] => {
      if is_digit(ch) {
        let acc = StringBuilder::new()
        acc.write_char(ch)
        let (result, remaining) = consume_digits_loop(acc, rest)
        (result.to_string(), remaining)
      } else {
        ("", view)
      }
    }
    _ => ("", view)
  }
}

///|
fn classify_identifier(ident : String, is_upper : Bool) -> TokenKind {
  if ident == "_" {
    Wildcard
  } else if is_upper {
    Upper(ident)
  } else {
    match ident {
      "fn" => Keyword(Keyword::Fn)
      "struct" => Keyword(Keyword::Struct)
      "enum" => Keyword(Keyword::Enum)
      "let" => Keyword(Keyword::Let)
      "mut" => Keyword(Keyword::Mut)
      "if" => Keyword(Keyword::If)
      "else" => Keyword(Keyword::Else)
      "while" => Keyword(Keyword::While)
      "for" => Keyword(Keyword::For)
      "return" => Keyword(Keyword::Return)
      "match" => Keyword(Keyword::Match)
      _ => Lower(ident)
    }
  }
}

///|
fn is_identifier_start(ch : Char) -> Bool {
  is_upper_ascii(ch) || is_lower_ascii(ch) || ch == '_'
}

///|
fn is_identifier_continue(ch : Char) -> Bool {
  is_identifier_start(ch) || is_digit(ch)
}

///|
fn is_upper_ascii(ch : Char) -> Bool {
  'A' <= ch && ch <= 'Z'
}

///|
fn is_lower_ascii(ch : Char) -> Bool {
  'a' <= ch && ch <= 'z'
}

///|
fn is_digit(ch : Char) -> Bool {
  '0' <= ch && ch <= '9'
}

///|
fn consume_string_literal(remaining: StringView, in_escape: Bool, acc: StringBuilder) -> (String, StringView) raise TokenizeError {
  match remaining {
    // End of string literal
    ['"', ..rest] if !in_escape => (acc.to_string(), rest)
    
    // Handle escape sequences
    ['\\', ..rest] if !in_escape => consume_string_literal(rest, true, acc)
    ['n', ..rest] if in_escape => {
      acc.write_char('\n')
      consume_string_literal(rest, false, acc)
    }
    ['t', ..rest] if in_escape => {
      acc.write_char('\t')
      consume_string_literal(rest, false, acc)
    }
    ['r', ..rest] if in_escape => {
      acc.write_char('\r')
      consume_string_literal(rest, false, acc)
    }
    ['"', ..rest] if in_escape => {
      acc.write_char('"')
      consume_string_literal(rest, false, acc)
    }
    ['\\', ..rest] if in_escape => {
      acc.write_char('\\')
      consume_string_literal(rest, false, acc)
    }
    
    // Normal character
    [ch, ..rest] => {
      if in_escape {
        raise TokenizeError("Invalid escape sequence: \\\"" + ch.to_string() + "\"")
      }
      acc.write_char(ch)
      consume_string_literal(rest, false, acc)
    }
    
    // Unterminated string
    [] => raise TokenizeError("Unterminated string literal")
  }
}
