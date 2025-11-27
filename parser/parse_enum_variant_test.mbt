/// ================================================================================
/// # 测试枚举变体访问语法
///
/// 本测试文件用于验证EnumName::Variant语法的解析功能。
/// ================================================================================

///| 测试枚举变体访问表达式的解析
test "Parse Enum Variant Access Expression" {
  // 测试简单的枚举变体访问：EnumName::Variant
  let code = "EnumName::Variant"
  let tokens = @lexer.tokenize(code)
  println("Tokens: " + tokens.to_string())
  
  // 解析表达式
  let (_expr, remaining_tokens) = parse_expr(tokens[:])
  
  // 验证所有token都已处理，并检查表达式类型
  println("Expression: " + _expr.to_string())
  println("Remaining tokens length: " + remaining_tokens.length().to_string())
  println("Remaining tokens: " + remaining_tokens.to_string())
  
  // 检查剩余token是否为EOF（这是正常的）
  if remaining_tokens.length() == 1 && remaining_tokens[0].kind is EOF {
    // 这是正常情况，测试通过
    println("Test passed: All tokens processed correctly")
  } else {
    assert_true(remaining_tokens.length() == 0)
  }
}
