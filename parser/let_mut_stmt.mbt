///|
pub(all) struct LetMutStmt {
  name : String
  ty : Type?
  expr : Expr
} derive(Show, Eq)

///|
pub fn parse_let_mut_stmt(
  tokens : ArrayView[Token],
) -> (LetMutStmt, ArrayView[Token]) raise ParseError {
  if tokens.length() < 4 {
    raise ParseError("Unexpected end of input while parsing let mut statement")
  }

  // Expect "let" keyword
  let token1 = tokens[0]
  let rest1 = tokens[1:]
  match token1.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) => {
      // Expect "mut" keyword
      let token2 = rest1[0]
      let rest2 = rest1[1:]
      match token2.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Mut) => {
          // Parse variable name (must be Lower token)
          if rest2.length() == 0 {
            raise ParseError("Expected variable name after 'let mut'")
          }
          let name_token = rest2[0]
          let rest3 = rest2[1:]
          match name_token.kind {
            @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(var_name) => {
              // Check for optional type annotation
              let (ty, after_ty) = if rest3.length() > 0 && 
                                    rest3[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
                // Parse type annotation
                let after_colon = rest3[1:]
                let (parsed_ty, after_parsed_ty) = parse_type(after_colon)
                (Some(parsed_ty), after_parsed_ty)
              } else {
                (None, rest3)
              }
              
              // Expect "="
              if after_ty.length() == 0 || after_ty[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(@lexer.AssignOp::Assign) {
                raise ParseError("Expected '=' in let mut statement")
              }
              let after_equals = after_ty[1:]
              
              // Parse expression
              let (expr, after_expr) = parse_expr(after_equals)
              
              // Expect ";"
              if after_expr.length() == 0 {
                raise ParseError("Unexpected end of input while parsing let mut statement")
              }
              if after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
                raise ParseError("Expected ';' at end of let mut statement")
              }
              let final_rest = after_expr[1:]
              
              ({ name: var_name, ty, expr }, final_rest)
            }
            _ => {
              raise ParseError("Expected variable name (lowercase identifier) after 'let mut'")
            }
          }
        }
        _ => {
          raise ParseError("Expected 'mut' keyword after 'let'")
        }
      }
    }
    _ => {
      raise ParseError("Expected 'let' keyword at start of let mut statement")
    }
  }
}
