///|
pub(all) struct Pattern {
  kind : PatternKind
} derive(Show, Eq)

///|
pub(all) enum PatternKind {
  Wildcard
  Ident(String)
  Tuple(Array[Pattern])
  Constructor(String, Array[Pattern])  // 枚举构造器模式：Red 或 RGB(r, g, b)
} derive(Show, Eq)

///|
pub fn parse_pattern(
  tokens : ArrayView[Token],
) -> (Pattern, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing pattern")
  }

  let token = tokens[0]
  let rest = tokens[1:]

  // Use match statement for proper pattern matching
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Wildcard => {
      // Wildcard pattern
      let pattern : Pattern = { kind: PatternKind::Wildcard }
      (pattern, rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => {
      // Identifier pattern (lowercase)
      let pattern : Pattern = { kind: PatternKind::Ident(name) }
      (pattern, rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => {
      // Constructor pattern (uppercase): Red or EnumName::Variant or RGB(...) or EnumName::RGB(...)
      // Check for double colon syntax: EnumName::Variant
      if rest.length() > 1 {
        match rest[0].kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") => {
            match rest[1].kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(_) => {
                // Parse variant name
                let variant : String = match rest[1].kind {
                  @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(v) => v
                  _ => raise ParseError("Expected uppercase identifier after ::")
                }
                
                let rest_after_colon : ArrayView[Token] = rest[2:]
                
                // Check for parameters
                 if rest_after_colon.length() > 0 {
                   match rest_after_colon[0].kind {
                     @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
                       // Constructor with parameters: EnumName::RGB(r, g, b)
                       let (params, after_params) = parse_constructor_params(rest_after_colon[1:])
                       // Combine enum name and variant name with :: separator
                       let pattern : Pattern = { kind: PatternKind::Constructor(name + "::" + variant, params) }
                       (pattern, after_params)
                     }
                     _ => {
                       // Constructor without parameters: EnumName::Red
                       let pattern : Pattern = { kind: PatternKind::Constructor(name + "::" + variant, []) }
                       (pattern, rest_after_colon)
                     }
                   }
                 } else {
                   // Constructor without parameters: EnumName::Red
                   let pattern : Pattern = { kind: PatternKind::Constructor(name + "::" + variant, []) }
                   (pattern, rest_after_colon)
                 }
              }
              _ => {
                // Not a valid enum variant, treat as regular constructor
                // Check for parameters (RGB(...))
                if rest.length() > 0 {
                  match rest[0].kind {
                    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
                       // Constructor with parameters: RGB(r, g, b)
                       let (params, after_params) = parse_constructor_params(rest[1:])
                       let pattern : Pattern = { kind: PatternKind::Constructor(name, params) }
                       (pattern, after_params)
                     }
                    _ => {
                      // Constructor without parameters: Red
                   let pattern : Pattern = { kind: PatternKind::Constructor(name, []) }
                   (pattern, rest)
                    }
                  }
                } else {
                  // Constructor without parameters: Red
            let pattern : Pattern = { kind: PatternKind::Constructor(name, []) }
            (pattern, rest)
                }
              }
            }
          }
          _ => {
            // Not a double colon, treat as regular constructor
            // Check for parameters (RGB(...))
            if rest.length() > 0 {
              match rest[0].kind {
                @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
                  // Constructor with parameters: RGB(r, g, b)
                  let (params, after_params) = parse_constructor_params(rest[1:])
                  let pattern : Pattern = { kind: PatternKind::Constructor(name, params) }
                  (pattern, after_params)
                }
                _ => {
                  // Constructor without parameters: Red
                  let pattern : Pattern = { kind: PatternKind::Constructor(name, []) }
                  (pattern, rest)
                }
              }
            } else {
              // Constructor without parameters: Red
              let pattern : Pattern = { kind: PatternKind::Constructor(name, []) }
              (pattern, rest)
            }
          }
        }
      } else {
        // Not enough tokens for double colon, treat as regular constructor
        // Constructor without parameters: Red
        let pattern : Pattern = { kind: PatternKind::Constructor(name, []) }
        (pattern, rest)
      }
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
      // Tuple pattern: (p1, p2, ...)
      parse_tuple_pattern(tokens)
    }
    _ => {
      raise ParseError("Unexpected token in pattern: \{token}")
    }
  }
}

