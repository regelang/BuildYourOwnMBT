///|
pub(all) struct Expr {
  kind : ExprKind
} derive(Show, Eq)

///|
pub(all) enum ExprKind {
  ApplyExpr(ApplyExpr)
  BlockExpr(BlockExpr)
  NotExpr(Expr)
  NegExpr(Expr)
  BinaryExpr(BinaryOp, Expr, Expr)
  IfExpr(IfExpr)
  MatchExpr(MatchExpr)
} derive(Show, Eq)

///|
pub(all) enum BinaryOp {
  Add // +
  Sub // -
  Mul // *
  Div // /
  Mod // %
  ShiftLeft // <<
  ShiftRight // >>
  Eq // ==
  NE // !=
  LT // <
  GT // >
  LE // <=
  GE // >=
  And // &&
  Or // ||
  BitAnd // &
  BitOr // |
} derive(Show, Eq)

///|


fn parse_primary(tokens: ArrayView[Token]) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_primary_with_depth(tokens, 0)
}

fn parse_primary_with_depth(tokens: ArrayView[Token], depth: Int) -> (Expr, ArrayView[Token]) raise ParseError {
  if depth > 1000000 {
    // Use simple parsing to avoid infinite recursion
    return parse_simple_primary(tokens)
  }
  
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input")
  }
  
  let token = tokens[0]
  
  match token.kind {
    // Handle if expressions
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) => {
      let (if_expr, rest) = parse_if_expr_with_depth(tokens, depth)
      ({ kind: ExprKind::IfExpr(if_expr) }, rest)
    }
    // Handle match expressions
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Match) => {
      let (match_expr, rest) = parse_match_expr(tokens)
      ({ kind: ExprKind::MatchExpr(match_expr) }, rest)
    }
    // Handle block expressions
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') => {
      let (block_expr, rest) = parse_block_expr_with_depth(tokens, depth)
      ({ kind: ExprKind::BlockExpr(block_expr) }, rest)
    }
    // Handle unary operators
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Not => {
      let rest = tokens[1:]
      let (expr, rest_after_expr) = parse_primary_with_depth(rest, depth + 1)
      ({ kind: ExprKind::NotExpr(expr) }, rest_after_expr)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::BinaryOp(@moonbitlang/MiniMoonbit/lexer.BinaryOp::Sub) => {
      let rest = tokens[1:]
      let (expr, rest_after_expr) = parse_primary_with_depth(rest, depth + 1)
      ({ kind: ExprKind::NegExpr(expr) }, rest_after_expr)
    }
    // Default case: parse as atom expression first
    _ => {
      // 默认情况下，将表达式作为 ApplyExpr 处理
      let (apply_expr, rest_after_apply) = parse_apply_expr_with_depth(tokens, depth)
      ({ kind: ExprKind::ApplyExpr(apply_expr) }, rest_after_apply)
    }
  }
}

/// Parse a minimal block expression for local function bodies
/// This version only handles the simplest cases to avoid recursion
/// Parse a minimal block expression for local function bodies
/// This version returns an empty block to avoid recursion issues
/// Parse a minimal block expression to avoid infinite recursion
/// This function simply counts braces to find the matching closing brace
/// and returns an empty block to avoid complex parsing
pub fn parse_minimal_block_expr(tokens: ArrayView[Token]) -> (BlockExpr, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') {
    raise ParseError("Expected '{' at start of block expression")
  }
  
  // Count braces to find the matching closing brace
  let mut brace_count = 1
  let mut i = 1
  
  while i < tokens.length() && brace_count > 0 {
    match tokens[i].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') => brace_count += 1
      @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') => brace_count -= 1
      _ => ()
    }
    i += 1
  }
  
  if brace_count != 0 {
    raise ParseError("Unmatched braces in block expression")
  }
  
  // Return an empty block and skip past the closing brace
  let statements = []
  ({ stmts: statements }, tokens[i:])
}

/// Parse a simple block expression
/// This function uses a conservative approach to avoid infinite recursion
pub fn parse_simple_block_expr(tokens: ArrayView[Token]) -> (BlockExpr, ArrayView[Token]) raise ParseError {
  parse_simple_block_expr_with_depth(tokens, 0)
}

fn parse_simple_primary(tokens: ArrayView[Token]) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_simple_primary_with_depth(tokens, 0)
}

