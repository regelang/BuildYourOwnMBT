///|
pub(all) enum KnfLeftValue {
  Ident(Name)
  ArrayAcc(Name, Name)
  FieldAcc(Name, String)
}

///|
pub fn Context::assign_stmt_to_knf(
  self : Context,
  assign_stmt : @typecheck.AssignStmt,
) -> Array[KnfStmt] raise KnfTransformError {
  let rhs_result = self.expr_to_knf(assign_stmt.expr)
  let rhs_stmts = rhs_result.0
  let rhs_expr = rhs_result.1

  match assign_stmt.op {
    @typecheck.AssignOp::Assign => {
      transform_simple_assign(self, assign_stmt.left_value, rhs_expr, rhs_stmts)
    }
    op => {
      transform_compound_assign(self, assign_stmt.left_value, op, rhs_expr, rhs_stmts)
    }
  }
}

fn transform_simple_assign(
  ctx : Context,
  left_value : @typecheck.LeftValue,
  rhs_expr : KnfExpr,
  rhs_stmts : Array[KnfStmt],
) -> Array[KnfStmt] raise KnfTransformError {
  let mut stmts = rhs_stmts
  match left_value.kind {
    @typecheck.LeftValueKind::Ident(name_str) => {
      let (lhs_name, _) = match ctx.lookup_name(name_str) {
        Some(result) => result
        None => raise KnfTransformError("Unknown identifier in assignment: " + name_str)
      }
      stmts = stmts + [Assign(lhs_name, rhs_expr)]
      stmts
    }
    @typecheck.LeftValueKind::ArrayAccess(base_lv, index_expr) => {
      let base_result = collect_left_value_place(ctx, base_lv)
      let base_stmts = base_result.0
      let base_name = base_result.1
      stmts = base_stmts

      let (index_stmts, index_expr_knf) = ctx.expr_to_knf(index_expr)
      stmts = stmts + index_stmts

      let index_type = ctx.typekind_to_knf(index_expr.ty)
      let index_name = ctx.expr_to_knf_name(index_expr_knf, index_type, stmts)

      stmts = stmts + rhs_stmts

      stmts = stmts + [ArrayPut(base_name, index_name, rhs_expr)]
      stmts
    }
    @typecheck.LeftValueKind::FieldAccess(base_lv, field_name) => {
      let base_result = collect_left_value_place(ctx, base_lv)
      let base_stmts = base_result.0
      let struct_name = base_result.1
      stmts = base_stmts + rhs_stmts

      let value_type = ctx.type_to_knf(left_value.ty)
      let value_name = ctx.expr_to_knf_name_always_temp(rhs_expr, value_type, stmts)

      stmts = stmts + [StructFieldSet(struct_name, field_name, value_name)]
      stmts
    }
  }
}

fn transform_compound_assign(
  ctx : Context,
  left_value : @typecheck.LeftValue,
  assign_op : @typecheck.AssignOp,
  rhs_expr : KnfExpr,
  rhs_stmts : Array[KnfStmt],
) -> Array[KnfStmt] raise KnfTransformError {
  let lhs_result = collect_left_value_place(ctx, left_value)
  let lhs_stmts = lhs_result.0
  let lhs_name = lhs_result.1
  let mut stmts = lhs_stmts + rhs_stmts

  let lhs_type = ctx.type_to_knf(left_value.ty)
  let rhs_type = ctx.type_to_knf(left_value.ty)
  let rhs_name = ctx.expr_to_knf_name(rhs_expr, rhs_type, stmts)

  let binary_op = match assign_op {
    @typecheck.AssignOp::PlusAssign => BinaryOp::Add
    @typecheck.AssignOp::MinusAssign => BinaryOp::Sub
    @typecheck.AssignOp::MultAssign => BinaryOp::Mul
    @typecheck.AssignOp::DivAssign => BinaryOp::Div
    @typecheck.AssignOp::ModAssign => BinaryOp::Mod
    _ => raise KnfTransformError("Unsupported compound assignment operator")
  }

  let temp_name = ctx.add_temp(lhs_type)
  stmts = stmts + [Let(temp_name, lhs_type, KnfExpr::Binary(binary_op, lhs_name, rhs_name))]

  let assign_stmt = transform_simple_assign(ctx, left_value, KnfExpr::Ident(temp_name), stmts)
  assign_stmt
}

fn collect_left_value_place(
  ctx : Context,
  left_value : @typecheck.LeftValue,
) -> (Array[KnfStmt], Name) raise KnfTransformError {
  match left_value.kind {
    @typecheck.LeftValueKind::Ident(name_str) => {
      let (name, _) = match ctx.lookup_name(name_str) {
        Some(result) => result
        None => raise KnfTransformError("Unknown identifier in assignment: " + name_str)
      }
      ([], name)
    }
    @typecheck.LeftValueKind::ArrayAccess(base_lv, index_expr) => {
      let base_result = collect_left_value_place(ctx, base_lv)
      let mut stmts = base_result.0
      let array_name = base_result.1

      let (index_stmts, index_knf) = ctx.expr_to_knf(index_expr)
      stmts = stmts + index_stmts

      let index_type = ctx.typekind_to_knf(index_expr.ty)
      let index_name = ctx.expr_to_knf_name(index_knf, index_type, stmts)

      // Need to load element for nested access
      let elem_type = ctx.type_to_knf(left_value.ty)
      let temp_name = ctx.expr_to_knf_name(
        KnfExpr::ArrayAccess(array_name, index_name),
        elem_type,
        stmts,
      )
      (stmts, temp_name)
    }
    @typecheck.LeftValueKind::FieldAccess(base_lv, field_name) => {
      let base_result = collect_left_value_place(ctx, base_lv)
      let stmts = base_result.0
      let base_name = base_result.1

      let field_type = ctx.type_to_knf(left_value.ty)
      let temp_name = ctx.expr_to_knf_name(
        KnfExpr::FieldAccess(base_name, field_name),
        field_type,
        stmts,
      )
      (stmts, temp_name)
    }
  }
}
