///|
pub fn Context::atom_expr_to_knf(
  self : Context,
  atom_expr : @typecheck.AtomExpr,
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  match atom_expr.kind {
    @typecheck.AtomExprKind::Int(value) => ([], Int(value))
    @typecheck.AtomExprKind::Double(value) => ([], Double(value))
    @typecheck.AtomExprKind::Bool(value) => ([], Bool(value))
    @typecheck.AtomExprKind::String(value) => ([], String(value))
    @typecheck.AtomExprKind::Unit => ([], Unit)
    @typecheck.AtomExprKind::Ident(name) => {
      match self.lookup_name(name) {
        Some((knf_name, knf_type)) => {
          // 检查是否是无参数的枚举构造器
          // 只有真正的枚举构造器才自动生成调用
          if self.is_enum_constructor(name) {
            match knf_type {
              Type::Function(params, _ret_ty) => {
                if params.length() == 0 {
                  // 无参数的枚举构造器，生成调用
                  ([], Call(knf_name, []))
                } else {
                  // 有参数的枚举构造器，返回标识符
                  ([], Ident(knf_name))
                }
              }
              _ => ([], Ident(knf_name))
            }
          } else {
            // 不是枚举构造器，直接返回标识符
            ([], Ident(knf_name))
          }
        }
        None => raise KnfTransformError("Unknown identifier: " + name)
      }
    }
    @typecheck.AtomExprKind::EnumVariant(enum_name, variant_name) => {
      // For enum variant like Color::Red, treat it as a constructor call
      let constructor_name = Name::{ id: enum_name + "::" + variant_name, slot: 0 }
      ([], Call(constructor_name, []))
    }
    @typecheck.AtomExprKind::Paren(expr) => {
      let (stmts, knf_expr) = self.expr_to_knf(expr)
      (stmts, knf_expr)
    }
    @typecheck.AtomExprKind::Tuple(exprs) => {
      let mut stmts : Array[KnfStmt] = []
      let mut names : Array[Name] = []
      
      for expr in exprs {
        let (expr_stmts, expr_knf) = self.expr_to_knf(expr)
        stmts = stmts + expr_stmts
        
        // 只有在表达式不是简单标识符时才创建临时变量
        match expr_knf {
          Ident(name) => {
            // 直接使用标识符，不创建临时变量
            names = names + [name]
          }
          _ => {
            // 对于复杂表达式，创建临时变量
            let temp_type = self.typekind_to_knf(expr.ty)
            let temp_name = self.add_temp(temp_type)
            stmts = stmts + [Let(temp_name, temp_type, expr_knf)]
            names = names + [temp_name]
          }
        }
      }
      
      (stmts, TupleLiteral(names))
    }
    @typecheck.AtomExprKind::Array(exprs) => {
      let mut stmts : Array[KnfStmt] = []
      let mut names : Array[Name] = []
      
      for expr in exprs {
        let (expr_stmts, expr_knf) = self.expr_to_knf(expr)
        stmts = stmts + expr_stmts
        
        match expr_knf {
          Ident(name) => {
            names = names + [name]
          }
          _ => {
            let temp_type = self.typekind_to_knf(expr.ty)
            let temp_name = self.add_temp(temp_type)
            stmts = stmts + [Let(temp_name, temp_type, expr_knf)]
            names = names + [temp_name]
          }
        }
      }
      
      let element_type = match atom_expr.ty {
        @typecheck.TypeKind::Array(elem_ty) => self.typekind_to_knf(elem_ty)
        _ => raise KnfTransformError("Array type mismatch")
      }
      
      (stmts, ArrayLiteral(element_type, names))
    }
    @typecheck.AtomExprKind::ArrayMake(size_expr, init_expr) => {
      let (size_stmts, size_knf) = self.expr_to_knf(size_expr)
      let (init_stmts, init_knf) = self.expr_to_knf(init_expr)
      
      let size_type = self.typekind_to_knf(size_expr.ty)
      let size_temp = self.add_temp(size_type)
      let size_let = Let(size_temp, size_type, size_knf)
      
      let init_type = self.typekind_to_knf(init_expr.ty)
      let init_temp = self.add_temp(init_type)
      let init_let = Let(init_temp, init_type, init_knf)
      
      let all_stmts = size_stmts + [size_let] + init_stmts + [init_let]
      
      (all_stmts, ArrayMake(size_temp, init_temp))
    }
    @typecheck.AtomExprKind::StructConstruct(sc_expr) => {
      // 简化处理：现在只处理基本字段赋值
      let mut stmts : Array[KnfStmt] = []
      let mut field_names : Array[(String, Name)] = []
      
      for i = 0; i < sc_expr.fields.length(); i = i + 1 {
        let (field_name, field_expr) = sc_expr.fields[i]
        let (field_stmts, field_knf) = self.expr_to_knf(field_expr)
        stmts = stmts + field_stmts
        
        let field_type = self.typekind_to_knf(field_expr.ty)
        let field_temp = self.add_temp(field_type)
        stmts = stmts + [Let(field_temp, field_type, field_knf)]
        field_names = field_names + [(field_name, field_temp)]
      }
      
      (stmts, CreateStruct(sc_expr.name, field_names))
    }
  }
}
