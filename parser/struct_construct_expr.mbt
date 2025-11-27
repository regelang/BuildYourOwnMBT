///|
pub(all) struct StructConstructExpr {
  name : String
  fields : Array[(String, Expr)]
} derive(Show, Eq)

///|
pub fn parse_struct_construct(
  tokens : ArrayView[Token],
) -> (AtomExpr, ArrayView[Token]) raise ParseError {
  parse_struct_construct_with_depth(tokens, 0)
}

///|
pub fn parse_struct_construct_with_depth(
  tokens : ArrayView[Token],
  depth : Int
) -> (AtomExpr, ArrayView[Token]) raise ParseError {
  if tokens.length() < 4 {
    raise ParseError("Expected struct constructor syntax: StructName::{ field: value, ... }")
  }
  
  // Parse the struct name (must be an uppercase identifier)
  let struct_name = match tokens[0].kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
    _ => raise ParseError("Expected struct name (uppercase identifier)")
  }
  
  // Check for '::' and '{'
  if tokens[1].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") ||
     tokens[2].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    raise ParseError("Expected '::{' after struct name")
  }
  
  let mut fields: Array[(String, Expr)] = []
  let mut current_tokens = tokens[3:]
  
  // Parse fields until we hit the closing '}'
  while current_tokens.length() > 0 {
    // Check for closing '}'
    if current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') {
      return (new_atom_expr(AtomExprKind::StructConstruct({
        name: struct_name,
        fields: fields
      })), current_tokens[1:])
    }
    
    // Skip commas between fields
    if current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
      current_tokens = current_tokens[1:]
      continue
    }
    
    // Parse field name (must be a lowercase identifier)
    if current_tokens.length() == 0 {
      raise ParseError("Expected field name or '}'")
    }
    
    let field_name = match current_tokens[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => name
      _ => raise ParseError("Expected field name (lowercase identifier)")
    }
    
    // Parse colon
    if current_tokens.length() < 2 || current_tokens[1].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(":") {
      raise ParseError("Expected ':' after field name")
    }
    
    // Parse field value expression
    if current_tokens.length() < 3 {
      raise ParseError("Expected expression after ':'")
    }
    
    let (field_value, after_expr) = parse_expr_with_depth(current_tokens[2:], depth + 1)
    fields = fields + [(field_name, field_value)]
    current_tokens = after_expr
    
    // Skip optional trailing comma
    if current_tokens.length() > 0 && current_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
      current_tokens = current_tokens[1:]
    }
  }
  
  // If we get here, we reached the end of input without finding a closing '}'
  raise ParseError("Expected '}' at end of struct constructor")
}