fn parse_simple_primary_with_depth(tokens: ArrayView[Token], depth: Int) -> (Expr, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input")
  }
  
  let token = tokens[0]
  
  match token.kind {
    // Skip if expressions to avoid infinite recursion
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) => {
      raise ParseError("If expressions are not allowed in this context")
    }
    // Skip block expressions to avoid infinite recursion
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('{') => {
      raise ParseError("Block expressions are not allowed in this context")
    }
    // Handle unary operators - parse only primary to avoid consuming binary operators
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Not => {
      let rest = tokens[1:]
      let (expr, rest_after_expr) = parse_simple_primary_with_depth(rest, depth + 1)
      ({ kind: ExprKind::NotExpr(expr) }, rest_after_expr)
    }
    @moonbitlang/MiniMoonbit/lexer.TokenKind::BinaryOp(@moonbitlang/MiniMoonbit/lexer.BinaryOp::Sub) => {
      let rest = tokens[1:]
      let (expr, rest_after_expr) = parse_simple_primary_with_depth(rest, depth + 1)
      ({ kind: ExprKind::NegExpr(expr) }, rest_after_expr)
    }
    // Default case: parse as atom expression first
    _ => {
      // 默认情况下，将表达式作为 ApplyExpr 处理
      let (apply_expr, rest_after_apply) = parse_apply_expr_with_depth(tokens, depth)
      ({ kind: ExprKind::ApplyExpr(apply_expr) }, rest_after_apply)
    }
  }
}

/// Parse a simple expression without block expressions
pub fn parse_simple_expr(tokens: ArrayView[Token]) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_simple_binary_expr(tokens, 0)
}

/// Parse a simple expression without block expressions with recursion depth tracking
pub fn parse_simple_expr_with_depth(tokens: ArrayView[Token], depth: Int) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_simple_binary_expr_with_depth(tokens, 0, depth)
}

fn parse_simple_binary_expr(
  tokens: ArrayView[Token],
  min_prec: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // Parse the left-hand side
  let left_parsed = parse_simple_primary(tokens)
  parse_simple_binary_expr_rhs(left_parsed.0, left_parsed.1, min_prec)
}

fn parse_simple_binary_expr_with_depth(
  tokens: ArrayView[Token],
  min_prec: Int,
  depth: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // Parse the left-hand side
  let left_parsed = parse_simple_primary_with_depth(tokens, depth)
  parse_simple_binary_expr_rhs_with_depth(left_parsed.0, left_parsed.1, min_prec, depth)
}

fn parse_simple_binary_expr_rhs(
  left: Expr,
  tokens: ArrayView[Token],
  min_prec: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // If we're out of tokens, we're done
  if tokens.length() == 0 {
    (left, tokens)
  } else {
    // Check if the next token is a binary operator
    let token = tokens[0]
    match token.kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::BinaryOp(op) => {
        let bin_op = convert_bin_op(op)
        let prec = bin_op.precedence()
        
        // If the operator's precedence is less than the minimum, we're done
        if prec < min_prec {
          (left, tokens)
        } else {
          // Consume the operator token
          let rest_after_op = tokens[1:]
          
          // Parse the right-hand side with higher precedence
          let right_parsed = parse_simple_primary(rest_after_op)
          
          // Check if there's another operator with higher precedence
          let (right, rest_after_right) = parse_simple_binary_expr_rhs(
            right_parsed.0,
            right_parsed.1,
            prec + 1
          )
          
          // Create the new expression and continue
          let new_left: Expr = {
            kind: ExprKind::BinaryExpr(
              bin_op,
              left,
              right
            )
          }
          
          parse_simple_binary_expr_rhs(new_left, rest_after_right, min_prec)
        }
      }
      _ => (left, tokens)
    }
  }
}

