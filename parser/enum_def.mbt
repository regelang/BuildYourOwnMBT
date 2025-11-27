/// 枚举定义
pub(all) struct EnumDef {
  name : String                    // 枚举名称
  type_params : Array[String]      // 泛型类型参数列表（如 ["T"]）
  variants : Array[EnumVariant]    // 变体列表
} derive(Show, Eq)

/// 枚举变体
pub(all) struct EnumVariant {
  name : String                    // 变体名称
  params : Array[Type]             // 参数类型列表（空数组表示无参数）
} derive(Show, Eq)

/// 解析枚举定义
/// 
/// 语法：
/// enum Color {
///   Red;
///   Green;
///   RGB(Int, Int, Int);
/// }
/// 
/// 泛型语法：
/// enum List[T] {
///   Nil;
///   Cons(T, List[T]);
/// }
pub fn parse_enum_def(
  tokens : ArrayView[Token]
) -> (EnumDef, ArrayView[Token]) raise ParseError {
  // 期望 'enum' 关键字
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(
    @moonbitlang/MiniMoonbit/lexer.Keyword::Enum,
  ) {
    raise ParseError("Expected 'enum' keyword")
  }
  
  // 解析枚举名称（大写标识符）
  if tokens.length() < 2 {
    raise ParseError("Expected enum name after 'enum'")
  }
  
  let enum_name = match tokens[1].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
    _ => raise ParseError("Expected enum name (uppercase identifier)")
  }
  
  // 解析可选的泛型类型参数：[T, U, ...]
  let mut current_pos = 2
  let type_params = if tokens.length() > current_pos && 
                     tokens[current_pos].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '[',
  ) {
    let (params, rest) = parse_enum_type_params(tokens[current_pos:])
    current_pos = tokens.length() - rest.length()
    params
  } else {
    []  // No type parameters
  }
  
  // 期望 '{'
  if tokens.length() <= current_pos || tokens[current_pos].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '{',
  ) {
    raise ParseError("Expected '{' after enum name")
  }
  
  // 解析变体列表
  let (variants, rest) = parse_enum_variants(tokens[current_pos + 1:])
  
  // 期望 '}'
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '}',
  ) {
    raise ParseError("Expected '}' at end of enum definition")
  }
  
  (EnumDef::{ name: enum_name, type_params: type_params, variants }, rest[1:])
}

/// 解析枚举的泛型类型参数列表
/// 
/// 语法：[T, U, V]
fn parse_enum_type_params(
  tokens : ArrayView[Token]
) -> (Array[String], ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '[',
  ) {
    raise ParseError("Expected '[' to start type parameter list")
  }
  
  let params : Array[String] = []
  let mut rest = tokens[1:]
  
  // 解析参数直到遇到 ']'
  while rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    ']',
  ) {
    // 解析类型参数名称（大写标识符）
    if rest.length() == 0 {
      raise ParseError("Expected type parameter name")
    }
    
    let param_name = match rest[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
      _ => raise ParseError("Expected type parameter name (uppercase identifier)")
    }
    
    params.push(param_name)
    rest = rest[1:]
    
    // 检查是否有逗号
    if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
      ",",
    ) {
      rest = rest[1:]
    } else if rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
      ']',
    ) {
      raise ParseError("Expected ',' or ']' in type parameter list")
    }
  }
  
  // 期望 ']'
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    ']',
  ) {
    raise ParseError("Expected ']' after type parameter list")
  }
  
  (params, rest[1:])
}

/// 解析枚举变体列表
fn parse_enum_variants(
  tokens : ArrayView[Token]
) -> (Array[EnumVariant], ArrayView[Token]) raise ParseError {
  let variants : Array[EnumVariant] = []
  let mut rest = tokens
  
  // 解析变体直到遇到 '}'
  while rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '}',
  ) {
    let (variant, after_variant) = parse_enum_variant(rest)
    variants.push(variant)
    rest = after_variant
  }
  
  (variants, rest)
}

/// 解析单个枚举变体
/// 
/// 语法：
/// Red;
/// RGB(Int, Int, Int);
fn parse_enum_variant(
  tokens : ArrayView[Token]
) -> (EnumVariant, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Expected enum variant")
  }
  
  // 解析变体名称（大写标识符）
  let variant_name = match tokens[0].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
    _ => raise ParseError("Expected variant name (uppercase identifier)")
  }
  
  // 检查是否有参数
  if tokens.length() > 1 && tokens[1].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '(',
  ) {
    // 带参数的变体
    let (params, rest) = parse_variant_params(tokens[2:])
    
    // 分号是可选的（特别是在最后一个变体后）
    if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
      ";",
    ) {
      (EnumVariant::{ name: variant_name, params }, rest[1:])
    } else {
      (EnumVariant::{ name: variant_name, params }, rest)
    }
  } else {
    // 无参数的变体
    // 分号是可选的
    if tokens.length() > 1 && tokens[1].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
      ";",
    ) {
      (EnumVariant::{ name: variant_name, params: [] }, tokens[2:])
    } else {
      (EnumVariant::{ name: variant_name, params: [] }, tokens[1:])
    }
  }
}

/// 解析变体参数列表
/// 
/// 语法：Int, Int, Int)
fn parse_variant_params(
  tokens : ArrayView[Token]
) -> (Array[Type], ArrayView[Token]) raise ParseError {
  let params : Array[Type] = []
  let mut rest = tokens
  
  // 解析参数直到遇到 ')'
  while rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    ')',
  ) {
    // 解析类型
    let (param_type, after_type) = parse_type(rest)
    params.push(param_type)
    rest = after_type
    
    // 检查是否有逗号
    if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
      ",",
    ) {
      rest = rest[1:]
    } else if rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
      ')',
    ) {
      raise ParseError("Expected ',' or ')' in variant parameters")
    }
  }
  
  // 期望 ')'
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    ')',
  ) {
    raise ParseError("Expected ')' after variant parameters")
  }
  
  (params, rest[1:])
}
