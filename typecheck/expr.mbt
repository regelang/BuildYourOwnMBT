///|
pub(all) struct Expr {
  kind : ExprKind
  ty : TypeKind
} derive(Show)

///|
pub(all) enum ExprKind {
  ApplyExpr(ApplyExpr)
  BlockExpr(BlockExpr)
  NotExpr(Expr)
  NegExpr(Expr)
  BinaryExpr(BinaryOp, Expr, Expr)
  IfExpr(IfExpr)
  MatchExpr(MatchExpr)
} derive(Show)

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
pub fn binop_is_cmp(bin_op : BinaryOp) -> Bool {
  match bin_op {
    Eq => true
    NE => true
    LT => true
    GT => true
    LE => true
    GE => true
    _ => false
  }
}

///|
pub fn binop_is_bitwise(bin_op : BinaryOp) -> Bool {
  bin_op is (BitAnd | BitOr)
}

///|
pub fn binop_is_arithmetic(bin_op : BinaryOp) -> Bool {
  match bin_op {
    Add => true
    Sub => true
    Mul => true
    Div => true
    Mod => true
    _ => false
  }
}

///|
pub fn parser_binop_to_typecheck_binop(
  tok_bin_op : @parser.BinaryOp,
) -> BinaryOp {
  match tok_bin_op {
    Add => Add
    Sub => Sub
    Mul => Mul
    Div => Div
    Mod => Mod
    ShiftLeft => ShiftLeft
    ShiftRight => ShiftRight
    Eq => Eq
    NE => NE
    LT => LT
    GT => GT
    LE => LE
    GE => GE
    And => And
    Or => Or
    BitAnd => BitAnd
    BitOr => BitOr
  }
}

