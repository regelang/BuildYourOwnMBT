/// 演示增强的错误日志功能

/// 示例 1: 基本的错误上下文
pub fn demo_basic_error() -> Unit {
  let source_code = 
    #|fn main() {
    #|  let x = 10
    #|  let y = "hello"
    #|  let z = x + y  // 类型错误
    #|}
  
  println("=== 示例 1: 基本错误上下文 ===\n")
  
  let error_location = SourceLocation::new(4, 11, 50, 5)
  let context = ErrorContext::new(
    Some(error_location),
    source_code,
    "Type mismatch: cannot add Int and String",
    []
  )
  
  println(context.format())
}

/// 示例 2: 带堆栈跟踪的错误
pub fn demo_error_with_stack() -> Unit {
  let source_code = "let result = divide(10, 0)"
  
  println("\n=== 示例 2: 带堆栈跟踪的错误 ===\n")
  
  let stack_trace = [
    "divide (math.mbt:15)",
    "calculate (main.mbt:42)",
    "process_data (main.mbt:28)",
    "main (main.mbt:10)"
  ]
  
  let location = SourceLocation::new(1, 14, 13, 12)
  let context = ErrorContext::new(
    Some(location),
    source_code,
    "Division by zero",
    stack_trace
  )
  
  println(context.format())
}

/// 示例 3: 使用 SimpleLocationTracker
pub fn demo_location_tracker() -> Unit {
  println("\n=== 示例 3: 位置跟踪器 ===\n")
  
  let tracker = SimpleLocationTracker::new()
  let code = "let x = 42\nlet y = 3.14"
  
  println("跟踪代码: \{code}\n")
  
  tracker.advance_by(code)
  
  println("最终位置:")
  println("  行号: \{tracker.get_line()}")
  println("  列号: \{tracker.get_column()}")
  println("  偏移: \{tracker.get_offset()}")
  
  let snapshot = tracker.snapshot(0)
  println("\n位置快照: \{snapshot}")
}

/// 示例 4: 使用 CachedLocationTracker
pub fn demo_cached_tracker() -> Unit {
  println("\n=== 示例 4: 带缓存的位置跟踪器 ===\n")
  
  let tracker = CachedLocationTracker::new()
  
  println("初始位置: 行\{tracker.get_line()}, 列\{tracker.get_column()}")
  
  tracker.advance_by("hello")
  println("前进 'hello' 后: 行\{tracker.get_line()}, 列\{tracker.get_column()}")
  
  tracker.save_position()
  println("保存位置")
  
  tracker.advance_by(" world")
  println("前进 ' world' 后: 行\{tracker.get_line()}, 列\{tracker.get_column()}")
  
  let _ = tracker.restore_position()
  println("恢复位置后: 行\{tracker.get_line()}, 列\{tracker.get_column()}")
}

/// 示例 5: 多行错误显示
pub fn demo_multiline_error() -> Unit {
  let source_code = 
    #|struct Point {
    #|  x : Int
    #|  y : Int
    #|}
    #|
    #|fn distance(p1 : Point, p2 : Point) -> Double {
    #|  let dx = p1.x - p2.x
    #|  let dy = p1.y - p2.y
    #|  sqrt(dx * dx + dy * dy)
    #|}
  
  println("\n=== 示例 5: 多行代码中的错误 ===\n")
  
  let location = SourceLocation::new(7, 12, 95, 4)
  let context = ErrorContext::new(
    Some(location),
    source_code,
    "Variable 'p1' not found in scope",
    ["distance (geometry.mbt:7)", "main (main.mbt:15)"]
  )
  
  println(context.format())
}

/// 示例 6: 使用 Locatable trait
pub fn demo_locatable_trait() -> Unit {
  println("\n=== 示例 6: Locatable Trait ===\n")
  
  let context = ErrorContext::new(
    None,
    "let x = undefined_var",
    "Undefined variable",
    []
  )
  
  println("原始错误（无位置）:")
  match context.get_location() {
    Some(_) => println("  有位置信息")
    None => println("  无位置信息")
  }
  
  let location = SourceLocation::new(1, 9, 8, 13)
  let with_location = context.with_location(location)
  
  println("\n添加位置后:")
  match with_location.get_location() {
    Some(loc) => println("  位置: 行\{loc.line}, 列\{loc.column}")
    None => println("  无位置信息")
  }
}

/// 运行所有示例
pub fn run_all_demos() -> Unit {
  demo_basic_error()
  demo_error_with_stack()
  demo_location_tracker()
  demo_cached_tracker()
  demo_multiline_error()
  demo_locatable_trait()
  
  println("\n=== 所有示例运行完成 ===")
}