fn parse_simple_binary_expr_rhs_with_depth(
  left: Expr,
  tokens: ArrayView[Token],
  min_prec: Int,
  depth: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // If we're out of tokens, we're done
  if tokens.length() == 0 {
    (left, tokens)
  } else {
    // Check if the next token is a binary operator
    let token = tokens[0]
    match token.kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::BinaryOp(op) => {
        let bin_op = convert_bin_op(op)
        let prec = bin_op.precedence()
        
        // If the operator's precedence is less than the minimum, we're done
        if prec < min_prec {
          (left, tokens)
        } else {
          // Consume the operator token
          let rest_after_op = tokens[1:]
          
          // Parse the right-hand side with higher precedence
          let right_parsed = parse_simple_primary_with_depth(rest_after_op, depth)
          
          // Check if there's another operator with higher precedence
          let (right, rest_after_right) = parse_simple_binary_expr_rhs_with_depth(
            right_parsed.0,
            right_parsed.1,
            prec + 1,
            depth
          )
          
          // Create the new expression and continue
          let new_left: Expr = {
            kind: ExprKind::BinaryExpr(
              bin_op,
              left,
              right
            )
          }
          
          parse_simple_binary_expr_rhs_with_depth(new_left, rest_after_right, min_prec, depth)
        }
      }
      _ => (left, tokens)
    }
  }
}

/// Helper function to convert lexer's BinaryOp to parser's BinaryOp
fn convert_bin_op(op: @moonbitlang/MiniMoonbit/lexer.BinaryOp) -> BinaryOp {
  match op {
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Add => Add
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Sub => Sub
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Mul => Mul
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Div => Div
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Mod => Mod
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Eq => Eq
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::NE => NE
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::LT => LT
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::GT => GT
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::LE => LE
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::GE => GE
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::And => And
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::Or => Or
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::BitAnd => BitAnd
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::BitOr => BitOr
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::ShiftLeft => ShiftLeft
    @moonbitlang/MiniMoonbit/lexer.BinaryOp::ShiftRight => ShiftRight
  }
}

///|
pub fn parse_expr(
  tokens: ArrayView[Token],
) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_binary_expr(tokens, 0)
}

/// Parse an expression with recursion depth tracking
pub fn parse_expr_with_depth(
  tokens: ArrayView[Token],
  depth: Int,
) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_binary_expr_with_depth(tokens, 0, depth)
}

fn parse_binary_expr(
  tokens: ArrayView[Token],
  min_prec: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_binary_expr_with_depth(tokens, min_prec, 0)
}

fn parse_binary_expr_with_depth(
  tokens: ArrayView[Token],
  min_prec: Int,
  depth: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // Parse the left-hand side
  let left_parsed = parse_primary_with_depth(tokens, depth)
  parse_binary_expr_rhs_with_depth(left_parsed.0, left_parsed.1, min_prec, depth)
}

fn parse_binary_expr_rhs(
  left: Expr,
  tokens: ArrayView[Token],
  min_prec: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  parse_binary_expr_rhs_with_depth(left, tokens, min_prec, 0)
}

fn parse_binary_expr_rhs_with_depth(
  left: Expr,
  tokens: ArrayView[Token],
  min_prec: Int,
  depth: Int
) -> (Expr, ArrayView[Token]) raise ParseError {
  // If we're out of tokens, we're done
  if tokens.length() == 0 {
    (left, tokens)
  } else {
    // Check if the next token is a binary operator
    let token = tokens[0]
    match token.kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::BinaryOp(op) => {
        let bin_op = convert_bin_op(op)
        let prec = bin_op.precedence()
        
        // If the operator's precedence is less than the minimum, we're done
        if prec < min_prec {
          (left, tokens)
        } else {
          // Consume the operator token
          let rest_after_op = tokens[1:]
          
          // Parse the right-hand side with higher precedence
          let right_parsed = parse_primary_with_depth(rest_after_op, depth)
          
          // Check if there's another operator with higher precedence
          let (right, rest_after_right) = parse_binary_expr_rhs_with_depth(
            right_parsed.0,
            right_parsed.1,
            prec + 1,
            depth
          )
          
          // Create the new expression and continue
          let new_left: Expr = {
            kind: ExprKind::BinaryExpr(
              bin_op,
              left,
              right
            )
          }
          
          parse_binary_expr_rhs_with_depth(new_left, rest_after_right, min_prec, depth)
        }
      }
      _ => (left, tokens)
    }
  }
}

///|
fn BinaryOp::precedence(self : Self) -> Int {
  match self {
    Or => 1
    And => 2
    Eq | NE => 3
    LT | GT | LE | GE => 4
    BitOr => 5
    BitAnd => 7
    ShiftLeft | ShiftRight => 8
    Add | Sub => 9
    Mul | Div | Mod => 10
  }
}
