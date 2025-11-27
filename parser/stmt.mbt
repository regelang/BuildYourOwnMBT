///|
pub(all) struct Stmt {
  kind : StmtKind
} derive(Show, Eq)

///|
pub(all) enum StmtKind {
  LetStmt(LetStmt)
  LetMutStmt(LetMutStmt)
  AssignStmt(AssignStmt)
  WhileStmt(WhileStmt)
  ExprStmt(Expr)
  ReturnStmt(Expr?)
  LocalFunction(LocalFunction)
  IfStmt(Expr)  // For if expressions used as statements
} derive(Show, Eq)

///|
pub fn parse_stmt(
  tokens : ArrayView[Token],
) -> (Stmt, ArrayView[Token]) raise ParseError {
  parse_stmt_with_depth(tokens, 0)
}

/// Parse a statement with recursion depth tracking
fn parse_stmt_with_depth(
  tokens : ArrayView[Token],
  depth : Int,
) -> (Stmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input while parsing statement")
  }

  let first_token = tokens[0]
  
  match first_token.kind {
    // Let statements
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(keyword) => {
      match keyword {
        @lexer.Keyword::Let => {
          // Check if this is "let mut" or just "let"
          if tokens.length() > 1 {
            let second_token = tokens[1]
            match second_token.kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Mut) => {
                // This is a "let mut" statement
                let (let_mut_stmt, rest) = parse_let_mut_stmt(tokens)
                ({ kind: LetMutStmt(let_mut_stmt) }, rest)
              }
              _ => {
                // This is a regular "let" statement
                let (let_stmt, rest) = parse_let_stmt(tokens)
                ({ kind: LetStmt(let_stmt) }, rest)
              }
            }
          } else {
            // Just "let" at end of input - parse as let statement (will error appropriately)
            let (let_stmt, rest) = parse_let_stmt(tokens)
            ({ kind: LetStmt(let_stmt) }, rest)
          }
        }
        @lexer.Keyword::While => {
          // While statement
          let (while_stmt, rest) = parse_while_stmt_with_depth(tokens, depth)
          ({ kind: WhileStmt(while_stmt) }, rest)
        }
        @lexer.Keyword::Return => {
          // Skip the 'return' keyword
          let after_return = tokens[1:]
          
          // Parse optional return expression
          let (return_expr_opt, after_expr) = if after_return.length() > 0 && 
                                              after_return[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            let (expr, rest) = parse_expr_with_depth(after_return, depth + 1)
            (Some(expr), rest)
          } else {
            (None, after_return)
          }
          
          // Expect semicolon
          if after_expr.length() == 0 || after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            raise ParseError("Expected ';' at end of return statement")
          }
          
          ({ kind: ReturnStmt(return_expr_opt) }, after_expr[1:])
        }
        @lexer.Keyword::If => {
          // This is an if expression used as a statement
          // Use parse_expr instead of parse_simple_expr to handle complex if expressions
          let (expr, rest) = parse_expr_with_depth(tokens, depth + 1)
          // Check if the next token is a semicolon (optional for if expressions)
          if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            ({ kind: ExprStmt(expr) }, rest[1:])
          } else {
            ({ kind: ExprStmt(expr) }, rest)
          }
        }
        @lexer.Keyword::Else => {
          // In simple parsing mode, when we encounter an else keyword,
          // we should skip it rather than throwing an error.
          // This allows the if expression parser to handle it properly
          // in the context where it belongs.
          let rest = tokens[1:]
          // Try to skip until we find a semicolon or closing brace
          let mut current_tokens = rest
          while current_tokens.length() > 0 {
            match current_tokens[0].kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") => {
                current_tokens = current_tokens[1:]
                break
              }
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket('}') => {
                break
              }
              _ => {
                current_tokens = current_tokens[1:]
              }
            }
          }
          // Return a no-op statement to represent the skipped else
          ({ kind: ExprStmt({ kind: ExprKind::ApplyExpr({ kind: ApplyExprKind::AtomExpr({ kind: AtomExprKind::Unit }) }) }) }, current_tokens)
        }
        _ => {
          // Try to parse as an expression statement
          parse_expression_statement_with_depth(tokens, depth)
        }
      }
    }
    // Check for local function declaration (fn identifier ...)
    _ => {
      if tokens.length() >= 2 {
        let second_token = tokens[1]
        match (first_token.kind, second_token.kind) {
          (@moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Fn), 
          @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(_)) => {
            // This is a local function declaration - parse it properly
            let (local_fn, rest) = parse_local_function_with_depth(tokens, depth)
            ({ kind: LocalFunction(local_fn) }, rest)
          }
          _ => {
            // Check if this is an assignment statement (starts with identifier)
            match first_token.kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(_) => {
                // Check if this is an assignment statement
                match parse_left_value(tokens) {
                  (_, after_left) => {
                    if after_left.length() > 0 {
                      match after_left[0].kind {
                        @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(_) => {
                          // This is an assignment statement
                          let (assign_stmt, rest) = parse_assign_stmt(tokens)
                          ({ kind: AssignStmt(assign_stmt) }, rest)
                        }
                        _ => parse_expression_statement_with_depth(tokens, depth)
                      }
                    } else {
                      parse_expression_statement_with_depth(tokens, depth)
                    }
                  }
                }
              }
              _ => parse_expression_statement_with_depth(tokens, depth)
            }
          }
        }
      } else {
        parse_expression_statement_with_depth(tokens, depth)
      }
    }
  }
}


