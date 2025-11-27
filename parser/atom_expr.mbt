///|
pub struct AtomExpr {
  kind : AtomExprKind
} derive(Show, Eq)

///| Create a new AtomExpr with the given kind
fn new_atom_expr(kind: AtomExprKind) -> AtomExpr {
  { kind: kind }
}

///|
pub(all) enum AtomExprKind {
  Int(Int) // 1, 42, etc
  Double(Double) // 1.0, 3.14, etc
  Bool(Bool) // true | false
  String(String) // "hello", etc
  Ident(String) // var
  Unit // ()
  Paren(Expr) // (expr)
  Tuple(Array[Expr]) // (expr, expr, ...)
  ArrayMake(Expr, Expr) // Array::make(size, init)
  Array(Array[Expr]) // [expr, expr, ...]
  StructConstruct(StructConstructExpr) // StructName::{ field: expr, ... }
  EnumVariant(String, String) // EnumName::Variant
} derive(Show, Eq)

///|
pub fn parse_atom_expr(
  tokens : ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_atom_expr_with_depth(tokens, 0)
}

/// Parse an atom expression with recursion depth tracking
pub fn parse_atom_expr_with_depth(
  tokens : ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth : Int,
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // Prevent infinite recursion by limiting depth
  if depth > 100 {
    // Use simple parsing for deep recursion
    return parse_simple_atom_expr_with_depth(tokens, depth)
  }
  
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input")
  }
  
  let token = tokens[0]
  let rest = tokens[1:]
  
  // Match on token.kind and create AtomExpr with the appropriate kind
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Int(n) => {
      (new_atom_expr(AtomExprKind::Int(n)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Double(d) => {
      (new_atom_expr(AtomExprKind::Double(d)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bool(b) => {
      (new_atom_expr(AtomExprKind::Bool(b)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::String(s) => {
      (new_atom_expr(AtomExprKind::String(s)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("true") => {
      (new_atom_expr(AtomExprKind::Bool(true)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("false") => {
      (new_atom_expr(AtomExprKind::Bool(false)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => {
      (new_atom_expr(AtomExprKind::Ident(name)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper("Array") => {
      // Check if this is Array::make syntax
      if rest.length() >= 3 &&
         rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") &&
         rest[1].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("make") &&
         rest[2].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') {
        parse_array_make_expr(tokens)
      } else {
        raise ParseError("Expected 'Array::make' syntax")
      }
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => {
      // Check if this is a struct constructor (StructName::{ ... })
      if rest.length() >= 2 &&
         rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") &&
         rest[1].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
        parse_struct_construct(tokens)
      } else if rest.length() >= 2 &&
                rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") &&
                rest[1].kind is @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(variant_name) {
        // This is enum variant syntax: EnumName::Variant
        let variant_name = match rest[1].kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
          _ => raise ParseError("Expected variant name after ::")
        }
        (new_atom_expr(AtomExprKind::EnumVariant(name, variant_name)), rest[2:])
      } else {
        // It's just a type name or enum constructor, treat it as an identifier
        // Enum constructors like Red or RGB(1,2,3) will be handled as identifiers
        // and function calls by the apply_expr parser
        (new_atom_expr(AtomExprKind::Ident(name)), rest)
      }
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
      parse_paren_expr_with_depth(tokens, depth)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') => {
      parse_array_expr_with_depth(tokens, depth)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) => {
      // This is an if expression, but it should be handled by parse_primary
      // in expr.mbt. If we get here, it's an error.
      raise ParseError("If expressions should be handled by parse_primary")
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Else) => {
      // This is an else keyword, but it should be handled by parse_primary
      // in expr.mbt as part of if-else expressions. If we get here, it's an error.
      raise ParseError("Else keyword should be handled by parse_primary")
    }
    _ => {
      raise ParseError("Unexpected token in atom expression: " + token.kind.to_string())
    }
  }
}

/// Parse a simple atom expression to avoid infinite recursion
fn parse_simple_atom_expr_with_depth(
  tokens : ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth : Int,
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input")
  }
  
  let token = tokens[0]
  let rest = tokens[1:]
  
  // Only handle simple cases to avoid recursion
  match token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Int(n) => {
      (new_atom_expr(AtomExprKind::Int(n)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Double(d) => {
      (new_atom_expr(AtomExprKind::Double(d)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bool(b) => {
      (new_atom_expr(AtomExprKind::Bool(b)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::String(s) => {
      (new_atom_expr(AtomExprKind::String(s)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("true") => {
      (new_atom_expr(AtomExprKind::Bool(true)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("false") => {
      (new_atom_expr(AtomExprKind::Bool(false)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(name) => {
      (new_atom_expr(AtomExprKind::Ident(name)), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper("Array") => {
      // For simple parsing, just treat Array as an identifier
      (new_atom_expr(AtomExprKind::Ident("Array")), rest)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => {
      // Check if this is enum variant syntax: EnumName::Variant
      if rest.length() >= 2 &&
         rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") &&
         rest[1].kind is @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(variant_name) {
        // For simple parsing, treat enum variant as identifier
        let variant_name = match rest[1].kind {
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(name) => name
          _ => "Unknown"
        }
        (new_atom_expr(AtomExprKind::EnumVariant(name, variant_name)), rest[2:])
      } else {
        // For simple parsing, just treat type names as identifiers
        (new_atom_expr(AtomExprKind::Ident(name)), rest)
      }
    }
    // Skip parentheses to avoid recursion
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') => {
      // For simple parsing, treat as unit
      if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
        (new_atom_expr(AtomExprKind::Unit), rest[1:])
      } else {
        // Otherwise, just skip the opening paren and return a dummy int
        (new_atom_expr(AtomExprKind::Int(0)), rest)
      }
    }
    // Skip arrays to avoid recursion
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') => {
      // For simple parsing, return an empty array
      (new_atom_expr(AtomExprKind::Array([])), rest)
    }
    // Skip keywords to avoid recursion
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(_) => {
      // For simple parsing, return a dummy int
      (new_atom_expr(AtomExprKind::Int(0)), rest)
    }
    _ => {
      raise ParseError("Unexpected token in simple atom expression: " + token.kind.to_string())
    }
  }
}

///|
fn parse_paren_expr(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_paren_expr_with_depth(tokens, 0)
}

///|
fn parse_paren_expr_with_depth(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth: Int
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // Skip the opening '('
  let rest = tokens[1:]
  
  // Check for empty parentheses first (Unit)
  if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
    return (new_atom_expr(AtomExprKind::Unit), rest[1:])
  }
  
  // Parse the first expression
  let first_expr_parsed = parse_expr_with_depth(rest, depth + 1)
  
  // Check if the next token is a comma or closing parenthesis
  let (exprs, remaining_tokens) = parse_comma_separated_exprs_with_depth(
    [first_expr_parsed.0], 
    first_expr_parsed.1,
    depth + 1
  )
  
  // Expect a closing parenthesis
  if remaining_tokens.length() == 0 || remaining_tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
    raise ParseError("Expected ')' in parenthesized expression")
  }
  
  // Skip the closing parenthesis
  let final_rest = remaining_tokens[1:]
  
  // Determine if this is a single expression in parentheses or a tuple
  if exprs.length() == 1 {
    // Single expression in parentheses (grouping)
    (new_atom_expr(AtomExprKind::Paren(exprs[0])), final_rest)
  } else {
    // Multiple expressions (tuple)
    (new_atom_expr(AtomExprKind::Tuple(exprs)), final_rest)
  }
}

/// Helper function to parse comma-separated expressions
fn parse_comma_separated_exprs(
  exprs: Array[Expr],
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]
) -> (Array[Expr], ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_comma_separated_exprs_with_depth(exprs, tokens, 0)
}

/// Helper function to parse comma-separated expressions with depth tracking
fn parse_comma_separated_exprs_with_depth(
  exprs: Array[Expr],
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth: Int
) -> (Array[Expr], ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // If there are no more tokens or the next token is not a comma, return what we have
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
    (exprs, tokens)
  } else {
    // Skip the comma
    let rest_after_comma = tokens[1:]
    
    // Check for closing parenthesis after comma (trailing comma case)
    if rest_after_comma.length() > 0 && rest_after_comma[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
      (exprs, rest_after_comma)
    } else {
      // Parse the next expression
      let next_expr_parsed = parse_expr_with_depth(rest_after_comma, depth + 1)
      
      // Recursively parse any additional expressions
      parse_comma_separated_exprs_with_depth(
        exprs + [next_expr_parsed.0],
        next_expr_parsed.1,
        depth
      )
    }
  }
}

///|
fn parse_array_expr(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_array_expr_with_depth(tokens, 0)
}

///|
fn parse_array_expr_with_depth(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth: Int
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // Skip the opening '['
  let rest = tokens[1:]
  
  // Check for empty array first
  if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(']') {
    return (new_atom_expr(AtomExprKind::Array([])), rest[1:])
  }
  
  // Parse the first expression
  let first_expr_parsed = parse_expr_with_depth(rest, depth + 1)
  
  // Check if the next token is a comma or closing bracket
  let (exprs, remaining_tokens) = parse_comma_separated_exprs_for_array_with_depth(
    [first_expr_parsed.0], 
    first_expr_parsed.1,
    depth + 1
  )
  
  // Expect a closing bracket
  if remaining_tokens.length() == 0 || remaining_tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(']') {
    raise ParseError("Expected ']' in array expression")
  }
  
  // Skip the closing bracket
  let final_rest = remaining_tokens[1:]
  
  // Return the array expression
  (new_atom_expr(AtomExprKind::Array(exprs)), final_rest)
}

/// Helper function to parse comma-separated expressions for arrays
fn parse_comma_separated_exprs_for_array(
  exprs: Array[Expr],
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]
) -> (Array[Expr], ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_comma_separated_exprs_for_array_with_depth(exprs, tokens, 0)
}

/// Helper function to parse comma-separated expressions for arrays with depth tracking
fn parse_comma_separated_exprs_for_array_with_depth(
  exprs: Array[Expr],
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth: Int
) -> (Array[Expr], ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // If there are no more tokens or the next token is not a comma, return what we have
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
    (exprs, tokens)
  } else {
    // Skip the comma
    let rest_after_comma = tokens[1:]
    
    // Check for closing bracket after comma (trailing comma case)
    if rest_after_comma.length() > 0 && rest_after_comma[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(']') {
      (exprs, rest_after_comma)
    } else {
      // Parse the next expression
      let next_expr_parsed = parse_expr_with_depth(rest_after_comma, depth + 1)
      
      // Recursively parse any additional expressions
      parse_comma_separated_exprs_for_array_with_depth(
        exprs + [next_expr_parsed.0],
        next_expr_parsed.1,
        depth
      )
    }
  }
}

///|
pub fn parse_array_make_expr(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  parse_array_make_expr_with_depth(tokens, 0)
}

///|
pub fn parse_array_make_expr_with_depth(
  tokens: ArrayView[@moonbitlang/MiniMoonbit/lexer.Token],
  depth: Int
) -> (AtomExpr, ArrayView[@moonbitlang/MiniMoonbit/lexer.Token]) raise ParseError {
  // We expect tokens to start with ["Array", "::", "make", "(", ...]
  if tokens.length() < 5 {
    raise ParseError("Invalid Array::make syntax")
  }

  // Check for "Array::make("
  if tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper("Array") ||
     tokens[1].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") ||
     tokens[2].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower("make") ||
     tokens[3].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') {
    raise ParseError("Expected 'Array::make(' in array make expression")
  }

  // Skip "Array::make("
  let mut rest = tokens[4:]
  
  // Parse size expression
  let size_parsed = parse_expr_with_depth(rest, depth + 1)
  rest = size_parsed.1
  
  // Expect comma after size
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
    raise ParseError("Expected ',' after array size in Array::make")
  }
  
  // Skip comma
  rest = rest[1:]
  
  // Parse init expression
  let init_parsed = parse_expr_with_depth(rest, depth + 1)
  rest = init_parsed.1
  
  // Expect closing parenthesis
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
    raise ParseError("Expected ')' after array initializer in Array::make")
  }
  
  // Skip closing parenthesis
  rest = rest[1:]
  
  // Return the ArrayMake expression and remaining tokens
  (new_atom_expr(AtomExprKind::ArrayMake(size_parsed.0, init_parsed.0)), rest)
}