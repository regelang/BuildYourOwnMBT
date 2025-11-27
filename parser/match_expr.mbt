/// Match 表达式
pub(all) struct MatchExpr {
  scrutinee : Expr              // 被匹配的表达式
  arms : Array[MatchArm]        // 匹配分支
} derive(Show, Eq)

/// Match 分支
pub(all) struct MatchArm {
  pattern : Pattern             // 模式
  body : Expr                   // 分支体
} derive(Show, Eq)

/// 解析 match 表达式
/// 
/// 语法：
/// match color {
///   Red => (255, 0, 0);
///   RGB(r, g, b) => (r, g, b);
/// }
pub fn parse_match_expr(
  tokens : ArrayView[Token]
) -> (MatchExpr, ArrayView[Token]) raise ParseError {
  // 期望 'match' 关键字
  if tokens.length() == 0 || tokens[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Keyword(
    @moonbitlang/MiniMoonbit/lexer.Keyword::Match,
  ) {
    raise ParseError("Expected 'match' keyword")
  }
  
  // 解析被匹配的表达式
  let (scrutinee, rest) = parse_expr(tokens[1:])
  
  // 期望 '{'
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '{',
  ) {
    raise ParseError("Expected '{' after match expression")
  }
  
  // 解析匹配分支
  let (arms, after_arms) = parse_match_arms(rest[1:])
  
  // 期望 '}'
  if after_arms.length() == 0 || after_arms[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '}',
  ) {
    raise ParseError("Expected '}' at end of match expression")
  }
  
  (MatchExpr::{ scrutinee, arms }, after_arms[1:])
}

/// 解析匹配分支列表
fn parse_match_arms(
  tokens : ArrayView[Token]
) -> (Array[MatchArm], ArrayView[Token]) raise ParseError {
  let arms : Array[MatchArm] = []
  let mut rest = tokens
  
  // 解析分支直到遇到 '}'
  while rest.length() > 0 && rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '}',
  ) {
    let (arm, after_arm) = parse_match_arm(rest)
    arms.push(arm)
    rest = after_arm
  }
  
  if arms.length() == 0 {
    raise ParseError("Match expression must have at least one arm")
  }
  
  (arms, rest)
}

/// 解析单个匹配分支
/// 
/// 语法：Red => (255, 0, 0); 或 Red => (255, 0, 0)
/// 注意：最后一个分支的分号是可选的
fn parse_match_arm(
  tokens : ArrayView[Token]
) -> (MatchArm, ArrayView[Token]) raise ParseError {
  // 解析模式
  let (pattern, rest) = parse_pattern(tokens)
  
  // 期望 '=>'
  if rest.length() == 0 || rest[0].kind != @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
    "=>",
  ) {
    raise ParseError("Expected '=>' after pattern")
  }
  
  // 解析分支体表达式
  let (body, after_body) = parse_expr(rest[1:])
  
  // 检查下一个token
  // 如果是分号，消费它
  // 如果是 '}'，说明是最后一个分支，分号可选
  // 否则，报错要求分号
  let final_rest = if after_body.length() > 0 && after_body[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Symbol(
    ";",
  ) {
    after_body[1:]
  } else if after_body.length() > 0 && after_body[0].kind == @moonbitlang/MiniMoonbit/lexer.TokenKind::Bracket(
    '}',
  ) {
    // 最后一个分支，分号可选
    after_body
  } else {
    raise ParseError("Expected ';' after match arm body")
  }
  
  (MatchArm::{ pattern, body }, final_rest)
}
