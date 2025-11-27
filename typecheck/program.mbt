///|
typealias @either.Either

///|
pub(all) suberror TypeCheckError String derive(Show)

///|
pub(all) struct Env {
  local_ : Map[String, Type]
  parent : Env?
}

///|
pub fn Env::new(parent? : Env? = None) -> Env {
  Env::{ local_: Map::new(), parent }
}

///|
pub fn Env::get(self : Env, name : String) -> Type? {
  match self.local_.get(name) {
    Some(t) => Some(t)
    None =>
      match self.parent {
        Some(p) => p.get(name)
        None => None
      }
  }
}

///|
pub fn Env::set(self : Env, name : String, t : Type) -> Unit {
  self.local_.set(name, t)
}

///|
pub(all) struct Context {
  mut type_env : Env
  type_vars : Map[Int, TypeKind]
  struct_defs : Map[String, StructDef]
  enum_defs : Map[String, EnumDef]  // 枚举定义
  func_types : Map[String, TypeKind]
  mut current_func_ret_ty : TypeKind?
  mut checking_structs : Set[String]  // For detecting circular dependencies
  generic_functions : Map[String, @parser.TopFunction]  // 泛型函数定义
  mut monomorphized_instances : Map[String, Array[(Array[TypeKind], String)]]  // 函数名 -> [(具体类型数组, 单态化后的函数名)]
  mut current_generic_type : String?  // 当前正在检查的泛型类型参数
  mut generic_type_bindings : Map[String, TypeKind]  // 泛型类型参数绑定映射
  mut generic_recursion_counter : Map[String, Int]  // 泛型递归计数器
  mut checking_generic_function_body : Bool  // 是否正在检查泛型函数体
}

///|
pub fn Context::new() -> Context {
  println("Context::new: creating new context");
  Context::{
    type_env: Env::new(),
    type_vars: Map::new(),
    struct_defs: Map::new(),
    enum_defs: Map::new(),
    func_types: Map::new(),
    current_func_ret_ty: None,
    checking_structs: Set::new(),
    generic_functions: Map::new(),
    monomorphized_instances: Map::new(),
    current_generic_type: None,
    generic_type_bindings: Map::new(),
    generic_recursion_counter: Map::new(),
    checking_generic_function_body: false,
  }
}

///|
pub fn Context::lookup_type(self : Context, name : String) -> Type? {
  match self.type_env.get(name) {
    Some(ty) => {
      let resolved_kind = self.resolve_type_kind(ty.kind)
      let updated = Type::{ kind: resolved_kind, mutable: ty.mutable }
      self.type_env.set(name, updated)
      Some(updated)
    }
    None => None
  }
}

///|
pub fn Context::allocate_fresh_type_var(self : Context) -> TypeKind {
  let mut id = 0
  while self.type_vars.get(id) is Some(_) {
    id = id + 1
  }
  let ty_var = TypeKind::TypeVar(id)
  self.type_vars.set(id, ty_var)
  ty_var
}

///|
pub fn Context::enter_scope(self : Self) -> Unit {
  let sub_env = Env::new(parent=Some(self.type_env))
  self.type_env = sub_env
}

///|
pub fn Context::exit_scope(self : Context) -> Unit {
  self.type_env = match self.type_env.parent {
    Some(p) => p
    None => self.type_env
  }
}

///|
pub fn Context::set_current_func_ret_ty(self : Context, ty : TypeKind) -> Unit {
  self.current_func_ret_ty = Some(ty)
}

///| Clear generic type bindings - should be called before checking a new function call
pub fn Context::clear_generic_type_bindings(self : Context) -> Unit {
  self.generic_type_bindings = Map::new()
}

///| Get generic type binding for a type parameter
pub fn Context::get_generic_type_binding(self : Context, param_name : String) -> TypeKind? {
  self.generic_type_bindings.get(param_name)
}

///| Set generic type binding for a type parameter
///  This helper performs an occurs check to avoid recording bindings that
///  would create infinite types, such as T -> List[T]. Such bindings are
///  a common source of non-terminating type resolution.
pub fn Context::set_generic_type_binding(self : Context, param_name : String, actual_type : TypeKind) -> Unit {
  // If the actual type structurally contains the generic parameter itself,
  // refuse the binding to prevent infinite types.
  if contains_generic_param(actual_type, param_name) {
    println("DEBUG: set_generic_type_binding: rejecting infinite binding " + param_name + " -> " + actual_type.to_string())
    return
  }
  self.generic_type_bindings.set(param_name, actual_type)
}

///|
pub(all) struct Program {
  top_lets : Map[String, TopLet]
  top_functions : Map[String, TopFunction]
  struct_defs : Map[String, StructDef]
  enum_defs : Map[String, EnumDef]  // 枚举定义
} derive(Show)