/// Parse a simple statement that uses simple expressions to avoid recursion
pub fn parse_simple_stmt(tokens: ArrayView[Token]) -> (Stmt, ArrayView[Token]) raise ParseError {
  parse_simple_stmt_with_depth(tokens, 0)
}

pub fn parse_simple_stmt_with_depth(tokens: ArrayView[Token], depth: Int) -> (Stmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input in statement")
  }

  let first_token = tokens[0]
  
  match first_token.kind {
    @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(keyword) => {
      match keyword {
        @lexer.Keyword::Let => {
          // Check if this is "let mut" or just "let"
          if tokens.length() > 1 {
            let second_token = tokens[1]
            match second_token.kind {
              @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Mut) => {
                // This is a "let mut" statement
                let (let_mut_stmt, rest) = parse_let_mut_stmt(tokens)
                ({ kind: LetMutStmt(let_mut_stmt) }, rest)
              }
              _ => {
                // This is a regular "let" statement
                let (let_stmt, rest) = parse_let_stmt(tokens)
                ({ kind: LetStmt(let_stmt) }, rest)
              }
            }
          } else {
            // Just "let" at end of input - parse as let statement (will error appropriately)
            let (let_stmt, rest) = parse_let_stmt(tokens)
            ({ kind: LetStmt(let_stmt) }, rest)
          }
        }
        @lexer.Keyword::While => {
          // While statement
          let (while_stmt, rest) = parse_while_stmt_with_depth(tokens, depth)
          ({ kind: WhileStmt(while_stmt) }, rest)
        }
        @lexer.Keyword::Return => {
          // Skip the 'return' keyword
          let after_return = tokens[1:]
          
          // Parse optional return expression (use simple expr to avoid recursion)
          let (return_expr_opt, after_expr) = if after_return.length() > 0 && 
                                              after_return[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            let (expr, rest) = parse_simple_expr_with_depth(after_return, depth + 1)
            (Some(expr), rest)
          } else {
            (None, after_return)
          }
          
          // Expect semicolon
          if after_expr.length() == 0 || after_expr[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            raise ParseError("Expected ';' at end of return statement")
          }
          
          ({ kind: ReturnStmt(return_expr_opt) }, after_expr[1:])
        }
        @lexer.Keyword::Fn => {
          // Local function declaration
          let (local_fn, rest) = parse_local_function_with_depth(tokens, depth)
          ({ kind: LocalFunction(local_fn) }, rest)
        }
        @lexer.Keyword::If => {
          // Skip if expressions to avoid infinite recursion in simple parsing
          raise ParseError("If expressions are not allowed in simple statements")
        }
        @lexer.Keyword::Else => {
          // Else keyword should not appear as a standalone statement
          // It should be handled as part of an if expression
          raise ParseError("Else keyword should be handled by if expression parser")
        }
        _ => {
          // Try to parse as an expression statement (use simple expr to avoid recursion)
          parse_simple_expression_statement_with_depth(tokens, depth)
        }
      }
    }
    // Check for assignment statement (starts with identifier)
    _ => {
      match first_token.kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::Lower(_) => {
          // Check if this is an assignment statement
          match parse_left_value(tokens) {
            (_, after_left) => {
              if after_left.length() > 0 {
                match after_left[0].kind {
                  @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(_) => {
                    // This is an assignment statement
                    let (assign_stmt, rest) = parse_assign_stmt(tokens)
                    ({ kind: AssignStmt(assign_stmt) }, rest)
                  }
                  _ => parse_simple_expression_statement_with_depth(tokens, depth)
                }
              } else {
                parse_simple_expression_statement_with_depth(tokens, depth)
              }
            }
          }
        }
        _ => parse_simple_expression_statement_with_depth(tokens, depth)
      }
    }
  }
}