/// Helper function to parse tuple patterns starting with '('
fn parse_tuple_pattern(
  tokens: ArrayView[Token]
) -> (Pattern, ArrayView[Token]) raise ParseError {
  // Skip the opening '('
  let after_open : ArrayView[Token] = tokens[1:]

  // Parse the first pattern
  let (first_pattern, after_first) = parse_pattern(after_open)

  // Parse remaining patterns in the tuple
  let (patterns, after_patterns) = parse_pattern_list([first_pattern], after_first)

  // Expect ')'
  if after_patterns.length() == 0 {
    raise ParseError("Expected ')' after tuple pattern")
  }
  
  match after_patterns[0].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') => {
      let after_close : ArrayView[Token] = after_patterns[1:]
      ({ kind: PatternKind::Tuple(patterns) }, after_close)
    }
    _ => {
      raise ParseError("Expected ')' after tuple pattern")
    }
  }
}

/// Helper function to parse comma-separated pattern list
fn parse_pattern_list(
  patterns: Array[Pattern],
  tokens: ArrayView[Token]
) -> (Array[Pattern], ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    return (patterns, tokens)
  }
  
  // Check if next token is comma
  let has_comma : Bool = 
    match tokens[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") => true
      _ => false
    }
  if has_comma {
    // Skip comma
    let after_comma : ArrayView[Token] = tokens[1:]

    // Check for trailing comma (end of patterns)
    if after_comma.length() > 0 {
      match after_comma[0].kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') => {
          return (patterns, after_comma)
        }
        _ => ()
      }
    }
    
    if after_comma.length() == 0 {
      raise ParseError("Unexpected end of input after comma in pattern list")
    }
    
    // Parse next pattern
    let (next_pattern, after_next) = parse_pattern(after_comma)
    parse_pattern_list(patterns + [next_pattern], after_next)
  } else {
    // No more commas, return current patterns
    (patterns, tokens)
  }
}


/// Parse constructor parameters
/// 
/// Syntax: r, g, b)
fn parse_constructor_params(tokens : ArrayView[Token]) -> (Array[Pattern], ArrayView[Token]) raise ParseError {
  let params : Array[Pattern] = []
  let mut current_tokens : ArrayView[Token] = tokens
  
  while current_tokens.length() > 0 {
    // Check for closing bracket
    let first_token = current_tokens[0]
    let is_closing_bracket : Bool = 
      match first_token.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') => true
        _ => false
      }
    
    if is_closing_bracket {
      current_tokens = current_tokens[1:]
      break
    }
    
    // Parse pattern
    let (param_pattern, after_pattern) = parse_pattern(current_tokens)
    params.push(param_pattern)
    current_tokens = after_pattern
    
    if current_tokens.length() == 0 {
      raise ParseError("Unexpected end of input in constructor parameters")
    }
    
    // Check for comma or closing bracket
    let next_token = current_tokens[0]
    match next_token.kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") => {
        current_tokens = current_tokens[1:]
      }
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') => {
        // Continue to next iteration, will break on closing bracket
        continue
      }
      _ => {
        raise ParseError("Expected ',' or ')' in constructor parameters")
      }
    }
  }
  
  (params, current_tokens)
}

///|
pub fn parse_let_binding(
  tokens : ArrayView[Token]
) -> (Stmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing let binding")
  }

  let token = tokens[0]
  let rest = tokens[1:]

  // Expect 'let' keyword
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) => {
      // Parse pattern
      let (pattern, after_pattern) = parse_pattern(rest)

      // Expect '='
      if after_pattern.length() == 0 {
        raise ParseError("Unexpected end of input after pattern in let binding")
      }
      if after_pattern[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(@lexer.AssignOp::Assign) {
        raise ParseError("Expected '=' after pattern in let binding")
      }
      let after_eq = after_pattern[1:]

      // Parse expression
      let (expr, after_expr) = parse_expr(after_eq)
      
      let let_stmt : LetStmt = { pattern, ty: None, expr }
      let stmt : Stmt = { kind: StmtKind::LetStmt(let_stmt) }
      (stmt, after_expr)
    }
    _ => {
      raise ParseError("Expected 'let' keyword in let binding")
    }
  }
}