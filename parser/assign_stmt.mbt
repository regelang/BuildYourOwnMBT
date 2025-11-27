///|
pub(all) struct AssignStmt {
  left_value : LeftValue
  op : AssignOp
  expr : Expr
} derive(Show, Eq)

///|
pub(all) enum AssignOp {
  Assign // =
  PlusAssign // +=
  MinusAssign // -=
  MultAssign // *=
  DivAssign // /=
  ModAssign // %=
} derive(Show, Eq)

///|
fn AssignOp::from_tok_assign_op(op : @lexer.AssignOp) -> AssignOp {
  match op {
    Assign => Assign
    PlusAssign => PlusAssign
    MinusAssign => MinusAssign
    MultAssign => MultAssign
    DivAssign => DivAssign
    ModAssign => ModAssign
  }
}

///|
pub fn parse_assign_stmt(
  tokens : ArrayView[Token],
) -> (AssignStmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing assignment statement")
  }

  // Parse left value
  let (left_value, after_left) = parse_left_value(tokens)

  // Expect assignment operator
  if after_left.length() == 0 {
    raise ParseError("Expected assignment operator after left value")
  }

  let op_token = after_left[0]
  let after_op = after_left[1:]

  let op = match op_token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(assign_op) => {
      AssignOp::from_tok_assign_op(assign_op)
    }
    _ => {
      raise ParseError("Expected assignment operator")
    }
  }

  // Parse expression
  let (expr, after_expr) = parse_expr(after_op)

  // Expect semicolon
  if after_expr.length() == 0 {
    raise ParseError("Unexpected end of input while parsing assignment statement")
  }
  if after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
    raise ParseError("Expected ';' at end of assignment statement")
  }

  let final_rest = after_expr[1:]

  ({ left_value, op, expr }, final_rest)
}
