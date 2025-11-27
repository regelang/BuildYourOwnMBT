/// 将 parser 的 TopLet 转换为类型检查器的内部表示
/// 
/// 参数：
/// - parser_top_let: parser 产生的顶层 let 绑定
/// 
/// 返回：类型检查器使用的 TopLet 结构
pub fn convert_top_let(parser_top_let : @parser.TopLet) -> TopLet {
  // 转换类型注解
  let ty = match parser_top_let.ty {
    Some(t) => Type::{
      kind: TypeKind::from_parser_type(t.kind),
      mutable: false  // 顶层 let 绑定总是不可变的
    }
    None => Type::{
      kind: TypeKind::Any,  // 类型将被推导
      mutable: false
    }
  }
  
  // 转换表达式
  let expr = Expr::{
    kind: ExprKind::from_parser_expr(parser_top_let.expr.kind),
    ty: TypeKind::Unit  // 将在类型检查期间更新
  }
  
  TopLet::{
    name: parser_top_let.name,
    ty: ty,
    expr: expr
  }
}

/// 将 parser 的 TopFunction 转换为类型检查器的内部表示
/// 
/// 参数：
/// - parser_func: parser 产生的顶层函数
/// 
/// 返回：类型检查器使用的 TopFunction 结构
pub fn convert_top_function(parser_func : @parser.TopFunction) -> TopFunction {
  // Note: Generic type parameters (type_param) are currently ignored
  // Full generic support would require monomorphization or type erasure
  
  // 转换参数列表
  let param_list = parser_func.param_list.map(fn(param) {
    Param::{
      name: param.name,
      ty: TypeKind::from_parser_type(param.ty.kind)  // 直接转换为 TypeKind
    }
  })
  
  // 获取返回类型
  let ret_ty = Type::{
    kind: TypeKind::from_parser_type(parser_func.ret_ty.kind),
    mutable: false
  }
  
  // 转换函数体（初始为空，将在类型检查期间填充）
  let body = BlockExpr::{
    stmts: [],
    ty: TypeKind::Unit
  }
  
  TopFunction::{
    fname: parser_func.fname,
    param_list: param_list,
    ret_ty: ret_ty.kind,  // Use TypeKind for TopFunction's ret_ty
    body: body
  }
}

/// Helper function to convert a parser's StructDef to our internal StructDef
pub fn convert_struct_def(parser_struct : @parser.StructDef) -> StructDef {
  // Convert fields
  let fields = parser_struct.fields.map(fn(field) {
    StructField::{
      name: field.name,
      ty: Type::{
        kind: TypeKind::from_parser_type(field.ty.kind),
        mutable: field.is_mut  // Use is_mut from the field, not from the type
      }
    }
  })
  
  StructDef::{
    name: parser_struct.name,
    type_params: parser_struct.type_params,
    fields: fields
  }
}

