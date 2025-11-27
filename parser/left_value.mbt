///|
pub(all) struct LeftValue {
  kind : LeftValueKind
} derive(Show, Eq)

///|
pub(all) enum LeftValueKind {
  Ident(String)
  ArrayAccess(LeftValue, Expr)
  FieldAccess(LeftValue, String)
} derive(Show, Eq)

///|
pub fn parse_left_value(
  tokens : ArrayView[Token],
) -> (LeftValue, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing left value")
  }

  // Left value must start with an identifier
  let token = tokens[0]
  let rest = tokens[1:]
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(var_name) => {
      // Start with a simple identifier
      let mut current_value: LeftValue = { kind: Ident(var_name) }
      let mut remaining_tokens = rest
      let mut continue_parsing = true

      // Parse suffixes: array access and field access
      while continue_parsing && remaining_tokens.length() > 0 {
        let next_token = remaining_tokens[0]
        match next_token.kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') => {
            // Array access: skip '['
            let after_open = remaining_tokens[1:]
            
            // Parse index expression
            let (index_expr, after_index) = parse_expr(after_open)
            
            // Expect ']'
            if after_index.length() == 0 || after_index[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(']') {
              raise ParseError("Expected ']' after array index in left value")
            }
            
            // Create new array access left value
            current_value = { kind: ArrayAccess(current_value, index_expr) }
            remaining_tokens = after_index[1:]
          }
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(".") => {
            // Field access: skip '.'
            let after_dot = remaining_tokens[1:]
            
            // Expect field name (lowercase identifier)
            if after_dot.length() == 0 {
              raise ParseError("Expected field name after '.' in left value")
            }
            
            let field_token = after_dot[0]
            match field_token.kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(field_name) => {
                // Create new field access left value
                current_value = { kind: FieldAccess(current_value, field_name) }
                remaining_tokens = after_dot[1:]
              }
              _ => {
                raise ParseError("Expected field name (lowercase identifier) after '.' in left value")
              }
            }
          }
          _ => {
            // No more suffixes, stop parsing
            continue_parsing = false
          }
        }
      }

      (current_value, remaining_tokens)
    }
    _ => {
      raise ParseError("Left value must start with an identifier")
    }
  }
}
