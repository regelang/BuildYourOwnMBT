///|
pub(all) enum KnfStmt {
  Let(Name, Type, KnfExpr) // let a : Int = 42;
  LetMut(Name, Type, KnfExpr) // let mut a : Int = 0;
  Assign(Name, KnfExpr) // a = 10;
  ArrayPut(Name, Name, KnfExpr) // arr[3] = 5;
  StructFieldSet(Name, String, Name) // point.x = 10;
  While(KnfBlock, KnfBlock) // while (cond) { ... }
  ExprStmt(KnfExpr) // expr;
  Return(KnfExpr) // return expr;
  ReturnUnit // return;
  ClosureDef(KnfClosure) // closure definition
}

///|
pub fn Context::stmt_to_knf(
  self : Context,
  stmt : @typecheck.Stmt,
) -> Array[KnfStmt] raise KnfTransformError {
  match stmt.kind {
    @typecheck.StmtKind::LetStmt(let_stmt) => self.let_stmt_to_knf(let_stmt)
    @typecheck.StmtKind::LetMutStmt(let_mut_stmt) => self.let_mut_stmt_to_knf(let_mut_stmt)
    @typecheck.StmtKind::AssignStmt(assign_stmt) => self.assign_stmt_to_knf(assign_stmt)
    @typecheck.StmtKind::ExprStmt(expr) => {
      let (expr_stmts, knf_expr) = self.expr_to_knf(expr)
      expr_stmts + [ExprStmt(knf_expr)]
    }
    @typecheck.StmtKind::ReturnStmt(expr_opt) => {
      match expr_opt {
        Some(expr) => {
          let (expr_stmts, knf_expr) = self.expr_to_knf(expr)
          expr_stmts + [Return(knf_expr)]
        }
        None => [ReturnUnit]
      }
    }
    @typecheck.StmtKind::WhileStmt(while_stmt) => self.while_stmt_to_knf(while_stmt)
    @typecheck.StmtKind::LocalFunction(local_func) => {
      let closure = self.local_function_to_knf(local_func)
      [ClosureDef(closure)]
    }
  }
}

///|
pub fn KnfStmt::to_string(self : KnfStmt, ident? : Int = 0) -> String {
  let s = match self {
    Let(name, ty, expr) => "let \{name} : \{ty} = \{expr};"
    LetMut(name, ty, expr) => "let mut \{name} : \{ty} = \{expr};"
    Assign(name, expr) => "\{name} = \{expr};"
    ArrayPut(array_name, index_name, value_expr) =>
      "\{array_name}[\{index_name}] = \{value_expr};"
    StructFieldSet(struct_name, field_name, value_name) =>
      "\{struct_name}.\{field_name} = \{value_name};"
    While(cond_block, body_block) =>
      if cond_block.stmts.length() <= 3 {
        let cond_str = cond_block.nested_to_string()
        let body_str = body_block.to_string(ident)
        "while \{cond_str} \{body_str}"
      } else {
        let cond_str = cond_block.to_string(ident)
        let body_str = body_block.to_string(ident)
        "while \{cond_str} \{body_str}"
      }
    ExprStmt(expr) => {
      let expr_str = expr.to_string(ident~)
      "\{expr_str};"
    }
    Return(expr) => "return \{expr};"
    ReturnUnit => "return;"
    ClosureDef(closure) => closure.to_string(ident~)
  }
  let indent_str = " ".repeat(ident)
  "\{indent_str}\{s}"
}

///|
pub impl Show for KnfStmt with output(self, logger) {
  logger.write_string(self.to_string(ident=0))
}