///|
pub fn typecheck(program : @parser.Program) -> Program raise TypeCheckError {
  println("typecheck: starting");
  let ctx = Context::new()
  
  // First, collect all built-in function types
  // Input/Output functions
  ctx.func_types.set("read_int", Function([], Int))
  ctx.type_env.set("read_int", { kind: Function([], Int), mutable: false })
  ctx.func_types.set("print_int", Function([Int], Unit))
  ctx.type_env.set("print_int", { kind: Function([Int], Unit), mutable: false })
  ctx.func_types.set("read_char", Function([], Int))
  ctx.type_env.set("read_char", { kind: Function([], Int), mutable: false })
  ctx.func_types.set("print_char", Function([Int], Unit))
  ctx.type_env.set("print_char", { kind: Function([Int], Unit), mutable: false })
  ctx.func_types.set("print_endline", Function([], Unit))
  ctx.type_env.set("print_endline", { kind: Function([], Unit), mutable: false })
  
  // Math functions
  ctx.func_types.set("int_of_float", Function([Double], Int))
  ctx.type_env.set("int_of_float", { kind: Function([Double], Int), mutable: false })
  ctx.func_types.set("float_of_int", Function([Int], Double))
  ctx.type_env.set("float_of_int", { kind: Function([Int], Double), mutable: false })
  ctx.func_types.set("truncate", Function([Double], Int))
  ctx.type_env.set("truncate", { kind: Function([Double], Int), mutable: false })
  ctx.func_types.set("floor", Function([Double], Double))
  ctx.type_env.set("floor", { kind: Function([Double], Double), mutable: false })
  ctx.func_types.set("abs_float", Function([Double], Double))
  ctx.type_env.set("abs_float", { kind: Function([Double], Double), mutable: false })
  ctx.func_types.set("sqrt", Function([Double], Double))
  ctx.type_env.set("sqrt", { kind: Function([Double], Double), mutable: false })
  ctx.func_types.set("sin", Function([Double], Double))
  ctx.type_env.set("sin", { kind: Function([Double], Double), mutable: false })
  ctx.func_types.set("cos", Function([Double], Double))
  ctx.type_env.set("cos", { kind: Function([Double], Double), mutable: false })
  ctx.func_types.set("atan", Function([Double], Double))
  ctx.type_env.set("atan", { kind: Function([Double], Double), mutable: false })
  
  // Check the program and get the typed version
  let checked_program = ctx.check_program(program)
  // Substitute all type variables with their actual types
  ctx.substitute_type_var(checked_program)
}

///|
pub fn Context::substitute_type_var(
  self : Context,
  program : Program,
) -> Program {
  let new_structs : Map[String, StructDef] = Map::new()
  let struct_entries = program.struct_defs.to_array()
  let mut si = 0
  while si < struct_entries.length() {
    let (name, struct_def) = struct_entries[si]
    new_structs.set(name, self.substitute_struct_def(struct_def))
    si = si + 1
  }

  let new_top_lets : Map[String, TopLet] = Map::new()
  let top_let_entries = program.top_lets.to_array()
  let mut li = 0
  while li < top_let_entries.length() {
    let (name, top_let) = top_let_entries[li]
    new_top_lets.set(name, self.substitute_top_let(top_let))
    li = li + 1
  }

  let new_functions : Map[String, TopFunction] = Map::new()
  let func_entries = program.top_functions.to_array()
  let mut fi = 0
  while fi < func_entries.length() {
    let (name, func) = func_entries[fi]
    new_functions.set(name, self.substitute_top_function(func))
    fi = fi + 1
  }

  let new_enums : Map[String, EnumDef] = Map::new()
  let enum_entries = program.enum_defs.to_array()
  let mut ei = 0
  while ei < enum_entries.length() {
    let (name, enum_def) = enum_entries[ei]
    new_enums.set(name, self.substitute_enum_def(enum_def))
    ei = ei + 1
  }

  Program::{
    top_lets: new_top_lets,
    top_functions: new_functions,
    struct_defs: new_structs,
    enum_defs: new_enums
  }
}

fn Context::substitute_type(self : Context, ty : Type) -> Type {
  Type::{
    kind: self.substitute_type_kind(ty.kind),
    mutable: ty.mutable
  }
}

fn Context::substitute_struct_def(
  self : Context,
  struct_def : StructDef,
) -> StructDef {
  let mut new_fields : Array[StructField] = []
  let mut i = 0
  while i < struct_def.fields.length() {
    let field = struct_def.fields[i]
    new_fields = new_fields + [StructField::{ name: field.name, ty: self.substitute_type(field.ty) }]
    i = i + 1
  }
  StructDef::{ name: struct_def.name, type_params: struct_def.type_params, fields: new_fields }
}