pub fn Context::check_program(
  self : Context,
  program : @parser.Program
) -> Program raise TypeCheckError {
  println("check_program: starting");
  // Create a new context with an empty checking_structs set
  let ctx = Context::{
    type_env: self.type_env,
    type_vars: self.type_vars,
    struct_defs: self.struct_defs,
    enum_defs: self.enum_defs,
    func_types: self.func_types,
    current_func_ret_ty: self.current_func_ret_ty,
    checking_structs: Set::new(),
    generic_functions: Map::new(),
    monomorphized_instances: Map::new(),
    current_generic_type: None,
    generic_type_bindings: Map::new(),
    generic_recursion_counter: Map::new(),
    checking_generic_function_body: false,
  }
  
  // First pass: collect all struct names, enum names and function signatures
  ctx.collect_struct_names(program)
  ctx.collect_enum_names(program)
  ctx.collect_function_types(program)

  // Second pass: check struct definitions
  let struct_entries = program.struct_defs.to_array()
  let checked_structs : Map[String, StructDef] = Map::new()
  let mut si = 0
  while si < struct_entries.length() {
    let (struct_name, struct_def) = struct_entries[si]
    let checked_struct = ctx.check_struct_def(struct_def)
    ctx.struct_defs.set(struct_name, checked_struct)
    checked_structs.set(struct_name, checked_struct)
    si = si + 1
  }

  // Check enum definitions
  let enum_entries = program.enum_defs.to_array()
  let checked_enums : Map[String, EnumDef] = Map::new()
  let mut ei = 0
  while ei < enum_entries.length() {
    let (enum_name, enum_def) = enum_entries[ei]
    let checked_enum = ctx.check_enum_def(enum_def)
    ctx.enum_defs.set(enum_name, checked_enum)
    checked_enums.set(enum_name, checked_enum)
    
    // Register enum constructors as functions in the type environment
    let mut vi = 0
    while vi < checked_enum.variants.length() {
      let variant = checked_enum.variants[vi]
      let constructor_type = if checked_enum.type_params.length() > 0 {
        // For generic enums, create a generic constructor type
        let mut type_args: Array[TypeKind] = []
        let mut i = 0
        while i < checked_enum.type_params.length() {
          // For each type parameter, we use a TypeVar
          type_args = type_args + [TypeKind::TypeVar(i)]
          i = i + 1
        }
        let enum_type = TypeKind::GenericEnum(enum_name, type_args)
        
        if variant.params.length() == 0 {
          // Simple constructor (no parameters): Nil : Node[T]
          // For generic enums, even simple constructors should be functions that return the enum type
          let func_type = TypeKind::Function([], enum_type)
          println("DEBUG: Registered generic enum constructor " + variant.name + " with type " + func_type.to_string())
          func_type
        } else {
          // Constructor with parameters: Cons : (T, Node[T]) -> Node[T]
          let func_type = TypeKind::Function(variant.params, enum_type)
          println("DEBUG: Registered generic enum constructor " + variant.name + " with type " + func_type.to_string())
          func_type
        }
      } else {
        // For non-generic enums
        if variant.params.length() == 0 {
          // Simple constructor (no parameters): Red : Color
          let enum_type = TypeKind::Enum(enum_name)
          println("DEBUG: Registered enum constructor " + variant.name + " with type " + enum_type.to_string())
          enum_type
        } else {
          // Constructor with parameters: RGB : (Int, Int, Int) -> Color
          let func_type = TypeKind::Function(variant.params, TypeKind::Enum(enum_name))
          println("DEBUG: Registered enum constructor " + variant.name + " with type " + func_type.to_string())
          func_type
        }
      }
      ctx.type_env.set(variant.name, Type::{ kind: constructor_type, mutable: false })
      ctx.func_types.set(variant.name, constructor_type)
      vi = vi + 1
    }
    ei = ei + 1
  }

  let top_let_entries = program.top_lets.to_array()
  let checked_top_lets : Map[String, TopLet] = Map::new()
  let mut li = 0
  while li < top_let_entries.length() {
    let (let_name, top_let) = top_let_entries[li]
    let checked_let = ctx.check_top_let(top_let)
    checked_top_lets.set(let_name, checked_let)
    li = li + 1
  }

  let func_entries = program.top_functions.to_array()
  let checked_functions : Map[String, TopFunction] = Map::new()
  let mut fi = 0
  while fi < func_entries.length() {
    let (func_name, func) = func_entries[fi]
    let checked_func = ctx.check_top_function(func)
    checked_functions.set(func_name, checked_func)
    fi = fi + 1
  }

  // Instantiate any recorded generic function instantiations
  ctx.instantiate_generic_functions(checked_functions)

  // Remove original generic function definitions from the checked list.
  // We only want monomorphized instances to flow to later stages (KNF/codegen).
  let generic_entries2 = ctx.generic_functions.to_array()
  let mut gi2 = 0
  while gi2 < generic_entries2.length() {
    let (gname, _) = generic_entries2[gi2]
    // Remove from checked_functions if present
    match checked_functions.get(gname) {
      Some(_) => { checked_functions.remove(gname) }
      None => ()
    }
    // Also remove the polymorphic signature from func_types and type_env
    ctx.func_types.remove(gname)
    // Remove top-level local binding for the generic function name so later
    // stages don't see an entry with TypeVar placeholders.
    ctx.type_env.local_.remove(gname)
    gi2 = gi2 + 1
  }

  // Debug: list final top-level functions and their signatures
  let debug_entries = checked_functions.to_array()
  let mut di = 0
  while di < debug_entries.length() {
    let (n, f) = debug_entries[di]
    println("FINAL FUNC: " + n + " -> " + f.ret_ty.to_string())
    // Also print parameter types for debugging
    let mut param_tys_str = ""
    let mut ppi = 0
    while ppi < f.param_list.length() {
      param_tys_str = param_tys_str + f.param_list[ppi].ty.to_string()
      if ppi < f.param_list.length() - 1 {
        param_tys_str = param_tys_str + ", "
      }
      ppi = ppi + 1
    }
    println("  params: (" + param_tys_str + ")")
    // Quick scan for any TypeVar mention in body, params or statements
    let body_str = f.body.ty.to_string() + " " + param_tys_str
    let body_full = f.body.to_string()
    if body_str.contains("TypeVar(") || body_full.contains("TypeVar(") {
      println("  WARNING: TypeVar found in function '" + n + "' types: " + body_str)
      // Print the full body for deeper debugging
      println("  BODY DUMP: " + body_full)
    }
    di = di + 1
  }

  // Normalize types in function bodies and top-lets to remove residual TypeVars
  // Use the local ctx (which has been mutated during checking/instantiation)
  // Dump current type_vars for debugging before normalization
  println("DEBUG: ctx.type_vars mapping before normalization:")
  let tv_entries = ctx.type_vars.to_array()
  let mut tvi = 0
  while tvi < tv_entries.length() {
    let (k, v) = tv_entries[tvi]
    println("  id=" + k.to_string() + " => " + v.to_string())
    tvi = tvi + 1
  }
  println("DEBUG: ctx.generic_type_bindings before normalization:")
  let gb = ctx.generic_type_bindings.to_array()
  let mut gbi = 0
  while gbi < gb.length() {
    let (k, v) = gb[gbi]
    println("  " + k + " => " + v.to_string())
    gbi = gbi + 1
  }

  let (norm_funcs, norm_lets) = ctx.normalize_program_types(checked_functions, checked_top_lets)

  Program::{
    top_lets: norm_lets,
    top_functions: norm_funcs,
    struct_defs: checked_structs,
    enum_defs: checked_enums
  }
}

