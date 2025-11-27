///| Match 表达式
pub(all) struct MatchExpr {
  scrutinee : Expr  // 被匹配的表达式
  arms : Array[MatchArm]  // 匹配分支
  ty : TypeKind  // 整个 match 表达式的类型
} derive(Show)

///| Match 分支
pub(all) struct MatchArm {
  pattern : Pattern  // 模式
  body : Expr  // 分支体
} derive(Show)



///| 检查 match 表达式
pub fn Context::check_match_expr(
  self : Context,
  match_expr : @parser.MatchExpr
) -> MatchExpr raise TypeCheckError {
  // 检查被匹配的表达式
  let checked_scrutinee = self.check_expr(match_expr.scrutinee)
  let scrutinee_ty = self.resolve_type_kind(checked_scrutinee.ty)
  
  // 检查每个分支
  let mut checked_arms : Array[MatchArm] = []
  let mut result_ty : TypeKind? = None
  let mut i = 0
  
  while i < match_expr.arms.length() {
    let arm = match_expr.arms[i]
    
    // 进入新作用域
    self.enter_scope()
    
    // 检查模式，将模式中的变量绑定到环境中
    // Use true for mutable to match KNF transformation which uses LetMut
    let checked_pattern = self.check_pattern(arm.pattern, scrutinee_ty, true)
    
    // 检查分支体
    let checked_body = self.check_expr(arm.body)
    let body_ty = self.resolve_type_kind(checked_body.ty)
    
    // 退出作用域
    self.exit_scope()
    
    // 检查所有分支的返回类型是否一致
    match result_ty {
      None => result_ty = Some(body_ty)
      Some(expected_ty) => {
        // First try regular type compatibility
        let mut compatible = self.is_type_compatible(expected_ty, body_ty)
        // If that fails, try generic compatibility for cases involving generic types
        if !compatible {
          compatible = self.is_generic_compatible(expected_ty, body_ty)
        }
        if !compatible {
          raise TypeCheckError("Match arms have incompatible types")
        }
        // 更新 result_ty 为统一后的类型
        result_ty = Some(self.resolve_type_kind(expected_ty))
      }
    }
    
    checked_arms = checked_arms + [MatchArm::{
      pattern: checked_pattern,
      body: Expr::{ kind: checked_body.kind, ty: body_ty }
    }]
    
    i = i + 1
  }
  
  let final_ty = match result_ty {
    Some(ty) => ty
    None => TypeKind::Unit  // 没有分支的情况（不应该发生）
  }
  
  MatchExpr::{
    scrutinee: Expr::{ kind: checked_scrutinee.kind, ty: scrutinee_ty },
    arms: checked_arms,
    ty: final_ty
  }
}