fn Context::substitute_enum_def(
  self : Context,
  enum_def : EnumDef,
) -> EnumDef {
  let mut new_variants : Array[EnumVariant] = []
  let mut i = 0
  while i < enum_def.variants.length() {
    let variant = enum_def.variants[i]
    let mut new_params : Array[TypeKind] = []
    let mut j = 0
    while j < variant.params.length() {
      new_params = new_params + [self.substitute_type_kind(variant.params[j])]
      j = j + 1
    }
    new_variants = new_variants + [EnumVariant::{ name: variant.name, params: new_params }]
    i = i + 1
  }
  EnumDef::{ name: enum_def.name, type_params: enum_def.type_params, variants: new_variants }
}

fn Context::substitute_struct_construct(
  self : Context,
  sc_expr : StructConstructExpr,
) -> StructConstructExpr {
  let mut new_fields : Array[(String, Expr)] = []
  let mut i = 0
  while i < sc_expr.fields.length() {
    let (field_name, field_expr) = sc_expr.fields[i]
    new_fields = new_fields + [(field_name, self.substitute_expr(field_expr))]
    i = i + 1
  }
  StructConstructExpr::{ name: sc_expr.name, fields: new_fields }
}

fn Context::substitute_top_let(
  self : Context,
  top_let : TopLet,
) -> TopLet {
  TopLet::{
    name: top_let.name,
    ty: self.substitute_type(top_let.ty),
    expr: self.substitute_expr(top_let.expr)
  }
}

fn Context::substitute_param(
  self : Context,
  param : Param,
) -> Param {
  Param::{ name: param.name, ty: self.substitute_type_kind(param.ty) }
}

fn Context::substitute_top_function(
  self : Context,
  func : TopFunction,
) -> TopFunction {
  let mut new_params : Array[Param] = []
  let mut i = 0
  while i < func.param_list.length() {
    new_params = new_params + [self.substitute_param(func.param_list[i])]
    i = i + 1
  }

  TopFunction::{
    fname: func.fname,
    param_list: new_params,
    ret_ty: self.substitute_type_kind(func.ret_ty),
    body: self.substitute_block_expr(func.body)
  }
}

fn Context::substitute_local_function(
  self : Context,
  func : LocalFunction,
) -> LocalFunction {
  let mut new_params : Array[(String, Type)] = []
  let mut i = 0
  while i < func.param_list.length() {
    let (name, ty) = func.param_list[i]
    new_params = new_params + [(name, self.substitute_type(ty))]
    i = i + 1
  }

  LocalFunction::{
    fname: func.fname,
    param_list: new_params,
    ret_ty: self.substitute_type(func.ret_ty),
    body: self.substitute_block_expr(func.body)
  }
}

fn Context::substitute_block_expr(
  self : Context,
  block : BlockExpr,
) -> BlockExpr {
  let mut new_stmts : Array[Stmt] = []
  let mut i = 0
  while i < block.stmts.length() {
    new_stmts = new_stmts + [self.substitute_stmt(block.stmts[i])]
    i = i + 1
  }

  BlockExpr::{
    stmts: new_stmts,
    ty: self.substitute_type_kind(block.ty)
  }
}

fn Context::substitute_stmt(
  self : Context,
  stmt : Stmt,
) -> Stmt {
  let new_kind = match stmt.kind {
    StmtKind::LetStmt(let_stmt) => StmtKind::LetStmt(self.substitute_let_stmt(let_stmt))
    StmtKind::LetMutStmt(let_mut_stmt) => StmtKind::LetMutStmt(self.substitute_let_mut_stmt(let_mut_stmt))
    StmtKind::AssignStmt(assign_stmt) => StmtKind::AssignStmt(self.substitute_assign_stmt(assign_stmt))
    StmtKind::WhileStmt(while_stmt) => StmtKind::WhileStmt(self.substitute_while_stmt(while_stmt))
    StmtKind::ExprStmt(expr) => StmtKind::ExprStmt(self.substitute_expr(expr))
    StmtKind::ReturnStmt(expr_opt) => {
      StmtKind::ReturnStmt(match expr_opt {
        Some(expr) => Some(self.substitute_expr(expr))
        None => None
      })
    }
    StmtKind::LocalFunction(local_fn) => StmtKind::LocalFunction(self.substitute_local_function(local_fn))
  }

  Stmt::{ kind: new_kind }
}