///|
pub fn Context::check_expr(
  self : Self,
  expr : @parser.Expr,
) -> Expr raise TypeCheckError {
  match expr.kind {
    @parser.ExprKind::ApplyExpr(apply_expr) => {
      let checked_apply = self.check_apply_expr(apply_expr)
      Expr::{
        kind: ExprKind::ApplyExpr(checked_apply),
        ty: checked_apply.ty
      }
    }
    @parser.ExprKind::BlockExpr(block_expr) => {
      let checked_block = self.check_block_expr(block_expr)
      Expr::{
        kind: ExprKind::BlockExpr(checked_block),
        ty: checked_block.ty
      }
    }
    @parser.ExprKind::IfExpr(if_expr) => {
      let checked_if = self.check_if_expr(if_expr)
      Expr::{
        kind: ExprKind::IfExpr(checked_if),
        ty: checked_if.ty
      }
    }
    @parser.ExprKind::NotExpr(inner_expr) => {
      let checked_inner = self.check_expr(inner_expr)
      match checked_inner.ty {
        TypeKind::Bool => {
          Expr::{
            kind: ExprKind::NotExpr(checked_inner),
            ty: TypeKind::Bool
          }
        }
        _ => raise TypeCheckError("Operator '!' expects Bool operand")
      }
    }
    @parser.ExprKind::NegExpr(inner_expr) => {
      let checked_inner = self.check_expr(inner_expr)
      match checked_inner.ty {
        TypeKind::Int => {
          Expr::{
            kind: ExprKind::NegExpr(checked_inner),
            ty: TypeKind::Int
          }
        }
        TypeKind::Double => {
          Expr::{
            kind: ExprKind::NegExpr(checked_inner),
            ty: TypeKind::Double
          }
        }
        _ => raise TypeCheckError("Unary '-' expects Int or Double operand")
      }
    }
    @parser.ExprKind::BinaryExpr(op, left, right) => {
      // Debug: print parser-level expression for easier tracing
      println("DEBUG: parser binary expr: " + expr.to_string());
      let tc_op = parser_binop_to_typecheck_binop(op)
      let left_checked = self.check_expr(left)
      let right_checked = self.check_expr(right)
      


  // Debug: show operand types for arithmetic ops
  println("DEBUG: binary op types - left: " + self.type_to_string(left_checked.ty) + ", right: " + self.type_to_string(right_checked.ty));
  let result_ty = if binop_is_arithmetic(tc_op) {
        let left_resolved = self.resolve_type_kind(left_checked.ty)
        let right_resolved = self.resolve_type_kind(right_checked.ty)

        if tc_op is BinaryOp::Mod {
          let left_ok = self.is_type_compatible(left_checked.ty, TypeKind::Int)
          let right_ok = self.is_type_compatible(right_checked.ty, TypeKind::Int)
          if !left_ok || !right_ok {
            raise TypeCheckError("Modulo expects Int operands")
          }
          TypeKind::Int
        } else {
          let mut expected_ty = TypeKind::Int
          if left_resolved is TypeKind::Double || right_resolved is TypeKind::Double {
            expected_ty = TypeKind::Double
          }

          let mut ok = self.is_type_compatible(left_checked.ty, expected_ty)
          if !ok {
            let l = self.type_to_string(left_checked.ty)
            let r = self.type_to_string(right_checked.ty)
            raise TypeCheckError("Arithmetic operands must both be Int or Double (left=" + l + ", right=" + r + ")")
          }
          ok = self.is_type_compatible(right_checked.ty, expected_ty)
          if !ok {
            let l = self.type_to_string(left_checked.ty)
            let r = self.type_to_string(right_checked.ty)
            raise TypeCheckError("Arithmetic operands must both be Int or Double (left=" + l + ", right=" + r + ")")
          }

          self.resolve_type_kind(expected_ty)
        }
      } else if binop_is_cmp(tc_op) {
        match tc_op {
          BinaryOp::Eq | BinaryOp::NE => {
            if !self.is_type_compatible(left_checked.ty, right_checked.ty) {
              raise TypeCheckError("Equality operands must have the same type")
            }

            let resolved_left = self.resolve_type_kind(left_checked.ty)
            match resolved_left {
              TypeKind::Int
              | TypeKind::Double
              | TypeKind::Bool
              | TypeKind::String
              | TypeKind::TypeVar(_) => TypeKind::Bool
              _ => raise TypeCheckError("Equality operands must have the same type")
            }
          }
          _ => {
            let left_resolved = self.resolve_type_kind(left_checked.ty)
            let right_resolved = self.resolve_type_kind(right_checked.ty)

            let mut expected_ty = TypeKind::Int
            if left_resolved is TypeKind::Double || right_resolved is TypeKind::Double {
              expected_ty = TypeKind::Double
            }

            let mut ok = self.is_type_compatible(left_checked.ty, expected_ty)
            if !ok {
              raise TypeCheckError("Comparison operands must be Int or Double")
            }
            ok = self.is_type_compatible(right_checked.ty, expected_ty)
            if !ok {
              raise TypeCheckError("Comparison operands must be Int or Double")
            }

            TypeKind::Bool
          }
        }
      } else {
        match tc_op {
          BinaryOp::And | BinaryOp::Or => {
            // For logical operators, both operands must be Bool
            // Use is_type_compatible to allow unification with Bool
            let mut ok = self.is_type_compatible(left_checked.ty, TypeKind::Bool)
            if !ok {
              let left_ty_str = self.type_to_string(left_checked.ty)
              raise TypeCheckError("Logical operands must be Bool (left operand has type: " + left_ty_str + ")")
            }
            ok = self.is_type_compatible(right_checked.ty, TypeKind::Bool)
            if !ok {
              let right_ty_str = self.type_to_string(right_checked.ty)
              raise TypeCheckError("Logical operands must be Bool (right operand has type: " + right_ty_str + ")")
            }
            
            TypeKind::Bool
          }
          _ => raise TypeCheckError("Unsupported binary operator")
        }
      }

      Expr::{
        kind: ExprKind::BinaryExpr(tc_op, left_checked, right_checked),
        ty: result_ty
      }
    }
    @parser.ExprKind::MatchExpr(match_expr) => {
      let checked_match = self.check_match_expr(match_expr)
      Expr::{
        kind: ExprKind::MatchExpr(checked_match),
        ty: checked_match.ty
      }
    }
  }
}
