///|
pub fn Context::block_codegen(
  self : Self,
  block : @knf.KnfBlock,
) -> &@llvm.Value? raise {
  let current_func = self.builder.getInsertFunction()

  let block_bb = current_func.addBasicBlock()
  let after_bb = current_func.addBasicBlock()

  let _ = self.builder.createBr(block_bb)

  self.builder.setInsertPoint(block_bb)

  let mut last_value : &@llvm.Value? = None
  let mut i = 0
  while i < block.stmts.length() {
    // Check current insert block, not the original block_bb
    let current_bb = self.builder.getInsertBlock()
    if current_bb.getTerminator() is Some(_) {
      break
    }

    let stmt = block.stmts[i]
    match stmt {
      @knf.KnfStmt::ExprStmt(expr) => {
        last_value = self.expr_codegen(expr)
      }
      @knf.KnfStmt::Return(_) => {
        self.stmt_codegen(stmt)
        last_value = None
      }
      @knf.KnfStmt::ReturnUnit => {
        self.stmt_codegen(stmt)
        last_value = None
      }
      _ => {
        self.stmt_codegen(stmt)
        last_value = None
      }
    }
    i = i + 1
  }

  // Check current insert block for terminator
  let final_bb = self.builder.getInsertBlock()
  if final_bb.getTerminator() is None {
    let _ = self.builder.createBr(after_bb)
  }

  self.builder.setInsertPoint(after_bb)
    match block.ty {
      @knf.Type::Unit => None
      _ => match last_value {
        Some(value) => Some(value)
        None => {
          // Patch: If block returns non-Unit and last stmt is ExprStmt, treat expr as block result value
          if block.stmts.length() > 0 {
            let last_stmt = block.stmts[block.stmts.length() - 1]
            match last_stmt {
              @knf.KnfStmt::ExprStmt(expr) => {
                let val = self.expr_codegen(expr)
                match val {
                  Some(v) => Some(v)
                  None => raise CodegenError("Block expression missing result value (ExprStmt codegen returned None)")
                }
              }
              @knf.KnfStmt::Return(_) | @knf.KnfStmt::ReturnUnit => None
              _ => raise CodegenError("Block expression missing result value")
            }
          } else {
            raise CodegenError("Block expression missing result value (empty block)")
          }
        }
      }
    }
}
