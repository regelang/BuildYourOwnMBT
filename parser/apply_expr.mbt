///|
pub(all) struct ApplyExpr {
  kind : ApplyExprKind
} derive(Show, Eq)

///|
pub(all) enum ApplyExprKind {
  AtomExpr(AtomExpr)
  ArrayAccess(ApplyExpr, Expr)
  FieldAccess(ApplyExpr, String)
  EnumVariantAccess(ApplyExpr, String)  // For EnumName::Variant syntax
  Call(ApplyExpr, Array[Expr])
} derive(Show, Eq)

///|
pub fn parse_apply_expr(
  tokens : ArrayView[Token],
) -> (ApplyExpr, ArrayView[Token]) raise ParseError {
  parse_apply_expr_with_depth(tokens, 0)
}

/// Parse an apply expression with recursion depth tracking
pub fn parse_apply_expr_with_depth(
  tokens : ArrayView[Token],
  depth : Int,
) -> (ApplyExpr, ArrayView[Token]) raise ParseError {
  let (atom_expr, rest) = parse_atom_expr_with_depth(tokens, depth)
  let base_expr : ApplyExpr = { kind: ApplyExprKind::AtomExpr(atom_expr) }
  parse_apply_expr_suffix_with_depth(base_expr, rest, depth)
}

/// Helper function to parse array access suffixes
fn parse_apply_expr_suffix(
  base_expr: ApplyExpr,
  tokens: ArrayView[Token]
) -> (ApplyExpr, ArrayView[Token]) raise ParseError {
  parse_apply_expr_suffix_with_depth(base_expr, tokens, 0)
}

/// Helper function to parse array access suffixes with depth tracking
fn parse_apply_expr_suffix_with_depth(
  base_expr: ApplyExpr,
  tokens: ArrayView[Token],
  depth: Int
) -> (ApplyExpr, ArrayView[Token]) raise ParseError {
  let mut current_expr = base_expr
  let mut remaining_tokens = tokens
  let mut operations_processed = 0
  
  // Limit the number of chained operations to prevent stack issues
  while operations_processed < 20 && remaining_tokens.length() > 0 {
    if remaining_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('[') {
      // Array access: skip '['
      let after_open = remaining_tokens[1:]
      
      // Parse the index expression
      let (index_expr, after_index) = parse_expr_with_depth(after_open, depth + 1)
      
      // Expect ']'
      if after_index.length() == 0 || after_index[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(']') {
        raise ParseError("Expected ']' after array index")
      }
      
      // Create new array access expression
      current_expr = { 
        kind: ApplyExprKind::ArrayAccess(current_expr, index_expr) 
      }
      
      remaining_tokens = after_index[1:]
      operations_processed = operations_processed + 1
    } else if remaining_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('(') {
      // Function call: skip '('
      let after_open = remaining_tokens[1:]
      
      // Parse the argument list
      let (args, after_args) = parse_comma_separated_args_with_depth(after_open, depth + 1)
      
      // Expect ')'
      if after_args.length() == 0 || after_args[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
        raise ParseError("Expected ')' after function arguments")
      }
      
      // Create new function call expression
      current_expr = {
        kind: ApplyExprKind::Call(current_expr, args)
      }
      
      remaining_tokens = after_args[1:]
      operations_processed = operations_processed + 1
    } else if remaining_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol("::") {
      // Namespace/Enum access: skip '::'
      let after_double_colon = remaining_tokens[1:]
      
      // Expect uppercase identifier as enum variant name
      if after_double_colon.length() == 0 {
        raise ParseError("Expected enum variant name after '::'")
      }
      
      let variant_token = after_double_colon[0]
      match variant_token.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Upper(variant_name) => {
          // Create a new enum variant access expression
          current_expr = {
            kind: ApplyExprKind::EnumVariantAccess(current_expr, variant_name)
          }
          
          remaining_tokens = after_double_colon[1:]
          operations_processed = operations_processed + 1
        }
        _ => {
          raise ParseError("Expected uppercase identifier (enum variant) after '::'")
        }
      }
    } else if remaining_tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(".") {
      // Field access: skip '.'
      let after_dot = remaining_tokens[1:]
      
      // Expect field name
      if after_dot.length() == 0 {
        raise ParseError("Expected field name after '. '")
      }
      
      let field_token = after_dot[0]
      match field_token.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(field_name) => {
          // Create new field access expression
          current_expr = {
            kind: ApplyExprKind::FieldAccess(current_expr, field_name)
          }
          
          remaining_tokens = after_dot[1:]
          operations_processed = operations_processed + 1
        }
        _ => {
          raise ParseError("Expected field name (lowercase identifier) after '. '")
        }
      }
    } else {
      // No more operations
      break
    }
  }
  
  (current_expr, remaining_tokens)
}

/// Helper function to parse comma-separated expression list
fn parse_comma_separated_args(
  tokens: ArrayView[Token]
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  parse_comma_separated_args_with_depth(tokens, 0)
}

/// Helper function to parse comma-separated expression list with depth tracking
fn parse_comma_separated_args_with_depth(
  tokens: ArrayView[Token],
  depth: Int
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  // Check for empty argument list
  if tokens.length() > 0 && tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
    ([], tokens)
  } else if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing expression list")
  } else {
    // Limit the number of arguments to prevent issues
    parse_expr_list_limited_with_depth(tokens, 0, depth)
  }
}

/// Helper function with argument limit
fn parse_expr_list_limited(
  tokens: ArrayView[Token],
  arg_count: Int
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  parse_expr_list_limited_with_depth(tokens, arg_count, 0)
}

/// Helper function with argument limit and depth tracking
fn parse_expr_list_limited_with_depth(
  tokens: ArrayView[Token],
  arg_count: Int,
  depth: Int
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  if arg_count > 10 {
    raise ParseError("Too many function arguments")
  }
  
  // Parse first argument
  let (first_arg, after_first) = parse_expr_with_depth(tokens, depth + 1)
  
  // Parse remaining arguments
  parse_expr_list_rest_with_depth([first_arg], after_first, arg_count + 1, depth)
}

/// Helper function to parse remaining comma-separated expressions
fn parse_expr_list_rest(
  args: Array[Expr], 
  tokens: ArrayView[Token],
  arg_count: Int
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  parse_expr_list_rest_with_depth(args, tokens, arg_count, 0)
}

/// Helper function to parse remaining comma-separated expressions with depth tracking
fn parse_expr_list_rest_with_depth(
  args: Array[Expr], 
  tokens: ArrayView[Token],
  arg_count: Int,
  depth: Int
) -> (Array[Expr], ArrayView[Token]) raise ParseError {
  if arg_count > 10 {
    raise ParseError("Too many function arguments")
  }
  
  // Check if next token is comma
  if tokens.length() > 0 && tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(",") {
    // Skip comma
    let after_comma = tokens[1:]
    
    // Check for trailing comma (end of arguments)
    if after_comma.length() > 0 && after_comma[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(')') {
      (args, after_comma)
    } else if after_comma.length() == 0 {
      raise ParseError("Unexpected end of input after comma in expression list")
    } else {
      // Parse next argument
      let (next_arg, after_next) = parse_expr_with_depth(after_comma, depth + 1)
      
      // Continue parsing
      parse_expr_list_rest_with_depth(args + [next_arg], after_next, arg_count + 1, depth)
    }
  } else {
    // No more commas, return current arguments
    (args, tokens)
  }
}