/// Helper function to parse a simple expression statement (uses simple expr to avoid recursion)


fn parse_simple_expression_statement_with_depth(tokens: ArrayView[Token], depth: Int) -> (Stmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input in expression statement")
  }

  // Skip if expressions to avoid infinite recursion
  if tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) {
    raise ParseError("If expressions are not allowed in simple expression statements")
  }
  
  // Skip let statements - they should be handled by the main parsing logic
  if tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Let) {
    raise ParseError("Let statements are not allowed in simple expression statements")
  }
  
  // For non-if, non-let expressions, use a simpler approach to avoid recursion
  // Parse primary expressions only (literals, identifiers, etc.)
  let (expr, rest) = parse_simple_primary_with_depth(tokens, depth + 1)
  
  // Check if this is actually an assignment
  if rest.length() > 0 {
    match rest[0].kind {
      @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(_) => {
        // This is an assignment statement, parse it
        match parse_assign_stmt(tokens) {
          (assign_stmt, rest_after_assign) => {
            if rest_after_assign.length() > 0 && 
               rest_after_assign[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
              ({ kind: AssignStmt(assign_stmt) }, rest_after_assign[1:])
            } else {
              ({ kind: AssignStmt(assign_stmt) }, rest_after_assign)
            }
          }
        }
      }
      _ => {
        // Not an assignment, return the expression
        if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
          ({ kind: ExprStmt(expr) }, rest[1:])
        } else {
          ({ kind: ExprStmt(expr) }, rest)
        }
      }
    }
  } else {
    // No more tokens, just return the expression
    ({ kind: ExprStmt(expr) }, rest)
  }
}


/// Parse an expression statement with recursion depth tracking
fn parse_expression_statement_with_depth(tokens: ArrayView[Token], depth: Int) -> (Stmt, ArrayView[Token]) raise ParseError {
  if tokens.length() == 0 {
    raise ParseError("Unexpected end of input in expression statement")
  }

  // Check if this is a local function declaration
  if tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::Fn) {
    let (local_fn, rest) = parse_local_function_with_depth(tokens, depth)
    ({ kind: LocalFunction(local_fn) }, rest)
  } else if tokens[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(@lexer.Keyword::If) {
    let (expr, rest) = parse_expr_with_depth(tokens, depth + 1)
    // Check if the next token is a semicolon (optional for if expressions)
    if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
      ({ kind: ExprStmt(expr) }, rest[1:])
    } else {
      ({ kind: ExprStmt(expr) }, rest)
    }
  } else {
    // First, try to parse as a regular expression (use simple expr to avoid infinite recursion)
    let (expr, rest) = parse_expr_with_depth(tokens, depth + 1)
    
    // Check if this is actually an assignment
    if rest.length() > 0 {
      match rest[0].kind {
        @moonbitlang/MiniMoonbit/lexer.TokenKind::AssignOp(_) => {
          // This is an assignment statement, parse it
          match parse_assign_stmt(tokens) {
            (assign_stmt, rest_after_assign) => {
              if rest_after_assign.length() > 0 && 
                 rest_after_assign[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
                ({ kind: AssignStmt(assign_stmt) }, rest_after_assign[1:])
              } else {
                ({ kind: AssignStmt(assign_stmt) }, rest_after_assign)
              }
            }
          }
        }
        _ => {
          // Not an assignment, return the expression
          if rest.length() > 0 && rest[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(";") {
            ({ kind: ExprStmt(expr) }, rest[1:])
          } else {
            ({ kind: ExprStmt(expr) }, rest)
          }
        }
      }
    } else {
      // No more tokens, just return the expression
      ({ kind: ExprStmt(expr) }, rest)
    }
  }
}