fn Context::substitute_let_stmt(
  self : Context,
  let_stmt : LetStmt,
) -> LetStmt {
  LetStmt::{
    pattern: let_stmt.pattern,
    ty: self.substitute_type_kind(let_stmt.ty),
    expr: self.substitute_expr(let_stmt.expr)
  }
}

fn Context::substitute_let_mut_stmt(
  self : Context,
  let_mut_stmt : LetMutStmt,
) -> LetMutStmt {
  LetMutStmt::{
    name: let_mut_stmt.name,
    ty: self.substitute_type_kind(let_mut_stmt.ty),
    expr: self.substitute_expr(let_mut_stmt.expr)
  }
}

fn Context::substitute_assign_stmt(
  self : Context,
  assign_stmt : AssignStmt,
) -> AssignStmt {
  AssignStmt::{
    left_value: self.substitute_left_value(assign_stmt.left_value),
    op: assign_stmt.op,
    expr: self.substitute_expr(assign_stmt.expr)
  }
}

fn Context::substitute_left_value(
  self : Context,
  left_value : LeftValue,
) -> LeftValue {
  let new_kind = match left_value.kind {
    LeftValueKind::Ident(name) => LeftValueKind::Ident(name)
    LeftValueKind::ArrayAccess(base, index) => {
      LeftValueKind::ArrayAccess(self.substitute_left_value(base), self.substitute_expr(index))
    }
    LeftValueKind::FieldAccess(base, field_name) => {
      LeftValueKind::FieldAccess(self.substitute_left_value(base), field_name)
    }
  }

  LeftValue::{
    kind: new_kind,
    ty: self.substitute_type(left_value.ty)
  }
}

fn Context::substitute_while_stmt(
  self : Context,
  while_stmt : WhileStmt,
) -> WhileStmt {
  WhileStmt::{
    cond: self.substitute_expr(while_stmt.cond),
    body: self.substitute_block_expr(while_stmt.body)
  }
}

fn Context::substitute_expr(
  self : Context,
  expr : Expr,
) -> Expr {
  let new_kind = match expr.kind {
    ExprKind::ApplyExpr(apply_expr) => ExprKind::ApplyExpr(self.substitute_apply_expr(apply_expr))
    ExprKind::BlockExpr(block_expr) => ExprKind::BlockExpr(self.substitute_block_expr(block_expr))
    ExprKind::NotExpr(inner) => ExprKind::NotExpr(self.substitute_expr(inner))
    ExprKind::NegExpr(inner) => ExprKind::NegExpr(self.substitute_expr(inner))
    ExprKind::BinaryExpr(op, lhs, rhs) => {
      ExprKind::BinaryExpr(op, self.substitute_expr(lhs), self.substitute_expr(rhs))
    }
    ExprKind::IfExpr(if_expr) => ExprKind::IfExpr(self.substitute_if_expr(if_expr))
    ExprKind::MatchExpr(match_expr) => ExprKind::MatchExpr(self.substitute_match_expr(match_expr))
  }

  Expr::{ kind: new_kind, ty: self.substitute_type_kind(expr.ty) }
}

fn Context::substitute_apply_expr(
  self : Context,
  apply_expr : ApplyExpr,
) -> ApplyExpr {
  let new_kind = match apply_expr.kind {
    ApplyExprKind::AtomExpr(atom) => ApplyExprKind::AtomExpr(self.substitute_atom_expr(atom))
    ApplyExprKind::ArrayAccess(array_expr, index_expr) => {
      ApplyExprKind::ArrayAccess(self.substitute_apply_expr(array_expr), self.substitute_expr(index_expr))
    }
    ApplyExprKind::FieldAccess(object_expr, field) => {
      ApplyExprKind::FieldAccess(self.substitute_apply_expr(object_expr), field)
    }
    ApplyExprKind::Call(callee, args) => {
      let mut new_args : Array[Expr] = []
      let mut i = 0
      while i < args.length() {
        new_args = new_args + [self.substitute_expr(args[i])]
        i = i + 1
      }
      ApplyExprKind::Call(self.substitute_apply_expr(callee), new_args)
    }
    ApplyExprKind::EnumVariantAccess(enum_name, variant_name) => {
      ApplyExprKind::EnumVariantAccess(enum_name, variant_name)
    }
  }

  ApplyExpr::{ kind: new_kind, ty: self.substitute_type_kind(apply_expr.ty) }
}

