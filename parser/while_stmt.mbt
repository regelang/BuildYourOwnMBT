///|
pub(all) struct WhileStmt {
  cond : Expr
  body : BlockExpr
} derive(Show, Eq)

///|
pub fn parse_while_stmt(
  tokens : ArrayView[Token],
) -> (WhileStmt, ArrayView[Token]) raise ParseError {
  parse_while_stmt_with_depth(tokens, 0)
}

///|
pub fn parse_while_stmt_with_depth(
  tokens : ArrayView[Token],
  depth : Int
) -> (WhileStmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing while statement")
  }

  let first_token = tokens[0]
  if first_token.kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::While) {
    raise ParseError("Expected 'while' keyword at start of while statement")
  }

  // Skip the 'while' keyword
  let after_while = tokens[1:]

  // Parse the condition expression
  let (cond, after_cond) = parse_expr_with_depth(after_while, depth + 1)

  // Parse the loop body
  let (body, after_body) = parse_block_expr_with_depth(after_cond, depth + 1)

  ({ cond, body }, after_body)
}
