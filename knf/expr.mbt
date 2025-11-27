///|
pub(all) enum KnfExpr {
  Unit
  Int(Int)
  Bool(Bool)
  Double(Double)
  String(String)
  Ident(Name)
  Not(Name)
  Neg(Name)
  Binary(BinaryOp, Name, Name)
  If(KnfExpr, KnfBlock, KnfBlock)
  Block(KnfBlock)
  Call(Name, Array[Name])
  ArrayAccess(Name, Name)
  FieldAccess(Name, String)
  TupleAccess(Name, Int)
  CreateStruct(String, Array[(String, Name)])
  ArrayLiteral(Type, Array[Name])
  ArrayMake(Name, Name)
  TupleLiteral(Array[Name])
}

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
} derive(Eq)

///|
pub impl Show for BinaryOp with output(self, logger) {
  let s = match self {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
    Mod => "%"
    ShiftLeft => "<<"
    ShiftRight => ">>"
    Eq => "=="
    NE => "!="
    LT => "<"
    GT => ">"
    LE => "<="
    GE => ">="
    And => "&&"
    Or => "||"
    BitAnd => "&"
    BitOr => "|"
  }
  logger.write_string(s)
}

///|
pub fn binop_to_knf(binop : @typecheck.BinaryOp) -> BinaryOp {
  match binop {
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
pub fn Context::expr_to_knf_name(
  self : Context,
  expr : KnfExpr,
  ty : Type,
  stmts : Array[KnfStmt],
) -> Name {
  match expr {
    Ident(name) => name
    _ => {
      let temp_name = self.add_temp(ty)
      stmts.push(Let(temp_name, ty, expr))
      temp_name
    }
  }
}

///|
pub fn Context::expr_to_knf_name_always_temp(
  self : Context,
  expr : KnfExpr,
  ty : Type,
  stmts : Array[KnfStmt],
) -> Name {
  // Always create a temporary variable, even for simple identifiers
  let temp_name = self.add_temp(ty)
  stmts.push(Let(temp_name, ty, expr))
  temp_name
}

///|
pub fn Context::expr_to_knf(
  self : Context,
  expr : @typecheck.Expr,
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  match expr.kind {
    @typecheck.ExprKind::ApplyExpr(apply_expr) => {
      // Directly delegate to apply_expr_to_knf
      self.apply_expr_to_knf(apply_expr)
    }
    @typecheck.ExprKind::BlockExpr(block_expr) => {
      let knf_block = self.block_expr_to_knf(block_expr)
      ([], Block(knf_block))
    }
    @typecheck.ExprKind::NotExpr(inner_expr) => {
      // Handle logical NOT: !expr
      let (inner_stmts, inner_knf) = self.expr_to_knf(inner_expr)
      
      // Always create a temporary variable for NotExpr
      let inner_type = self.typekind_to_knf(inner_expr.ty)
      let temp_name = self.expr_to_knf_name_always_temp(inner_knf, inner_type, inner_stmts)
      
      (inner_stmts, Not(temp_name))
    }
    @typecheck.ExprKind::NegExpr(inner_expr) => {
      // Handle arithmetic negation: -expr
      let (inner_stmts, inner_knf) = self.expr_to_knf(inner_expr)
      
      // Always create a temporary variable for NegExpr
      let inner_type = self.typekind_to_knf(inner_expr.ty)
      let temp_name = self.expr_to_knf_name_always_temp(inner_knf, inner_type, inner_stmts)
      
      (inner_stmts, Neg(temp_name))
    }
    @typecheck.ExprKind::BinaryExpr(op, left_expr, right_expr) => {
      let (left_stmts, left_knf) = self.expr_to_knf(left_expr)
      let (right_stmts, right_knf) = self.expr_to_knf(right_expr)
      
      // Build the final statements
      let final_stmts = left_stmts + right_stmts
      
      // For binary expressions, we want to preserve simple identifiers
      // but create temporaries for complex expressions
      let left_type = self.typekind_to_knf(left_expr.ty)
      let left_name = self.expr_to_knf_name(left_knf, left_type, final_stmts)
      
      let right_type = self.typekind_to_knf(right_expr.ty)
      let right_name = self.expr_to_knf_name(right_knf, right_type, final_stmts)
      
      let knf_op = binop_to_knf(op)
      (final_stmts, Binary(knf_op, left_name, right_name))
    }
    @typecheck.ExprKind::IfExpr(if_expr) => {
      self.if_expr_to_knf(if_expr)
    }
    @typecheck.ExprKind::MatchExpr(match_expr) => {
      self.match_expr_to_knf(match_expr)
    }
  }
}

///|
pub fn KnfExpr::to_string(self : KnfExpr, ident? : Int = 0) -> String {
  match self {
    Unit => "()"
    Int(i) => i.to_string()
    Bool(b) => b.to_string()
    Double(d) => d.to_string()
    String(s) => "\"\{s}\""
    Ident(name) => name.to_string()
    Not(name) => "!\{name}"
    Neg(name) => "-\{name}"
    Binary(op, lhs, rhs) => "\{lhs} \{op} \{rhs}"
    Call(func_name, args) => {
      let args_strs = args.map(arg => arg.to_string()).join(", ")
      "\{func_name}(\{args_strs})"
    }
    ArrayAccess(array_name, index_name) => "\{array_name}[\{index_name}]"
    FieldAccess(struct_name, field_name) => "\{struct_name}.\{field_name}"
    TupleAccess(tuple_name, index) => "\{tuple_name}.\{index}"
    CreateStruct(struct_name, init_arr) => {
      let init_strs = init_arr.map(field => "\{field.0}: \{field.1}").join(", ")
      "\{struct_name}::{\{init_strs}}"
    }
    ArrayLiteral(ty, elem_names) => {
      let elems_strs = elem_names.map(elem => elem.to_string()).join(", ")
      "[\{elems_strs}]::Array[\{ty}]"
    }
    ArrayMake(size_name, init_name) => "array_make(\{size_name}, \{init_name})"
    TupleLiteral(elem_names) => {
      let elems_strs = elem_names.map(elem => elem.to_string()).join(", ")
      "(\{elems_strs})"
    }
    Block(block) => block.to_string(ident)
    If(cond, then_block, else_block) => {
      let cond_str = cond.to_string()
      let then_str : String = then_block.to_string(ident)
      if else_block.stmts.is_empty() {
        "if \{cond_str} \{then_str}"
      } else {
        let else_str : String = else_block.to_string(ident)
        "if \{cond_str} \{then_str} else \{else_str}"
      }
    }
  }
}

///|
pub impl Show for KnfExpr with output(self, logger) {
  logger.write_string(self.to_string(ident=0))
}

///| 将 match 表达式转换为 KNF 形式
///
/// Match 表达式被编译为 if-else 链：
/// match expr {
///   Pattern1 => body1;
///   Pattern2 => body2;
/// }
///
/// 编译为：
/// let temp = expr;
/// if (matches_pattern1(temp)) {
///   let bindings1 = extract_pattern1(temp);
///   body1
/// } else if (matches_pattern2(temp)) {
///   let bindings2 = extract_pattern2(temp);
///   body2
/// } else {
///   error
/// }
pub fn Context::match_expr_to_knf(
  self : Context,
  match_expr : @typecheck.MatchExpr
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  // 1. 计算被匹配的表达式
  let (scrutinee_stmts, scrutinee_knf) = self.expr_to_knf(match_expr.scrutinee)
  let scrutinee_ty = self.typekind_to_knf(match_expr.scrutinee.ty)
  
  // 2. 将 scrutinee 存储到临时变量中
  let scrutinee_name = self.expr_to_knf_name_always_temp(scrutinee_knf, scrutinee_ty, scrutinee_stmts)
  
  // 3. 编译每个分支为 if-else 链
  if match_expr.arms.length() == 0 {
    // 没有分支，返回 unit
    (scrutinee_stmts, Unit)
  } else {
    // 从最后一个分支开始，向前构建 if-else 链
    let last_arm = match_expr.arms[match_expr.arms.length() - 1]
    let (last_stmts, last_expr) = self.compile_match_arm(scrutinee_name, last_arm)
    
    // 将最后一个表达式添加为语句
    let last_block_stmts = last_stmts + [KnfStmt::ExprStmt(last_expr)]
    let result_ty = self.typekind_to_knf(match_expr.ty)
    let mut current_block = KnfBlock::{
      stmts: last_block_stmts,
      ty: result_ty
    }
    
    // 从倒数第二个分支开始，向前构建
    let mut i = match_expr.arms.length() - 2
    while i >= 0 {
      let arm = match_expr.arms[i]
      
      // 生成顶层模式匹配条件（只检查顶层构造器）
      let top_level_cond = self.compile_pattern_check_top_level(scrutinee_name, arm.pattern)
      
      // 生成模式绑定和分支体
      let (arm_stmts, arm_expr) = self.compile_match_arm(scrutinee_name, arm)
      
      // 检查是否有嵌套构造器模式，如果有，需要在分支体内部添加嵌套检查
      let (has_nested, nested_guard) = self.has_nested_constructor_pattern(scrutinee_name, arm.pattern)
      
      let arm_block = if has_nested {
        // 有嵌套模式，需要在分支体内部添加 guard
        let (guard_cond, guard_stmts) = nested_guard
        
        // 将 guard 检查和分支体包装在一起
        let guarded_body_block = KnfBlock::{
          stmts: arm_stmts + [KnfStmt::ExprStmt(arm_expr)],
          ty: result_ty
        }
        
        // 如果 guard 失败，跳转到 else 分支
        let guard_if = If(guard_cond, guarded_body_block, current_block)
        
        KnfBlock::{
          stmts: guard_stmts + [KnfStmt::ExprStmt(guard_if)],
          ty: result_ty
        }
      } else {
        // 没有嵌套模式，直接使用分支体
        KnfBlock::{
          stmts: arm_stmts + [KnfStmt::ExprStmt(arm_expr)],
          ty: result_ty
        }
      }
      
      // 构建 if-else
      let if_expr = If(top_level_cond, arm_block, current_block)
      current_block = KnfBlock::{
        stmts: [KnfStmt::ExprStmt(if_expr)],
        ty: result_ty
      }
      
      i = i - 1
    }
    
    // 返回整个 if-else 链
    (scrutinee_stmts, Block(current_block))
  }
}

///| 编译单个 match 分支
fn Context::compile_match_arm(
  self : Context,
  scrutinee_name : Name,
  arm : @typecheck.MatchArm
) -> (Array[KnfStmt], KnfExpr) raise KnfTransformError {
  // 1. 生成模式绑定语句
  let binding_stmts = self.compile_pattern_bindings(scrutinee_name, arm.pattern)
  
  // 2. 转换分支体
  let (body_stmts, body_expr) = self.expr_to_knf(arm.body)
  
  // 3. 合并语句
  (binding_stmts + body_stmts, body_expr)
}

///| 生成顶层模式匹配的条件检查（只检查顶层构造器）
fn Context::compile_pattern_check_top_level(
  self : Context,
  scrutinee_name : Name,
  pattern : @typecheck.Pattern
) -> KnfExpr {
  let _ = self  // Suppress unused variable warning
  match pattern.kind {
    @typecheck.PatternKind::Wildcard => Bool(true)
    @typecheck.PatternKind::Ident(name) => {
      // 特殊处理：true 和 false 应该被当作字面量比较
      if name == "true" {
        Ident(scrutinee_name)
      } else if name == "false" {
        Not(scrutinee_name)
      } else {
        // 普通标识符模式，总是匹配
        Bool(true)
      }
    }
    @typecheck.PatternKind::Constructor(constructor_name, _) => {
      let builtin_name = Name::{ id: "__builtin_enum_tag_eq", slot: 0 }
      let constructor_name_as_name = Name::{ id: constructor_name, slot: 0 }
      Call(builtin_name, [scrutinee_name, constructor_name_as_name])
    }
    @typecheck.PatternKind::Tuple(_) => Bool(true)
  }
}

///| 检查模式是否有嵌套构造器，如果有，返回嵌套检查的 guard
///
/// 返回：(是否有嵌套构造器, (guard 条件, guard 语句))
fn Context::has_nested_constructor_pattern(
  self : Context,
  scrutinee_name : Name,
  pattern : @typecheck.Pattern
) -> (Bool, (KnfExpr, Array[KnfStmt])) raise KnfTransformError {
  match pattern.kind {
    @typecheck.PatternKind::Constructor(constructor_name, sub_patterns) => {
      // 检查子模式中是否有构造器
      let mut has_nested = false
      for sub_pattern in sub_patterns {
        match sub_pattern.kind {
          @typecheck.PatternKind::Constructor(_, _) => {
            has_nested = true
            break
          }
          _ => ()
        }
      }
      
      if !has_nested {
        (false, (Bool(true), []))
      } else {
        // 生成嵌套检查
        let (guard_cond, guard_stmts) = self.compile_nested_pattern_guards(scrutinee_name, constructor_name, sub_patterns)
        (true, (guard_cond, guard_stmts))
      }
    }
    _ => (false, (Bool(true), []))
  }
}

///| 为嵌套构造器模式生成 guard 检查
fn Context::compile_nested_pattern_guards(
  self : Context,
  scrutinee_name : Name,
  constructor_name : String,
  sub_patterns : Array[@typecheck.Pattern]
) -> (KnfExpr, Array[KnfStmt]) raise KnfTransformError {
  let mut all_checks : Array[KnfExpr] = []
  let mut all_stmts : Array[KnfStmt] = []
  
  // 获取字段类型
  let mut field_types : Array[Type] = []
  let mut found = false
  for _enum_name, enum_def in self.enum_defs {
    if found { break }
    for variant in enum_def.variants {
      if variant.name == constructor_name {
        field_types = variant.params.map(fn(param_ty) { self.typekind_to_knf(param_ty) })
        found = true
        break
      }
    }
  }
  
  // 为每个嵌套构造器生成检查
  let mut i = 0
  while i < sub_patterns.length() {
    match sub_patterns[i].kind {
      @typecheck.PatternKind::Constructor(nested_constructor, _) => {
        // 生成字段访问
        let field_name = Name::{ id: "nested_guard_field_\{i}_\{self.temp_counter}", slot: self.temp_counter }
        self.temp_counter = self.temp_counter + 1
        
        let field_access = FieldAccess(scrutinee_name, "field\{i + 1}")
        let field_ty = if i < field_types.length() { field_types[i] } else { Type::Unit }
        all_stmts = all_stmts + [KnfStmt::Let(field_name, field_ty, field_access)]
        
        // 生成标签检查
        let builtin_name = Name::{ id: "__builtin_enum_tag_eq", slot: 0 }
        let constructor_name_as_name = Name::{ id: nested_constructor, slot: 0 }
        let tag_check = Call(builtin_name, [field_name, constructor_name_as_name])
        all_checks = all_checks + [tag_check]
      }
      _ => ()
    }
    i = i + 1
  }
  
  // 用 AND 连接所有检查
  if all_checks.length() == 0 {
    (Bool(true), all_stmts)
  } else if all_checks.length() == 1 {
    (all_checks[0], all_stmts)
  } else {
    // 将检查结果存储到临时变量并 AND 连接
    let mut current_result_name = Name::{ id: "guard_check_0", slot: self.temp_counter }
    self.temp_counter = self.temp_counter + 1
    all_stmts = all_stmts + [KnfStmt::Let(current_result_name, Type::Bool, all_checks[0])]
    
    let mut j = 1
    while j < all_checks.length() {
      let next_check_name = Name::{ id: "guard_check_\{j}", slot: self.temp_counter }
      self.temp_counter = self.temp_counter + 1
      all_stmts = all_stmts + [KnfStmt::Let(next_check_name, Type::Bool, all_checks[j])]
      
      let and_result_name = Name::{ id: "guard_and_\{j}", slot: self.temp_counter }
      self.temp_counter = self.temp_counter + 1
      all_stmts = all_stmts + [KnfStmt::Let(and_result_name, Type::Bool, Binary(BinaryOp::And, current_result_name, next_check_name))]
      
      current_result_name = and_result_name
      j = j + 1
    }
    
    (Ident(current_result_name), all_stmts)
  }
}



///| 生成模式绑定语句
fn Context::compile_pattern_bindings(
  self : Context,
  scrutinee_name : Name,
  pattern : @typecheck.Pattern
) -> Array[KnfStmt] raise KnfTransformError {
  match pattern.kind {
    @typecheck.PatternKind::Wildcard => {
      // 通配符不绑定任何变量
      []
    }
    @typecheck.PatternKind::Ident(var_name) => {
      // 变量模式：绑定整个值
      // 为变量在当前 KNF 上下文中注册名字和类型
      // 先尝试从 scrutinee_name 推断类型，否则退回到 Unit
      let bound_ty = match self.name_env.get_name_type(scrutinee_name) {
        Some(t) => t
        None => Type::Unit
      }

      // 在环境中为 var_name 分配一个新的 Name，并使用该 Name 生成绑定语句
      // Use LetMut instead of Let to allow reassignment (needed for some test cases)
      let var_name_obj = self.add_new_name(var_name, bound_ty)
      [KnfStmt::LetMut(var_name_obj, bound_ty, Ident(scrutinee_name))]
    }
    @typecheck.PatternKind::Constructor(constructor_name, sub_patterns) => {
      // 构造器模式：提取字段并绑定子模式
      // 需要从枚举定义中获取字段类型
      let mut stmts : Array[KnfStmt] = []
      
      // 查找构造器所属的枚举和变体
      let mut field_types : Array[Type] = []
      let mut found = false
      for _enum_name, enum_def in self.enum_defs {
        if found { break }
        for variant in enum_def.variants {
          if variant.name == constructor_name {
            // 找到了对应的变体，获取字段类型
            field_types = variant.params.map(fn(param_ty) { self.typekind_to_knf(param_ty) })
            found = true
            break
          }
        }
      }
      
      let mut i = 0
      while i < sub_patterns.length() {
        // 为每个子模式创建一个临时变量
        let temp_name = Name::{ id: "temp_\{i}", slot: i }
        let field_access = FieldAccess(scrutinee_name, "field\{i + 1}")
        // 使用正确的字段类型
        let field_ty = if i < field_types.length() { field_types[i] } else { Type::Unit }
        stmts = stmts + [KnfStmt::Let(temp_name, field_ty, field_access)]
        
        // 递归处理子模式，传递类型信息
        let sub_bindings = self.compile_pattern_bindings_with_type(temp_name, field_ty, sub_patterns[i])
        stmts = stmts + sub_bindings
        
        i = i + 1
      }
      stmts
    }
    @typecheck.PatternKind::Tuple(sub_patterns) => {
      // 元组模式：提取每个元素并绑定
      let mut stmts : Array[KnfStmt] = []
      let mut i = 0
      while i < sub_patterns.length() {
        let tuple_access = TupleAccess(scrutinee_name, i)
        let temp_name = Name::{ id: "tuple_\{i}", slot: i + 1000 }  // 使用大的偏移避免冲突
        stmts = stmts + [KnfStmt::Let(temp_name, Type::Unit, tuple_access)]
        
        // 递归处理子模式
        let sub_bindings = self.compile_pattern_bindings(temp_name, sub_patterns[i])
        stmts = stmts + sub_bindings
        
        i = i + 1
      }
      stmts
    }
  }
}

///| 生成模式绑定语句（带类型信息）
///
/// 这个版本接受显式的类型参数，用于处理临时变量的情况
fn Context::compile_pattern_bindings_with_type(
  self : Context,
  scrutinee_name : Name,
  scrutinee_type : Type,
  pattern : @typecheck.Pattern
) -> Array[KnfStmt] raise KnfTransformError {
  match pattern.kind {
    @typecheck.PatternKind::Wildcard => {
      // 通配符不绑定任何变量
      []
    }
    @typecheck.PatternKind::Ident(var_name) => {
      // 变量模式：绑定整个值，使用提供的类型
      // Use LetMut instead of Let to allow reassignment (needed for some test cases)
      let var_name_obj = self.add_new_name(var_name, scrutinee_type)
      [KnfStmt::LetMut(var_name_obj, scrutinee_type, Ident(scrutinee_name))]
    }
    @typecheck.PatternKind::Constructor(constructor_name, sub_patterns) => {
      // 嵌套构造器模式：需要先检查标签，然后提取字段
      let mut stmts : Array[KnfStmt] = []
      
      // 查找构造器所属的枚举和变体
      let mut field_types : Array[Type] = []
      let mut found = false
      for _enum_name, enum_def in self.enum_defs {
        if found { break }
        for variant in enum_def.variants {
          if variant.name == constructor_name {
            // 找到了对应的变体，获取字段类型
            field_types = variant.params.map(fn(param_ty) { self.typekind_to_knf(param_ty) })
            found = true
            break
          }
        }
      }
      
      // 为每个子模式创建字段访问并递归处理
      let mut i = 0
      while i < sub_patterns.length() {
        // 为每个子模式创建一个临时变量
        let temp_name = Name::{ id: "nested_field_\{i}", slot: i + 2000 }
        let field_access = FieldAccess(scrutinee_name, "field\{i + 1}")
        // 使用正确的字段类型
        let field_ty = if i < field_types.length() { field_types[i] } else { Type::Unit }
        stmts = stmts + [KnfStmt::Let(temp_name, field_ty, field_access)]
        
        // 递归处理子模式，传递类型信息
        let sub_bindings = self.compile_pattern_bindings_with_type(temp_name, field_ty, sub_patterns[i])
        stmts = stmts + sub_bindings
        
        i = i + 1
      }
      stmts
    }
    @typecheck.PatternKind::Tuple(sub_patterns) => {
      // 元组模式：提取每个元素并绑定
      let mut stmts : Array[KnfStmt] = []
      let mut i = 0
      while i < sub_patterns.length() {
        let tuple_access = TupleAccess(scrutinee_name, i)
        let temp_name = Name::{ id: "tuple_\{i}", slot: i + 1000 }
        stmts = stmts + [KnfStmt::Let(temp_name, Type::Unit, tuple_access)]
        
        // 递归处理子模式
        let sub_bindings = self.compile_pattern_bindings(temp_name, sub_patterns[i])
        stmts = stmts + sub_bindings
        
        i = i + 1
      }
      stmts
    }
  }
}
