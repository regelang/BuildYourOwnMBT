///|
pub(all) struct Param {
  name : String
  ty : Type
} derive(Show, Eq)

///|
pub(all) struct TopFunction {
  fname : String
  type_params : Array[String] // Generic type parameters like ["T", "U"] in fn[T, U]
  param_list : Array[Param]
  ret_ty : Type
  body : BlockExpr
} derive(Show, Eq)

///|
pub fn parse_param(
  tokens: ArrayView[Token],
) -> (Param, ArrayView[Token]) raise ParseError {
  if tokens.length() < 3 {
    raise ParseError("Incomplete parameter definition")
  }

  // Parse parameter name
  let name_token = tokens[0]
  let name = match name_token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name
    _ => raise ParseError("Expected parameter name")
  }

  // Expect colon after parameter name
  if tokens[1].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
    raise ParseError("Expected ':' after parameter name")
  }

  // Parse parameter type
  let (ty, rest) = parse_type(tokens[2:])
  ({ name, ty }, rest)
}

/// Helper function to parse a comma-separated list of parameters
fn parse_param_list(
  tokens: ArrayView[Token],
) -> (Array[Param], ArrayView[Token]) raise ParseError {
  let mut params = []
  let mut current_tokens = tokens
  
  while current_tokens.length() > 0 {
    // Check for closing parenthesis
    if current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
      break
    }
    
    // Parse parameter
    let (param, rest) = parse_param(current_tokens)
    params = params + [param]
    current_tokens = rest
    
    // Check for comma
    if current_tokens.length() > 0 && 
       current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
      current_tokens = current_tokens[1:]
    }
  }
  
  (params, current_tokens)
}

///|
pub fn parse_top_function(
  tokens: ArrayView[Token],
) -> (TopFunction, ArrayView[Token]) raise ParseError {
  println("parse_top_function: starting");
  if tokens.length() < 3 {
    raise ParseError("Incomplete function definition")
  }

  // Parse 'fn' keyword
  if tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Fn) {
    raise ParseError("Expected 'fn' keyword at start of function")
  }

  // Check for optional generic type parameters: fn[T, U, ...]
  let mut current_pos = 1
  let type_params = if tokens.length() > current_pos && 
                      tokens[current_pos].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') {
    let (params, rest) = parse_function_type_params(tokens[current_pos:])
    current_pos = tokens.length() - rest.length()
    params
  } else {
    []  // No type parameters
  }

  // Parse function name
  if tokens.length() <= current_pos {
    raise ParseError("Expected function name")
  }
  let name_token = tokens[current_pos]
  let fname = match name_token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name
    _ => raise ParseError("Expected function name")
  }
  current_pos = current_pos + 1

  // Check if this is the main function
  let (param_list, after_params, ret_ty) = if fname == "main" {
    // For main function, expect no parameters and no return type
    if tokens.length() <= current_pos || 
       tokens[current_pos].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
      raise ParseError("Expected '{' after 'main'")
    }
    let empty_params: Array[Param] = []
    let unit_type: Type = { kind: TypeKind::Unit }
    (empty_params, tokens[current_pos:], unit_type)
  } else {
    // For regular functions, parse parameters and return type
    let (params, after_params) = if tokens.length() > current_pos && 
                                     tokens[current_pos].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') {
      // Traditional parenthesized parameter list
      let (params, after_params) = parse_param_list(tokens[current_pos + 1:])

      // Expect ')' after parameters
      if after_params.length() == 0 || 
         after_params[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
        raise ParseError("Expected ')' after parameter list")
      }
      
      (params, after_params[1:])
    } else if tokens.length() > current_pos && 
              tokens[current_pos].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("->") {
      // No parameters, just return type
      let empty_params: Array[Param] = []
      (empty_params, tokens[current_pos:])
    } else {
      // Parse parameter list without parentheses (similar to local functions)
      let mut params = []
      let mut current_tokens = tokens[current_pos:]
      
      while current_tokens.length() > 0 {
        // Check for arrow or opening brace
        match current_tokens[0].kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("->") => break
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') => break
          _ => {
            // Parse parameter
            let (param, rest) = parse_param(current_tokens)
            params = params + [param]
            current_tokens = rest
            
            // Check for comma (optional)
            if current_tokens.length() > 0 && 
               current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
              current_tokens = current_tokens[1:]
            }
          }
        }
      }
      
      (params, current_tokens)
    }

    // Expect '->' and return type (optional for Unit return type)
    let (ret_ty, after_ret_ty) = if after_params.length() > 0 && 
        after_params[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("->") {
      // Parse return type
      let (ty, rest) = parse_type(after_params[1:])
      (ty, rest)
    } else {
      // Default to Unit type if no return type specified
      let unit_type: Type = { kind: TypeKind::Unit }
      (unit_type, after_params)
    }
    (params, after_ret_ty, ret_ty)
  }

  // Parse function body
  let (body, rest) = parse_block_expr(after_params)

  ({ fname, type_params, param_list, ret_ty, body }, rest)
}

/// 解析函数的泛型类型参数列表
/// 
/// 语法：[T, U, V]
fn parse_function_type_params(
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