// Normalize types in expressions/statements to resolve any remaining TypeVars
fn Context::normalize_atom_expr(self: Context, a: AtomExpr) -> AtomExpr {
  match a.kind {
    AtomExprKind::Paren(e) => {
      let ne = self.normalize_expr(e)
      AtomExpr::{ kind: AtomExprKind::Paren(ne), ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
    AtomExprKind::Tuple(es) => {
      let mut out: Array[Expr] = []
      let mut i = 0
      while i < es.length() {
        out = out + [self.normalize_expr(es[i])]
        i = i + 1
      }
      AtomExpr::{ kind: AtomExprKind::Tuple(out), ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
    AtomExprKind::Array(es) => {
      let mut out: Array[Expr] = []
      let mut i = 0
      while i < es.length() {
        out = out + [self.normalize_expr(es[i])]
        i = i + 1
      }
      AtomExpr::{ kind: AtomExprKind::Array(out), ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
    AtomExprKind::ArrayMake(sz, init) => {
      AtomExpr::{ kind: AtomExprKind::ArrayMake(sz, self.normalize_expr(init)), ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
    AtomExprKind::StructConstruct(sc) => {
      // StructConstruct contains Exprs inside; to avoid deep changes, just normalize whole AtomExpr ty
      AtomExpr::{ kind: a.kind, ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
    AtomExprKind::Paren(_) | AtomExprKind::Int(_) | AtomExprKind::Double(_) | AtomExprKind::Bool(_) | AtomExprKind::String(_) | AtomExprKind::Ident(_) | AtomExprKind::Unit | AtomExprKind::EnumVariant(_, _) => {
      AtomExpr::{ kind: a.kind, ty: self.substitute_type_kind(self.resolve_type_kind(a.ty)) }
    }
  }
}

fn Context::normalize_apply_expr(self: Context, ae: ApplyExpr) -> ApplyExpr {
  match ae.kind {
    ApplyExprKind::AtomExpr(atom) => {
      let na = self.normalize_atom_expr(atom)
      ApplyExpr::{ kind: ApplyExprKind::AtomExpr(na), ty: self.substitute_type_kind(self.resolve_type_kind(ae.ty)) }
    }
    ApplyExprKind::ArrayAccess(arr, idx) => {
      let narr = self.normalize_apply_expr(arr)
      let nidx = self.normalize_expr(idx)
      ApplyExpr::{ kind: ApplyExprKind::ArrayAccess(narr, nidx), ty: self.substitute_type_kind(self.resolve_type_kind(ae.ty)) }
    }
    ApplyExprKind::FieldAccess(obj, field) => {
      let nobj = self.normalize_apply_expr(obj)
      ApplyExpr::{ kind: ApplyExprKind::FieldAccess(nobj, field), ty: self.substitute_type_kind(self.resolve_type_kind(ae.ty)) }
    }
    ApplyExprKind::Call(callee, args) => {
      let ncallee = self.normalize_apply_expr(callee)
      let mut nargs: Array[Expr] = []
      let mut i = 0
      while i < args.length() {
        nargs = nargs + [self.normalize_expr(args[i])]
        i = i + 1
      }
      // If the callee has a concrete function type, use its parameter types
      // to fill in any remaining TypeVars in the argument types (common when
      // passing local functions whose params were inferred earlier).
      let final_args = match self.resolve_type_kind(ncallee.ty) {
        TypeKind::Function(param_tys, _) => {
          let mut final_nargs: Array[Expr] = []
          let mut j = 0
          while j < nargs.length() {
            let aexpr = nargs[j]
            // If the argument type still contains a TypeVar, replace it
            // with the corresponding callee parameter type.
            let arg_ty = self.resolve_type_kind(aexpr.ty)
            let new_ty = if arg_ty.to_string().contains("TypeVar(") {
              if j < param_tys.length() {
                self.substitute_type_kind(param_tys[j])
              } else {
                self.substitute_type_kind(arg_ty)
              }
            } else {
              self.substitute_type_kind(arg_ty)
            }
            final_nargs = final_nargs + [Expr::{ kind: aexpr.kind, ty: new_ty }]
            j = j + 1
          }
          final_nargs
        }
        _ => nargs
      }
      ApplyExpr::{ kind: ApplyExprKind::Call(ncallee, final_args), ty: self.substitute_type_kind(self.resolve_type_kind(ae.ty)) }
    }
    ApplyExprKind::EnumVariantAccess(a, v) => {
      ApplyExpr::{ kind: ApplyExprKind::EnumVariantAccess(a, v), ty: self.substitute_type_kind(self.resolve_type_kind(ae.ty)) }
    }
  }
}

fn Context::normalize_expr(self: Context, e: Expr) -> Expr {
  match e.kind {
    ExprKind::ApplyExpr(ae) => {
      let nae = self.normalize_apply_expr(ae)
      Expr::{ kind: ExprKind::ApplyExpr(nae), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::BlockExpr(be) => {
      let nbe = self.normalize_block_expr(be)
      Expr::{ kind: ExprKind::BlockExpr(nbe), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::NotExpr(inner) => {
      let ni = self.normalize_expr(inner)
      Expr::{ kind: ExprKind::NotExpr(ni), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::NegExpr(inner) => {
      let ni = self.normalize_expr(inner)
      Expr::{ kind: ExprKind::NegExpr(ni), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::BinaryExpr(op, l, r) => {
      let nl = self.normalize_expr(l)
      let nr = self.normalize_expr(r)
      Expr::{ kind: ExprKind::BinaryExpr(op, nl, nr), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::IfExpr(ie) => {
      // For now, just normalize contained expressions by converting to_string? Better to reconstruct
      Expr::{ kind: ExprKind::IfExpr(ie), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
    ExprKind::MatchExpr(me) => {
      Expr::{ kind: ExprKind::MatchExpr(me), ty: self.substitute_type_kind(self.resolve_type_kind(e.ty)) }
    }
  }
}

fn Context::normalize_stmt(self: Context, s: Stmt) -> Stmt {
  match s.kind {
    StmtKind::LetStmt(ls) => {
      let ne = self.normalize_expr(ls.expr)
      Stmt::{ kind: StmtKind::LetStmt(LetStmt::{ pattern: ls.pattern, ty: self.substitute_type_kind(self.resolve_type_kind(ls.ty)), expr: ne }) }
    }
    StmtKind::LetMutStmt(lm) => {
      let ne = self.normalize_expr(lm.expr)
      Stmt::{ kind: StmtKind::LetMutStmt(LetMutStmt::{ name: lm.name, ty: self.substitute_type_kind(self.resolve_type_kind(lm.ty)), expr: ne }) }
    }
    StmtKind::AssignStmt(a) => {
      Stmt::{ kind: StmtKind::AssignStmt(a) }
    }
    StmtKind::WhileStmt(w) => {
      let nb = self.normalize_block_expr(w.body)
      Stmt::{ kind: StmtKind::WhileStmt(WhileStmt::{ cond: self.normalize_expr(w.cond), body: nb }) }
    }
    StmtKind::ExprStmt(e) => {
      Stmt::{ kind: StmtKind::ExprStmt(self.normalize_expr(e)) }
    }
    StmtKind::ReturnStmt(eopt) => {
      match eopt {
        Some(e) => Stmt::{ kind: StmtKind::ReturnStmt(Some(self.normalize_expr(e))) }
        None => Stmt::{ kind: StmtKind::ReturnStmt(None) }
      }
    }
    StmtKind::LocalFunction(lf) => {
      // Normalize the local function parameter types and body
      let mut new_params: Array[(String, Type)] = []
      let mut i = 0
      while i < lf.param_list.length() {
        let (n, t) = lf.param_list[i]
        new_params = new_params + [(n, Type::{ kind: self.substitute_type_kind(self.resolve_type_kind(t.kind)), mutable: t.mutable })]
        i = i + 1
      }
      let nbody = self.normalize_block_expr(lf.body)
      Stmt::{ kind: StmtKind::LocalFunction(LocalFunction::{ fname: lf.fname, param_list: new_params, ret_ty: Type::{ kind: self.substitute_type_kind(self.resolve_type_kind(lf.ret_ty.kind)), mutable: lf.ret_ty.mutable }, body: nbody }) }
    }
  }
}

fn Context::normalize_block_expr(self: Context, be: BlockExpr) -> BlockExpr {
  let mut new_stmts: Array[Stmt] = []
  let mut i = 0
  while i < be.stmts.length() {
    let orig = be.stmts[i]
    let nstmt = self.normalize_stmt(orig)
    // Append normalized statement first
    new_stmts = new_stmts + [nstmt]

    // Post-process: if this statement is a call (e.g., let x = fold(...)) and
    // one of the arguments is a local function Ident whose declared parameter
    // types still contain TypeVar, but the callee's parameter type is a
    // concrete function type, update the earlier LocalFunction statement we
    // emitted to use the concrete parameter types. This fixes cases like
    // `cnt` in the generic fold test where local fn params were TypeVars.
    match nstmt.kind {
      StmtKind::LetStmt(ls) => {
        match ls.expr.kind {
          ExprKind::ApplyExpr(ae) => {
            match ae.kind {
              ApplyExprKind::Call(callee, args) => {
                // Resolve callee type to find param types
                match self.resolve_type_kind(callee.ty) {
                  TypeKind::Function(param_tys, _) => {
                    // For each arg that is an Ident, check if it references a
                    // prior LocalFunction with TypeVar params and update it.
                    let mut aj = 0
                    while aj < args.length() {
                      let aexpr = args[aj]
                      match aexpr.kind {
                        ExprKind::ApplyExpr(ae2) => {
                          match ae2.kind {
                            ApplyExprKind::AtomExpr(atom) => {
                              match atom.kind {
                                AtomExprKind::Ident(name) => {
                                  // Find a previously emitted LocalFunction with this name
                                  let mut k = 0
                                  while k < new_stmts.length() - 1 {
                                    match new_stmts[k].kind {
                                      StmtKind::LocalFunction(lf) => {
                                        if lf.fname == name {
                                          // If the local function params still contain TypeVar,
                                          // and the callee param at this position expects a
                                          // function type, replace the local function's
                                          // parameter kinds with the concrete ones.
                                          let lf_has_typevar = false
                                          // Check if the current LF param types contain TypeVar
                                          let mut pi = 0
                                          let mut need_update = false
                                          while pi < lf.param_list.length() {
                                            if lf.param_list[pi].1.kind.to_string().contains("TypeVar(") {
                                              need_update = true
                                              break
                                            }
                                            pi = pi + 1
                                          }
                                          if need_update {
                                            // If the corresponding callee param is a function,
                                            // and its parameter types are concrete, use them.
                                            if aj < param_tys.length() {
                                              match param_tys[aj] {
                                                TypeKind::Function(inner_params, _) => {
                                                  // Build new param_list for the local function
                                                  let mut new_lf_params: Array[(String, Type)] = []
                                                  let mut ii = 0
                                                  while ii < lf.param_list.length() {
                                                    let pname = lf.param_list[ii].0
                                                    let pkind = if ii < inner_params.length() { self.substitute_type_kind(inner_params[ii]) } else { self.substitute_type_kind(lf.param_list[ii].1.kind) }
                                                    new_lf_params = new_lf_params + [(pname, Type::{ kind: pkind, mutable: lf.param_list[ii].1.mutable })]
                                                    ii = ii + 1
                                                  }
                                                  // Replace the earlier LocalFunction statement in new_stmts
                                                  new_stmts[k] = Stmt::{ kind: StmtKind::LocalFunction(LocalFunction::{ fname: lf.fname, param_list: new_lf_params, ret_ty: Type::{ kind: self.substitute_type_kind(lf.ret_ty.kind), mutable: lf.ret_ty.mutable }, body: lf.body }) }
                                                }
                                                _ => ()
                                              }
                                            }
                                          }
                                        }
                                      }
                                      _ => ()
                                    }
                                    k = k + 1
                                  }
                                }
                                _ => ()
                              }
                            }
                            _ => ()
                          }
                        }
                        _ => ()
                      }
                      aj = aj + 1
                    }
                  }
                  _ => ()
                }
              }
              _ => ()
            }
          }
          _ => ()
        }
      }
      _ => ()
    }

    i = i + 1
  }

  // Patch: If block returns non-Unit and last stmt is ExprStmt, convert it
  // into an explicit ReturnStmt so downstream KNF/codegen sees a return.
  if new_stmts.length() > 0 && self.substitute_type_kind(self.resolve_type_kind(be.ty)).to_string() != "Unit" {
    let last_idx = new_stmts.length() - 1
    let last = new_stmts[last_idx]
    match last.kind {
      StmtKind::ExprStmt(expr) => {
        // Replace the final ExprStmt with an explicit ReturnStmt(Some(expr)).
        new_stmts[last_idx] = Stmt::{ kind: StmtKind::ReturnStmt(Some(expr)) }
        return BlockExpr::{ stmts: new_stmts, ty: expr.ty }
      }
      _ => ()
    }
  }
  BlockExpr::{ stmts: new_stmts, ty: self.substitute_type_kind(self.resolve_type_kind(be.ty)) }
}

// Run normalization on all checked functions and top-lets before handing to KNF
fn Context::normalize_program_types(self: Context, funcs: Map[String, TopFunction], lets: Map[String, TopLet]) -> (Map[String, TopFunction], Map[String, TopLet]) {
  let func_entries = funcs.to_array()
  let mut fi = 0
  let new_funcs: Map[String, TopFunction] = Map::new()
  while fi < func_entries.length() {
    let (name, f) = func_entries[fi]
    // normalize params
    let mut new_params: Array[Param] = []
    let mut i = 0
    while i < f.param_list.length() {
      let p = f.param_list[i]
      new_params = new_params + [Param::{ name: p.name, ty: self.substitute_type_kind(self.resolve_type_kind(p.ty)) }]
      i = i + 1
    }
    let nbody = self.normalize_block_expr(f.body)
    let nret = self.substitute_type_kind(self.resolve_type_kind(f.ret_ty))
    new_funcs.set(name, TopFunction::{ fname: f.fname, param_list: new_params, ret_ty: nret, body: nbody })
    fi = fi + 1
  }

  // Normalize top-lets
  let let_entries = lets.to_array()
  let mut li = 0
  let new_lets: Map[String, TopLet] = Map::new()
  while li < let_entries.length() {
    let (lname, l) = let_entries[li]
    let new_expr = self.normalize_expr(l.expr)
  new_lets.set(lname, TopLet::{ name: l.name, ty: Type::{ kind: self.substitute_type_kind(self.resolve_type_kind(l.ty.kind)), mutable: false }, expr: new_expr })
    li = li + 1
  }

  (new_funcs, new_lets)
}

///|
pub fn Context::collect_struct_names(
  self : Context,
  program : @parser.Program,
) -> Unit raise TypeCheckError {
  let struct_entries = program.struct_defs.to_array()
  let mut si = 0
  while si < struct_entries.length() {
    let (struct_name, _) = struct_entries[si]
    match self.struct_defs.get(struct_name) {
      Some(_) => raise TypeCheckError("Duplicate struct definition: " + struct_name)
      None => ()
    }
    let placeholder = StructDef::{ name: struct_name, type_params: [], fields: [] }
    self.struct_defs.set(struct_name, placeholder)
    si = si + 1
  }
}

///| 收集枚举名称
pub fn Context::collect_enum_names(
  self : Context,
  program : @parser.Program,
) -> Unit raise TypeCheckError {
  let enum_entries = program.enum_defs.to_array()
  let mut ei = 0
  while ei < enum_entries.length() {
    let (enum_name, _) = enum_entries[ei]
    match self.enum_defs.get(enum_name) {
      Some(_) => raise TypeCheckError("Duplicate enum definition: " + enum_name)
      None => ()
    }
    // Check for name conflicts with structs
    match self.struct_defs.get(enum_name) {
      Some(_) => raise TypeCheckError("Enum name conflicts with struct: " + enum_name)
      None => ()
    }
    let placeholder = EnumDef::{ name: enum_name, type_params: [], variants: [] }
    self.enum_defs.set(enum_name, placeholder)
    ei = ei + 1
  }
}

///|
pub fn Context::collect_function_types(
  self : Context,
  program : @parser.Program,
) -> Unit raise TypeCheckError {
  println("collect_function_types: starting");
  // Check for duplicate top-level let bindings
  let top_let_entries = program.top_lets.to_array()
  let mut li = 0
  while li < top_let_entries.length() {
    let (let_name, top_let) = top_let_entries[li]
    if self.type_env.get(let_name) is Some(_) {
      raise TypeCheckError("Duplicate top-level binding: " + let_name)
    }
    let placeholder_type = match top_let.ty {
      Some(parser_ty) => self.check_parser_type(parser_ty)
      None => Type::{ kind: self.allocate_fresh_type_var(), mutable: false }
    }
    self.type_env.set(let_name, placeholder_type)
    li = li + 1
  }

  // Check for duplicate function definitions and parameter names
  let func_entries = program.top_functions.to_array()
  let mut fi = 0
  while fi < func_entries.length() {
    let (func_name, top_func) = func_entries[fi]
    
    // Handle generic functions
    if top_func.type_params.length() > 0 {
      // This is a generic function - save it for later monomorphization
      self.generic_functions.set(func_name, top_func)
      self.monomorphized_instances.set(func_name, [])
      
      // Don't register generic type parameters as empty structs - this causes confusion
      // Instead, we'll handle them properly during instantiation
      
      // Register a polymorphic function type
      // For generic functions, we need to check the actual parameter types
      let mut param_kinds : Array[TypeKind] = []
      let mut i = 0
      while i < top_func.param_list.length() {
        let param_ty = self.check_parser_type(top_func.param_list[i].ty)
        param_kinds = param_kinds + [param_ty.kind]
        i = i + 1
      }
      let ret_ty = self.check_parser_type(top_func.ret_ty)
      let function_kind = TypeKind::Function(param_kinds, ret_ty.kind)
      
      self.func_types.set(func_name, function_kind)
      self.type_env.set(func_name, Type::{ kind: function_kind, mutable: false })
      
      fi = fi + 1
      continue
    }
    
    // Check for duplicate function name
    match (self.func_types.get(func_name), self.type_env.get(func_name)) {
      (Some(_), _) | (_, Some(_)) => 
        raise TypeCheckError("Duplicate function or binding: " + func_name)
      _ => ()
    }
    
    // Check for duplicate parameter names
    let mut i = 0
    let mut seen_params : Array[String] = []
    while i < top_func.param_list.length() {
      let param = top_func.param_list[i]
      // Check if parameter name is already in seen_params
      let mut j = 0
      let mut is_duplicate = false
      while j < seen_params.length() {
        if seen_params[j] == param.name {
          is_duplicate = true
          break
        }
        j = j + 1
      }
      if is_duplicate {
        raise TypeCheckError("Duplicate parameter name '" + param.name + "' in function " + func_name)
      }
      seen_params = seen_params + [param.name]
      i = i + 1
    }
    
    // Process parameter and return types
    let mut param_kinds : Array[TypeKind] = []
    i = 0
    while i < top_func.param_list.length() {
      let param = top_func.param_list[i]
      let checked_param = self.check_parser_type(param.ty)
      param_kinds = param_kinds + [self.resolve_type_kind(checked_param.kind)]
      i = i + 1
    }
    
    let checked_ret = self.check_parser_type(top_func.ret_ty)
    let ret_kind = self.resolve_type_kind(checked_ret.kind)
    let function_kind = TypeKind::Function(param_kinds, ret_kind)
    
    self.func_types.set(func_name, function_kind)
    self.type_env.set(func_name, Type::{ kind: function_kind, mutable: false })
    fi = fi + 1
  }
}

///|
fn Context::substitute_type_kind(self : Context, kind : TypeKind) -> TypeKind {
  // First resolve any TypeVars to their actual types
  match kind {
    TypeVar(id) => {
      match self.type_vars.get(id) {
        Some(resolved_kind) => resolved_kind
        None => kind  // If not found, keep the TypeVar as is
      }
    }
    _ => {
      // Then handle composite types recursively
      let resolved = self.resolve_type_kind(kind)
      match resolved {
        TypeKind::Tuple(elems) => {
          let mut resolved_elems : Array[TypeKind] = []
          let mut i = 0
          while i < elems.length() {
            resolved_elems = resolved_elems + [self.substitute_type_kind(elems[i])]
            i = i + 1
          }
          TypeKind::Tuple(resolved_elems)
        }
        TypeKind::Array(elem) => TypeKind::Array(self.substitute_type_kind(elem))
        TypeKind::Function(params, ret) => {
          let mut resolved_params : Array[TypeKind] = []
          let mut i = 0
          while i < params.length() {
            resolved_params = resolved_params + [self.substitute_type_kind(params[i])]
            i = i + 1
          }
          TypeKind::Function(resolved_params, self.substitute_type_kind(ret))
        }
        other => other
      }
    }
  }
}

///| 查找构造器所属的枚举
pub fn Context::find_enum_for_constructor(
  self : Context,
  constructor_name : String
) -> String? {
  let enum_entries = self.enum_defs.to_array()
  let mut i = 0
  while i < enum_entries.length() {
    let (enum_name, enum_def) = enum_entries[i]
    let mut j = 0
    while j < enum_def.variants.length() {
      // Support both bare variant names (e.g. "Nil") and qualified
      // names (e.g. "Node::Nil") when resolving which enum a
      // constructor belongs to.
      let variant_name = enum_def.variants[j].name
      let qualified = enum_name + "::" + variant_name
      if variant_name == constructor_name || qualified == constructor_name {
        return Some(enum_name)
      }
      j = j + 1
    }
    i = i + 1
  }
  None
}

///|
pub fn Context::record_generic_instantiation(
  self : Context,
  func_name : String,
  concrete_types : Array[TypeKind]
) -> Unit raise TypeCheckError {
  println("DEBUG: record_generic_instantiation: func=" + func_name + ", concrete_types=" + concrete_types.to_string())
  ignore(concrete_types)
  let instances = match self.monomorphized_instances.get(func_name) {
    Some(list) => list
    None => []
  }
  
  // Check if this instantiation already exists
  let mut already_exists = false
  let mut i = 0
  while i < instances.length() {
    let (existing_types, _) = instances[i]
    if self.type_arrays_equal(existing_types, concrete_types) {
      already_exists = true
      break
    }
    i = i + 1
  }
  
  if !already_exists {
    // Generate a unique name for this instantiation
    let mut mono_name = func_name
    let mut ti = 0
    while ti < concrete_types.length() {
      mono_name = mono_name + "_" + self.type_to_mangled_string(concrete_types[ti])
      ti = ti + 1
    }
    let new_instances = instances + [(concrete_types, mono_name)]
    self.monomorphized_instances.set(func_name, new_instances)
    // If we have the generic function definition available, instantiate it
    // immediately and register a concrete signature so call-sites during
    // the same typechecking run can pick up the concrete return type.
    match self.generic_functions.get(func_name) {
      Some(gf) => {
        let instantiated = self.instantiate_generic_function(gf, concrete_types, mono_name)
        // Clean residual TypeVars in instantiated signature
        let mut cleaned_params: Array[Param] = []
        let mut ppi = 0
        while ppi < instantiated.param_list.length() {
          let p = instantiated.param_list[ppi]
          cleaned_params = cleaned_params + [Param::{ name: p.name, ty: self.substitute_type_kind(p.ty) }]
          ppi = ppi + 1
        }
        let cleaned_ret = self.substitute_type_kind(instantiated.ret_ty)
        let mut param_tys: Array[TypeKind] = []
        let mut pti = 0
        while pti < cleaned_params.length() {
          param_tys = param_tys + [cleaned_params[pti].ty]
          pti = pti + 1
        }
        let func_kind = TypeKind::Function(param_tys, cleaned_ret)
        self.func_types.set(mono_name, func_kind)
        self.type_env.set(mono_name, Type::{ kind: func_kind, mutable: false })
      }
      None => ()
    }
  }
}

///|
fn Context::type_arrays_equal(
  self : Context,
  types1 : Array[TypeKind],
  types2 : Array[TypeKind]
) -> Bool {
  if types1.length() != types2.length() {
    return false
  }
  let mut i = 0
  while i < types1.length() {
    if !self.types_equal(types1[i], types2[i]) {
      return false
    }
    i = i + 1
  }
  true
}



///|
fn Context::type_to_mangled_string(self : Context, ty : TypeKind) -> String {
  match ty {
    TypeKind::Unit => "Unit"
    TypeKind::Bool => "Bool"
    TypeKind::Int => "Int"
    TypeKind::Double => "Double"
    TypeKind::String => "String"
    TypeKind::Struct(name) => name
    TypeKind::Enum(name) => name
    TypeKind::Array(elem) => "Array_" + self.type_to_mangled_string(elem)
    TypeKind::Tuple(types) => {
      let mut result = "Tuple"
      let mut i = 0
      while i < types.length() {
        result = result + "_" + self.type_to_mangled_string(types[i])
        i = i + 1
      }
      result
    }
    _ => "Unknown"
  }
}

///|
pub fn Context::instantiate_generic_functions(
  self : Context,
  checked_functions : Map[String, TopFunction]
) -> Unit raise TypeCheckError {
  // For each generic function, create instantiated versions
  let generic_entries = self.monomorphized_instances.to_array()
  let mut gi = 0
  while gi < generic_entries.length() {
    let (func_name, instances) = generic_entries[gi]
    let generic_func = match self.generic_functions.get(func_name) {
      Some(f) => f
      None => {
        gi = gi + 1
        continue
      }
    }
    
    // For each concrete type instantiation, create a specialized function
    let mut ii = 0
    while ii < instances.length() {
      let (concrete_types, mono_name) = instances[ii]
      let mut instantiated = self.instantiate_generic_function(
        generic_func,
        concrete_types,
        mono_name
      )
      // Normalize the instantiated function body with the appropriate
      // generic binding so any residual generic Struct names (like `T`)
      // are substituted before KNF/codegen. We compute the binding the
      // same way as instantiate_generic_function would and apply it
      // temporarily while normalizing the body.
      // Handle each generic type parameter
      let mut type_param_index = 0
      while type_param_index < generic_func.type_params.length() {
        let type_param = generic_func.type_params[type_param_index]
        // Try to infer the binding from parameter positions similar to instantiate_generic_function
        let mut binding_opt : TypeKind? = None
        let mut pi = 0
        while pi < generic_func.param_list.length() {
          let p = generic_func.param_list[pi]
          if self.is_generic_type(p.ty.kind, type_param) {
            if pi < concrete_types.length() {
              match self.infer_binding_from_parser_and_concrete(p.ty.kind, concrete_types[pi], type_param) {
                Some(b) => { binding_opt = Some(b); break }
                None => { binding_opt = Some(concrete_types[pi]); break }
              }
            }
          }
          pi = pi + 1
        }
        if binding_opt is None {
          if self.is_generic_type(generic_func.ret_ty.kind, type_param) && concrete_types.length() > 0 {
            binding_opt = Some(concrete_types[0])
          } else if concrete_types.length() > 0 {
            binding_opt = Some(concrete_types[0])
          } else {
            binding_opt = Some(TypeKind::Any)
          }
        }
        let binding = binding_opt.unwrap()
        // Temporarily set generic_type_bindings
        self.generic_type_bindings.set(type_param, binding)
        type_param_index = type_param_index + 1
      }
      let normalized_body = self.normalize_block_expr(instantiated.body)
      // Create a final instantiated function with normalized body
      let final_instantiated = TopFunction::{ fname: instantiated.fname, param_list: instantiated.param_list, ret_ty: instantiated.ret_ty, body: normalized_body }
      // Use final_instantiated in place of instantiated below
      instantiated = final_instantiated
      // Substitute any residual TypeVars in the instantiated signature/body
      // using known type_var bindings so KNF/codegen sees concrete types.
      let mut cleaned_params: Array[Param] = []
      let mut ppi = 0
      while ppi < instantiated.param_list.length() {
        let p = instantiated.param_list[ppi]
        cleaned_params = cleaned_params + [Param::{ name: p.name, ty: self.substitute_type_kind(p.ty) }]
        ppi = ppi + 1
      }
      let cleaned_ret = self.substitute_type_kind(instantiated.ret_ty)
      let cleaned_top = TopFunction::{ fname: instantiated.fname, param_list: cleaned_params, ret_ty: cleaned_ret, body: instantiated.body }
      checked_functions.set(mono_name, cleaned_top)
      // Register concrete function type for the monomorphized function so
      // subsequent lookups and call-site rewrites can find the concrete
      // signature.
      let mut param_tys: Array[TypeKind] = []
      let mut pti = 0
      while pti < cleaned_params.length() {
        param_tys = param_tys + [cleaned_params[pti].ty]
        pti = pti + 1
      }
      let func_kind = TypeKind::Function(param_tys, cleaned_ret)
      self.func_types.set(mono_name, func_kind)
      self.type_env.set(mono_name, Type::{ kind: func_kind, mutable: false })
      ii = ii + 1
    }
    
    gi = gi + 1
  }
}

///|
fn Context::instantiate_generic_function(
  self : Context,
  func : @parser.TopFunction,
  concrete_types : Array[TypeKind],
  mono_name : String
) -> TopFunction raise TypeCheckError {
  // Instantiate a generic function by substituting its type parameters
  // with the provided concrete type(s), then typecheck the function body
  if func.type_params.length() == 0 {
    raise TypeCheckError("instantiate_generic_function called for non-generic function: " + func.fname)
  }
  
  // For now, we'll handle the first type parameter for simplicity
  // In a full implementation, we'd handle all type parameters
  let type_param = if func.type_params.length() > 0 { func.type_params[0] } else { "T" }
  // Determine a concrete binding for the generic parameter.
  // Prefer to infer from parameter positions where the parser type contains the type_param.
  let mut binding_opt : TypeKind? = None
  println("DEBUG: instantiate_generic_function: func.param_list.length()=" + func.param_list.length().to_string() + ", concrete_types.length()=" + concrete_types.length().to_string())
  let mut i = 0
  while i < func.param_list.length() {
    let p = func.param_list[i]
    println("DEBUG: checking param " + i.to_string() + ": name=" + p.name + ", ty=" + p.ty.kind.to_string())
    if self.is_generic_type(p.ty.kind, type_param) {
      println("DEBUG: param " + i.to_string() + " contains generic type " + type_param)
      if i < concrete_types.length() {
        // Try to infer the binding by matching the parser-level type
        // against the concrete type; this extracts the inner type when
        // the parser type is Array[T] and concrete is Array[Int], etc.
        println("DEBUG: trying to infer binding from param " + i.to_string() + ": parser_ty=" + p.ty.kind.to_string() + ", concrete_ty=" + concrete_types[i].to_string())
        match self.infer_binding_from_parser_and_concrete(p.ty.kind, concrete_types[i], type_param) {
          Some(b) => {
            println("DEBUG: inferred binding: " + b.to_string())
            binding_opt = Some(b)
            break
          }
          None => {
            println("DEBUG: failed to infer, using concrete type directly")
            binding_opt = Some(concrete_types[i])
            break
          }
        }
      }
    }
    i = i + 1
  }

  // If we couldn't find from params, try return type or fallback to first concrete type
  if binding_opt is None {
    if self.is_generic_type(func.ret_ty.kind, type_param) && concrete_types.length() > 0 {
      binding_opt = Some(concrete_types[0])
    } else if concrete_types.length() > 0 {
      binding_opt = Some(concrete_types[0])
    } else {
      // As a last resort, use Any
      binding_opt = Some(TypeKind::Any)
    }
  }

  let binding = binding_opt.unwrap()

  // DEBUG: print binding and intended substitution. The concrete binding seeded here
  // will be used to resolve generic parameters while type checking the monomorphized body.
  println("DEBUG: instantiate_generic_function: func=" + func.fname + ", type_param=" + type_param + ", binding=" + binding.to_string())

  // Build checked parameter list with substituted types
  let mut new_params: Array[TypeKind] = []
  let mut idx = 0
  while idx < func.param_list.length() {
    let p = func.param_list[idx]
    let new_kind = self.parser_typekind_to_concrete(p.ty.kind, type_param, binding)
    new_params = new_params + [new_kind]
    idx = idx + 1
  }
  // Build final Param array (name + substituted TypeKind)
  let mut final_params: Array[Param] = []
  let mut pi = 0
  while pi < func.param_list.length() {
    final_params = final_params + [Param::{ name: func.param_list[pi].name, ty: new_params[pi] }]
    pi = pi + 1
  }

  // Convert return type and resolve it to a concrete TypeKind
  let new_ret = self.parser_typekind_to_concrete(func.ret_ty.kind, type_param, binding)
  let final_ret = self.resolve_type_kind(new_ret)

  // Prepare environment and check body with the substituted types
  // Save previous generic bindings/context
  let prev_bindings = self.generic_type_bindings
  let prev_current = self.current_generic_type
  let prev_ret_ty = self.current_func_ret_ty
  let prev_checking_generic = self.checking_generic_function_body
  self.generic_type_bindings = Map::new()
  self.generic_type_bindings.set(type_param, binding)
  match binding {
    TypeKind::GenericStruct(struct_name, _) | TypeKind::Struct(struct_name) => {
      if struct_name != type_param {
        self.generic_type_bindings.set(struct_name, binding)
      }
    }
    _ => ()
  }
  self.current_generic_type = Some(type_param)
  self.current_func_ret_ty = Some(new_ret)
  self.checking_generic_function_body = true

  // Enter a fresh scope and bind parameters
  self.enter_scope()
  let mut qi = 0
  while qi < final_params.length() {
    let fp = final_params[qi]
    self.type_env.set(fp.name, Type::{ kind: fp.ty, mutable: false })
    qi = qi + 1
  }

  // Typecheck the body
  let checked_body = self.check_block_expr(func.body)
  let resolved_body_ty = self.resolve_type_kind(checked_body.ty)

  // Cleanup: restore previous environment and generic bindings
  self.exit_scope()
  self.generic_type_bindings = prev_bindings
  self.current_generic_type = prev_current
  self.current_func_ret_ty = prev_ret_ty
  self.checking_generic_function_body = prev_checking_generic

  TopFunction::{
    fname: mono_name,
    param_list: final_params,
    ret_ty: final_ret,
    body: BlockExpr::{ stmts: checked_body.stmts, ty: resolved_body_ty }
  }
}


///| Replace generic type parameters with TypeVar
fn Context::replace_generic_with_typevar(
  self : Context,
  ty : TypeKind,
  type_param : String
) -> TypeKind {
  match ty {
    TypeKind::Struct(name) => {
      if name == type_param {
        TypeKind::TypeVar(0)
      } else {
        ty
      }
    }
    TypeKind::Array(elem_ty) => {
      let replaced_elem = self.replace_generic_with_typevar(elem_ty, type_param)
      TypeKind::Array(replaced_elem)
    }
    TypeKind::Tuple(types) => {
      let replaced_types = types.map(fn(t) { self.replace_generic_with_typevar(t, type_param) })
      TypeKind::Tuple(replaced_types)
    }
    TypeKind::Function(params, ret) => {
      let replaced_params = params.map(fn(t) { self.replace_generic_with_typevar(t, type_param) })
      let replaced_ret = self.replace_generic_with_typevar(ret, type_param)
      TypeKind::Function(replaced_params, replaced_ret)
    }
    _ => ty
  }
}

/// Helper: convert a parser.TypeKind to a concrete TypeKind with substitution
pub fn Context::parser_typekind_to_concrete(
  self: Context,
  ptk: @parser.TypeKind,
  type_param: String,
  binding: TypeKind
) -> TypeKind raise TypeCheckError {
  match ptk {
    @parser.TypeKind::Unit => TypeKind::Unit
    @parser.TypeKind::Bool => TypeKind::Bool
    @parser.TypeKind::Int => TypeKind::Int
    @parser.TypeKind::Double => TypeKind::Double
    @parser.TypeKind::String => TypeKind::String
    @parser.TypeKind::Tuple(types) => {
      let mut out: Array[TypeKind] = []
      let mut j = 0
      while j < types.length() {
        out = out + [self.parser_typekind_to_concrete(types[j], type_param, binding)]
        j = j + 1
      }
      TypeKind::Tuple(out)
    }
    @parser.TypeKind::Array(elem) => TypeKind::Array(self.parser_typekind_to_concrete(elem, type_param, binding))
    @parser.TypeKind::Function(params, ret) => {
      let mut p_out: Array[TypeKind] = []
      let mut k = 0
      while k < params.length() {
        p_out = p_out + [self.parser_typekind_to_concrete(params[k], type_param, binding)]
        k = k + 1
      }
      TypeKind::Function(p_out, self.parser_typekind_to_concrete(ret, type_param, binding))
    }
    @parser.TypeKind::Defined(name) => {
      if name == type_param {
        // Substitute with the concrete binding
        binding
      } else {
        // Regular defined type: struct or enum
        if self.struct_defs.get(name) is Some(_) {
          TypeKind::Struct(name)
        } else if self.enum_defs.get(name) is Some(_) {
          TypeKind::Enum(name)
        } else {
          raise TypeCheckError("Unknown type during instantiation: " + name)
        }
      }
    }
    @parser.TypeKind::GenericEnum(name, type_args) => {
      // Properly instantiate generic enums by substituting type arguments
      let mut substituted_args: Array[TypeKind] = []
      let mut i = 0
      while i < type_args.length() {
        substituted_args = substituted_args + [self.parser_typekind_to_concrete(type_args[i], type_param, binding)]
        i = i + 1
      }
      
      // Check if this is actually a generic struct or a generic enum
      if self.struct_defs.get(name) is Some(_) {
        TypeKind::GenericStruct(name, substituted_args)
      } else if self.enum_defs.get(name) is Some(_) {
        TypeKind::GenericEnum(name, substituted_args)
      } else {
        // If we can't find it, assume it's an enum for now
        TypeKind::GenericEnum(name, substituted_args)
      }
    }
  }
}


///| Infer the concrete binding for a generic parameter by matching a parser
///| TypeKind (which may contain the type parameter) against a concrete
///| TypeKind. Returns Some(binding) if the binding for the type_param can be
///| determined, otherwise None.
fn Context::infer_binding_from_parser_and_concrete(
  self: Context,
  ptk: @parser.TypeKind,
  concrete: TypeKind,
  type_param: String
) -> TypeKind? {
  match ptk {
    @parser.TypeKind::Defined(name) => {
      if name == type_param {
        Some(concrete)
      } else {
        None
      }
    }
    @parser.TypeKind::Array(elem) => {
      match concrete {
        TypeKind::Array(c_elem) => self.infer_binding_from_parser_and_concrete(elem, c_elem, type_param)
        _ => None
      }
    }
    @parser.TypeKind::Tuple(parts) => {
      match concrete {
        TypeKind::Tuple(c_parts) => {
          if parts.length() != c_parts.length() { None }
          else {
            // Try to find a binding from any component
            let mut j = 0
            while j < parts.length() {
              match self.infer_binding_from_parser_and_concrete(parts[j], c_parts[j], type_param) {
                Some(b) => return Some(b)
                None => ()
              }
              j = j + 1
            }
            None
          }
        }
        _ => None
      }
    }
    @parser.TypeKind::Function(params, ret) => {
      match concrete {
        TypeKind::Function(c_params, c_ret) => {
          // Try to infer from parameters first
          let mut j = 0
          while j < params.length() && j < c_params.length() {
            match self.infer_binding_from_parser_and_concrete(params[j], c_params[j], type_param) {
              Some(b) => return Some(b)
              None => ()
            }
            j = j + 1
          }
          // Try return
          self.infer_binding_from_parser_and_concrete(ret, c_ret, type_param)
        }
        _ => None
      }
    }
    _ => None
  }
}
