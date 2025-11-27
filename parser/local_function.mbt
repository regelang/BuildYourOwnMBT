///|
pub(all) struct LocalFunction {
  fname : String
  param_list : Array[(String, Type?)]
  ret_ty : Type?
  body : BlockExpr
} derive(Show, Eq)

///|
pub fn parse_local_function(
  tokens : ArrayView[Token],
) -> (LocalFunction, ArrayView[Token]) raise ParseError {
  parse_local_function_with_depth(tokens, 0)
}

///|
pub fn parse_local_function_with_depth(
  tokens : ArrayView[Token],
  depth : Int
) -> (LocalFunction, ArrayView[Token]) raise ParseError {
  // Parse 'fn' keyword
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@moonbitlang/MiniMoonbit/lexer.Keyword::Fn) {
    raise ParseError("Expected 'fn' keyword in function declaration")
  }
  
  // Skip 'fn' keyword
  let mut rest = tokens[1:]
  
  // Parse function name
  if rest.length() == 0 {
    raise ParseError("Expected function name after 'fn' keyword")
  }
  
  let fname = match rest[0].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name;
    _ => raise ParseError("Expected identifier as function name")
  }
  rest = rest[1:]
  
  // Parse parameter list - handle "fn name {", "fn name(param) {", and "fn name param: Type {" formats
  let mut params: Array[(String, Type?)] = []
  
  // Check if next token is '(' (parameter list in parentheses) or parameter name (no parentheses)
  if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') {
    // Skip '('
    rest = rest[1:]
    
    // Parse parameters
    // Check for empty parameter list
    if rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
      // Parse first parameter
      if rest.length() == 0 {
        raise ParseError("Expected parameter name in function declaration")
      }
      
      // Parse parameters with optional types
      while true {
        // Parse parameter name
        if rest.length() == 0 {
          raise ParseError("Expected parameter name in function declaration")
        }
        
        let param_name = match rest[0].kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name;
          _ => raise ParseError("Expected identifier as parameter name")
        }
        rest = rest[1:]
        
        // Parse optional type annotation
        let mut param_type: Option[Type] = None
        if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
          // Skip ':'
          rest = rest[1:]
          
          // Parse type
          let (ty, new_rest) = parse_type(rest)
          param_type = Some(ty)
          rest = new_rest
        }
        
        // Add parameter to list
        params = params + [(param_name, param_type)]
        
        // Check for more parameters
        if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
          break
        }
        
        // Skip ','
        rest = rest[1:]
      }
    }
    
    // Expect ')'
    if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
      raise ParseError("Expected ')' after parameter list")
    }
    
    // Skip ')'
    rest = rest[1:]
  } else if rest.length() > 0 {
    // Check if next token is a parameter name (starts with lowercase letter)
    let is_param_name = match rest[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(_) => true;
      _ => false
    }
    if is_param_name {
    // Parameters without parentheses: fn name param1: Type1, param2: Type2 { ... }
    // Parse parameters with optional types
    while true {
      // Parse parameter name
      if rest.length() == 0 {
        raise ParseError("Expected parameter name in function declaration")
      }
      
      let param_name = match rest[0].kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name;
        _ => raise ParseError("Expected identifier as parameter name")
      }
      rest = rest[1:]
      
      // Parse optional type annotation
      let mut param_type: Option[Type] = None
      if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
        // Skip ':'
        rest = rest[1:]
        
        // Parse type
        let (ty, new_rest) = parse_type(rest)
        param_type = Some(ty)
        rest = new_rest
      }
      
      // Add parameter to list
      params = params + [(param_name, param_type)]
      
      // Check for more parameters or function body
      if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
        break
      }
      
      // Skip ','
      rest = rest[1:]
    }
    }
  } else if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    // No parameters - function body starts immediately
    // params is already empty
  } else {
    raise ParseError("Expected '(', parameter name, or '{' after function name")
  }
  
  // Parse optional return type
  let mut ret_ty: Option[Type] = None
  if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("->") {
    // Skip '->'
    rest = rest[1:]
    
    // Parse return type
    let (ty, new_rest) = parse_type(rest)
    ret_ty = Some(ty)
    rest = new_rest
  }
  
  // Parse function body (block expression) - use regular parser with depth tracking
  let (body, new_rest) = parse_block_expr_with_depth(rest, depth + 1)
  rest = new_rest
  
  // Create and return the LocalFunction
  ({
    fname: fname,
    param_list: params,
    ret_ty: ret_ty,
    body: body
  }, rest)
}