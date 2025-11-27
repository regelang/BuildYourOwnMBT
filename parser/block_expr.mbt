///|
pub(all) struct BlockExpr {
  stmts : Array[Stmt]
} derive(Show, Eq)

///|
pub fn parse_block_expr(
  tokens : ArrayView[Token],
) -> (BlockExpr, ArrayView[Token]) raise ParseError {
  parse_block_expr_with_depth(tokens, 0)
}

///|
fn parse_simple_block_expr_with_depth(
  tokens : ArrayView[Token],
  depth : Int
) -> (BlockExpr, ArrayView[Token]) raise ParseError {
  // Simple version for deep recursion - just parse basic block structure
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing simple block expression")
  }

  let first_token = tokens[0]
  if first_token.kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    raise ParseError("Expected '{' at start of simple block expression")
  }

  // Skip the opening brace
  let after_open = tokens[1:]
  
  // Parse statements until we hit the closing brace
  let statements : Array[Stmt] = []
  let mut current_tokens = after_open

  while current_tokens.length() > 0 {
    // Check for closing brace
    match current_tokens[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') => {
        // Found closing brace - we're done
        let final_tokens = current_tokens[1:]
        return ({ stmts: statements }, final_tokens)
      }
      _ => {
        // Parse statement with current depth (don't increase depth further)
        let (stmt, rest) = parse_stmt_with_depth(current_tokens, depth)
        statements.push(stmt)
        current_tokens = rest
      }
    }
  }
  
  // If we reach here, we never found the closing brace
  raise ParseError("Expected '}' at end of simple block expression")
}

///|
fn parse_block_expr_with_depth(
  tokens : ArrayView[Token],
  depth : Int
) -> (BlockExpr, ArrayView[Token]) raise ParseError {
  // Prevent infinite recursion by limiting depth
  if depth > 5 {
    // Use simple parsing for deep recursion
    return parse_simple_block_expr_with_depth(tokens, depth)
  }

  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing block expression")
  }

  let first_token = tokens[0]
  if first_token.kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    raise ParseError("Expected '{' at start of block expression")
  }

  // Skip the opening brace
  let after_open = tokens[1:]
  
  // Parse statements until we hit the closing brace
  let statements : Array[Stmt] = []
  let mut current_tokens = after_open

  while current_tokens.length() > 0 {
    // Check for closing brace
    match current_tokens[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') => {
        // Found closing brace - we're done
        let final_tokens = current_tokens[1:]
        return ({ stmts: statements }, final_tokens)
      }
      _ => {
        // Parse statement with increased depth
        let (stmt, rest) = parse_stmt_with_depth(current_tokens, depth + 1)
        statements.push(stmt)
        current_tokens = rest
      }
    }
  }
  
  // If we reach here, we never found the closing brace
  raise ParseError("Expected '}' at end of block expression")
}
