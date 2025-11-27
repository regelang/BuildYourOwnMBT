///|
pub(all) struct TopLet {
  name : String
  ty : Type?
  expr : Expr
} derive(Show, Eq)

///|
pub fn parse_top_let(
  tokens : ArrayView[Token],
) -> (TopLet, ArrayView[Token]) raise ParseError {
  if tokens.length() < 3 {
    raise ParseError("Unexpected end of input while parsing top-level let binding")
  }

  // Expect "let" keyword
  let token1 = tokens[0]
  let rest1 = tokens[1:]
  match token1.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) => {
      // Parse variable name (must be Lower token)
      if rest1.length() == 0 {
        raise ParseError("Expected variable name after 'let'")
      }
      let name_token = rest1[0]
      let rest2 = rest1[1:]
      match name_token.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(var_name) => {
          // Check for optional type annotation
          let (ty, after_ty) = if rest2.length() > 0 && 
                                rest2[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
            // Parse type annotation
            let after_colon = rest2[1:]
            let (parsed_ty, after_parsed_ty) = parse_type(after_colon)
            (Some(parsed_ty), after_parsed_ty)
          } else {
            (None, rest2)
          }
          
          // Expect "="
          if after_ty.length() == 0 || after_ty[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(@lexer.AssignOp::Assign) {
            raise ParseError("Expected '=' in top-level let binding")
          }
          let after_equals = after_ty[1:]
          
          // Parse expression
          let (expr, after_expr) = parse_expr(after_equals)
          
          // Expect ";"
          if after_expr.length() == 0 {
            raise ParseError("Unexpected end of input while parsing top-level let binding")
          }
          if after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            raise ParseError("Expected ';' at end of top-level let binding")
          }
          let final_rest = after_expr[1:]
          
          ({ name: var_name, ty, expr }, final_rest)
        }
        _ => {
          raise ParseError("Expected variable name (lowercase identifier) after 'let'")
        }
      }
    }
    _ => {
      raise ParseError("Expected 'let' keyword at start of top-level let binding")
    }
  }
}
