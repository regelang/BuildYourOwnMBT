///|
pub(all) struct LetStmt {
  pattern : Pattern
  ty : Type?
  expr : Expr
} derive(Show, Eq)

///|
pub fn parse_let_stmt(
  tokens : ArrayView[Token],
) -> (LetStmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing let statement")
  }

  // Expect "let" keyword
  let token = tokens[0]
  let rest = tokens[1:]
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) => {
      // Parse pattern
      let (pattern, after_pattern) = parse_pattern(rest)
      
      // Check for optional type annotation
      let (ty, after_ty) = if after_pattern.length() > 0 && 
                              after_pattern[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
        // Parse type annotation
        let after_colon = after_pattern[1:]
        let (parsed_ty, after_parsed_ty) = parse_type(after_colon)
        (Some(parsed_ty), after_parsed_ty)
      } else {
        (None, after_pattern)
      }
      
      // Expect "="
      if after_ty.length() == 0 || after_ty[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(@lexer.AssignOp::Assign) {
        raise ParseError("Expected '=' in let statement")
      }
      let after_equals = after_ty[1:]
      
      // Parse expression
      let (expr, after_expr) = parse_expr(after_equals)
      
      // Expect ";"
      if after_expr.length() == 0 {
        raise ParseError("Unexpected end of input while parsing let statement")
      }
      if after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
        raise ParseError("Expected ';' at end of let statement")
      }
      let final_rest = after_expr[1:]
      
      ({ pattern, ty, expr }, final_rest)
    }
    _ => {
      raise ParseError("Expected 'let' keyword at start of let statement")
    }
  }
}