fn Context::substitute_atom_expr(
  self : Context,
  atom : AtomExpr,
) -> AtomExpr {
  let new_kind = match atom.kind {
    AtomExprKind::Int(value) => AtomExprKind::Int(value)
    AtomExprKind::Double(value) => AtomExprKind::Double(value)
    AtomExprKind::Bool(value) => AtomExprKind::Bool(value)
    AtomExprKind::String(value) => AtomExprKind::String(value)
    AtomExprKind::Ident(name) => AtomExprKind::Ident(name)
    AtomExprKind::Unit => AtomExprKind::Unit
    AtomExprKind::Paren(expr) => AtomExprKind::Paren(self.substitute_expr(expr))
    AtomExprKind::Tuple(exprs) => {
      let mut new_exprs : Array[Expr] = []
      let mut i = 0
      while i < exprs.length() {
        new_exprs = new_exprs + [self.substitute_expr(exprs[i])]
        i = i + 1
      }
      AtomExprKind::Tuple(new_exprs)
    }
    AtomExprKind::Array(exprs) => {
      let mut new_exprs : Array[Expr] = []
      let mut i = 0
      while i < exprs.length() {
        new_exprs = new_exprs + [self.substitute_expr(exprs[i])]
        i = i + 1
      }
      AtomExprKind::Array(new_exprs)
    }
    AtomExprKind::ArrayMake(size_expr, init_expr) => {
      AtomExprKind::ArrayMake(self.substitute_expr(size_expr), self.substitute_expr(init_expr))
    }
    AtomExprKind::StructConstruct(sc_expr) => {
      AtomExprKind::StructConstruct(self.substitute_struct_construct(sc_expr))
    }
    AtomExprKind::EnumVariant(enum_name, variant_name) => {
      AtomExprKind::EnumVariant(enum_name, variant_name)
    }
  }

  AtomExpr::{ kind: new_kind, ty: self.substitute_type_kind(atom.ty) }
}

fn Context::substitute_if_expr(
  self : Context,
  if_expr : IfExpr,
) -> IfExpr {
  let mut new_else : Option[Either[IfExpr, BlockExpr]] = None
  match if_expr.else_block {
    None => new_else = None
    Some(@either.Either::Left(else_if)) => {
      new_else = Some(@either.Either::Left(self.substitute_if_expr(else_if)))
    }
    Some(@either.Either::Right(else_block)) => {
      new_else = Some(@either.Either::Right(self.substitute_block_expr(else_block)))
    }
  }

  IfExpr::{
    cond: self.substitute_expr(if_expr.cond),
    then_block: self.substitute_block_expr(if_expr.then_block),
    else_block: new_else,
    ty: self.substitute_type_kind(if_expr.ty)
  }
}

fn Context::substitute_match_expr(
  self : Context,
  match_expr : MatchExpr,
) -> MatchExpr {
  let mut new_arms : Array[MatchArm] = []
  let mut i = 0
  while i < match_expr.arms.length() {
    let arm = match_expr.arms[i]
    new_arms = new_arms + [MatchArm::{
      pattern: arm.pattern,  // 模式不需要替换类型变量
      body: self.substitute_expr(arm.body)
    }]
    i = i + 1
  }
  
  MatchExpr::{
    scrutinee: self.substitute_expr(match_expr.scrutinee),
    arms: new_arms,
    ty: self.substitute_type_kind(match_expr.ty)
  }
}
