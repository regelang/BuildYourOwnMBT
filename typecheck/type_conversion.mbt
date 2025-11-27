///|
fn TypeKind::from_parser_type(ty : @parser.TypeKind) -> TypeKind {
  match ty {
    @parser.TypeKind::Unit => TypeKind::Unit
    @parser.TypeKind::Bool => TypeKind::Bool
    @parser.TypeKind::Int => TypeKind::Int
    @parser.TypeKind::Double => TypeKind::Double
    @parser.TypeKind::String => TypeKind::String
    @parser.TypeKind::Tuple(types) => {
      TypeKind::Tuple(types.map(fn(t) { TypeKind::from_parser_type(t) }))
    }
    @parser.TypeKind::Array(elem_ty) => {
      let elem = TypeKind::from_parser_type(elem_ty)
      TypeKind::Array(elem)
    }
    @parser.TypeKind::Function(param_tys, ret_ty) => {
      let ret = TypeKind::from_parser_type(ret_ty)
      TypeKind::Function(
        param_tys.map(fn(t) { TypeKind::from_parser_type(t) }),
        ret
      )
    }
    @parser.TypeKind::GenericEnum(name, type_args) => {
      TypeKind::GenericEnum(
        name,
        type_args.map(fn(t) { TypeKind::from_parser_type(t) })
      )
    }
    @parser.TypeKind::Defined(name) => {
      TypeKind::Struct(name)
    }
  }
}

///|
fn ExprKind::from_parser_expr(expr_kind : @parser.ExprKind) -> ExprKind {
  match expr_kind {
    @parser.ExprKind::ApplyExpr(_apply_expr) => {
      // For now, just return a simple Unit expression
      // We'll implement the full conversion later
      ExprKind::ApplyExpr(ApplyExpr::{
        kind: ApplyExprKind::AtomExpr(AtomExpr::{
          kind: AtomExprKind::Unit,
          ty: TypeKind::Unit
        }),
        ty: TypeKind::Unit
      })
    }
    @parser.ExprKind::BlockExpr(_block_expr) => {
      // For now, create a simple block with no statements
      // The actual statement conversion will be implemented later
      ExprKind::BlockExpr(BlockExpr::{
        stmts: [],
        ty: TypeKind::Unit
      })
    }
    @parser.ExprKind::NotExpr(inner_expr) => {
      // For now, we'll just create a placeholder NotExpr with Bool type
      // The actual type checking will be done during the type checking phase
      ExprKind::NotExpr(Expr::{
        kind: ExprKind::from_parser_expr(inner_expr.kind),
        ty: TypeKind::Bool
      })
    }
    @parser.ExprKind::NegExpr(inner_expr) => {
      // For now, we'll just create a placeholder NegExpr with Int type
      // The actual type checking will be done during the type checking phase
      ExprKind::NegExpr(Expr::{
        kind: ExprKind::from_parser_expr(inner_expr.kind),
        ty: TypeKind::Int
      })
    }
    @parser.ExprKind::BinaryExpr(op, left_expr, right_expr) => {
      // Convert the operator
      let op = match op {
        @parser.BinaryOp::Add => BinaryOp::Add
        @parser.BinaryOp::Sub => BinaryOp::Sub
        @parser.BinaryOp::Mul => BinaryOp::Mul
        @parser.BinaryOp::Div => BinaryOp::Div
        @parser.BinaryOp::Mod => BinaryOp::Mod
        @parser.BinaryOp::ShiftLeft => BinaryOp::ShiftLeft
        @parser.BinaryOp::ShiftRight => BinaryOp::ShiftRight
        @parser.BinaryOp::Eq => BinaryOp::Eq
        @parser.BinaryOp::NE => BinaryOp::NE
        @parser.BinaryOp::LT => BinaryOp::LT
        @parser.BinaryOp::GT => BinaryOp::GT
        @parser.BinaryOp::LE => BinaryOp::LE
        @parser.BinaryOp::GE => BinaryOp::GE
        @parser.BinaryOp::And => BinaryOp::And
        @parser.BinaryOp::Or => BinaryOp::Or
        @parser.BinaryOp::BitAnd => BinaryOp::BitAnd
        @parser.BinaryOp::BitOr => BinaryOp::BitOr
      }
      
      // Convert left and right expressions
      let left = Expr::{
        kind: ExprKind::from_parser_expr(left_expr.kind),
        ty: TypeKind::Any  // Will be updated during type checking
      }
      
      let right = Expr::{
        kind: ExprKind::from_parser_expr(right_expr.kind),
        ty: TypeKind::Any  // Will be updated during type checking
      }
      
      // Create the binary expression
      ExprKind::BinaryExpr(op, left, right)
    }
    @parser.ExprKind::IfExpr(if_expr) => {
      // Convert condition
      let cond_expr = Expr::{
        kind: ExprKind::from_parser_expr(if_expr.cond.kind),
        ty: TypeKind::Bool
      }
      
      // Convert then block (placeholder for now)
      let then_block = BlockExpr::{
        stmts: [],  // Will be filled in later
        ty: TypeKind::Unit
      }
      
      // Convert else block if it exists (placeholder for now)
      // For now, we'll just use None for the else block
      // The actual conversion will be implemented later
      let else_block = None
      
      // Create the if expression
      ExprKind::IfExpr(IfExpr::{
        cond: cond_expr,
        then_block: then_block,
        else_block: else_block,
        ty: TypeKind::Unit  // Will be updated during type checking
      })
    }
    @parser.ExprKind::MatchExpr(match_expr) => {
      // Convert scrutinee expression
      let scrutinee = Expr::{
        kind: ExprKind::from_parser_expr(match_expr.scrutinee.kind),
        ty: TypeKind::Any  // Will be updated during type checking
      }
      
      // Convert match arms
      let arms = match_expr.arms.map(fn(arm) {
        // Convert pattern (placeholder for now)
        let pattern = Pattern::from_parser_pattern(arm.pattern)
        
        // Convert body expression
        let body = Expr::{
          kind: ExprKind::from_parser_expr(arm.body.kind),
          ty: TypeKind::Any  // Will be updated during type checking
        }
        
        MatchArm::{ pattern, body }
      })
      
      // Create the match expression
      ExprKind::MatchExpr(MatchExpr::{
        scrutinee,
        arms,
        ty: TypeKind::Any  // Will be updated during type checking
      })
    }
  }
}

///| Convert parser Pattern to typecheck Pattern
fn Pattern::from_parser_pattern(pattern : @parser.Pattern) -> Pattern {
  match pattern.kind {
    @parser.PatternKind::Wildcard => {
      Pattern::{ kind: PatternKind::Wildcard }
    }
    @parser.PatternKind::Ident(name) => {
      Pattern::{ kind: PatternKind::Ident(name) }
    }
    @parser.PatternKind::Tuple(sub_patterns) => {
      let converted_patterns = sub_patterns.map(fn(p) { Pattern::from_parser_pattern(p) })
      Pattern::{ kind: PatternKind::Tuple(converted_patterns) }
    }
    @parser.PatternKind::Constructor(name, sub_patterns) => {
      let converted_patterns = sub_patterns.map(fn(p) { Pattern::from_parser_pattern(p) })
      Pattern::{ kind: PatternKind::Constructor(name, converted_patterns) }
    }
  }
}
