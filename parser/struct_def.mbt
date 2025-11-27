///|
pub(all) struct StructDef {
  name : String
  type_params : Array[String]      // 泛型类型参数列表（如 ["T"]）
  fields : Array[StructField]
} derive(Show, Eq)

///|
pub(all) struct StructField {
  name : String
  is_mut : Bool
  ty : Type
} derive(Show, Eq)

///|
pub fn parse_struct_field(
  tokens : ArrayView[Token],
) -> (StructField, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing struct field")
  }
  
  // Parse optional 'mut' keyword
  let (is_mut, rest) = if tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@moonbitlang/MiniMoonbit/lexer.Keyword::Mut) {
    (true, tokens[1:])
  } else {
    (false, tokens)
  }
  
  // Parse field name
  if rest.length() == 0 {
    raise ParseError("Expected field name")
  }
  
  let field_name = match rest[0].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name
    _ => raise ParseError("Expected field name (lowercase identifier)")
  }
  
  // Parse colon
  if rest.length() < 2 || rest[1].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
    raise ParseError("Expected ':' after field name")
  }
  
  // Parse field type
  if rest.length() < 3 {
    raise ParseError("Expected type after ':'")
  }
  
  let (field_type, after_type) = parse_type(rest[2:])
  
  // Return the field and remaining tokens
  ({
    name: field_name,
    is_mut: is_mut,
    ty: field_type
  }, after_type)
}

///|
pub fn parse_struct_def(
  tokens : ArrayView[Token],
) -> (StructDef, ArrayView[Token]) raise ParseError {
  // Parse 'struct' keyword
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@moonbitlang/MiniMoonbit/lexer.Keyword::Struct) {
    raise ParseError("Expected 'struct' keyword")
  }
  
  // Parse struct name (must be an uppercase identifier)
  if tokens.length() < 2 {
    raise ParseError("Expected struct name after 'struct'")
  }
  
  let struct_name = match tokens[1].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
    _ => raise ParseError("Expected struct name (uppercase identifier)")
  }
  
  // Parse optional type parameter: [T, U, ...]
  let mut next_idx = 2
  let type_params = if tokens.length() > next_idx && tokens[next_idx].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') {
    let (params, rest) = parse_struct_type_params(tokens[next_idx:])
    next_idx = tokens.length() - rest.length()
    params
  } else {
    []  // No type parameters
  }
  
  // Parse opening '{'
  if tokens.length() <= next_idx || tokens[next_idx].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    raise ParseError("Expected '{' after struct name")
  }
  
  let mut fields: Array[StructField] = []
  let mut current_tokens = tokens[next_idx + 1:]
  
  // Parse fields until we hit the closing '}'
  while current_tokens.length() > 0 {
    // Check for closing '}'
    if current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') {
      return ({
        name: struct_name,
        type_params: type_params,  // Include type parameters
        fields: fields
      }, current_tokens[1:])
    }
    
    // Skip semicolons between fields
    if current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
      current_tokens = current_tokens[1:]
      continue
    }
    
    // Parse a field
    let (field, rest) = parse_struct_field(current_tokens)
    fields = fields + [field]
    current_tokens = rest
    
    // Skip optional semicolon after field
    if current_tokens.length() > 0 && current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
      current_tokens = current_tokens[1:]
    }
  }
  
  // If we get here, we reached the end of input without finding a closing '}'
  raise ParseError("Expected '}' at end of struct definition")
}

/// 解析结构体的泛型类型参数列表
/// 
/// 语法：[T, U, V]
fn parse_struct_type_params(
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
