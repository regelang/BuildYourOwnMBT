///|
pub(all) struct IfExpr {
  cond : Expr
  then_block : BlockExpr
  else_block : Either[IfExpr, BlockExpr]?
} derive(Show, Eq)

///|
pub fn parse_if_expr(
  tokens : ArrayView[Token],
) -> (IfExpr, ArrayView[Token]) raise ParseError {
  parse_if_expr_with_depth(tokens, 0)
}

/// Parse an if expression with recursion depth tracking
pub fn parse_if_expr_with_depth(
  tokens : ArrayView[Token],
  depth : Int,
) -> (IfExpr, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing if expression")
  }

  let first_token = tokens[0]
  if first_token.kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) {
    raise ParseError("Expected 'if' keyword at start of if expression")
  }

  // Skip the 'if' keyword
  let after_if = tokens[1:]

  // Parse the condition expression
  let (cond, after_cond) = parse_expr_with_depth(after_if, depth + 1)

  // Parse the then block
  let (then_block, after_then) = parse_block_expr_with_depth(after_cond, depth)

  // Check for optional else block
  let (else_block, final_tokens) = if after_then.length() > 0 && 
                     after_then[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Else) {
    // Skip the 'else' keyword
    let after_else = after_then[1:]
    
    if after_else.length() == 0 {
      raise ParseError("Unexpected end of input after 'else'")
    }
    
    // Check what comes after 'else'
    match after_else[0].kind {
      // 'else if' - recursively parse another if expression
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) => {
        let (else_if_expr, final_tokens) = parse_if_expr_with_depth(after_else, depth + 1)
        (Some(Left(else_if_expr)), final_tokens)
      }
      // 'else { ... }' - parse a block expression
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') => {
        let (else_block_expr, final_tokens) = parse_block_expr_with_depth(after_else, depth)
        (Some(Right(else_block_expr)), final_tokens)
      }
      _ => {
        raise ParseError("Expected 'if' or '{' after 'else'")
      }
    }
  } else {
    // No else block
    (None, after_then)
  }

  ({ cond, then_block, else_block }, final_tokens)
}
