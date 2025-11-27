test "SourceLocation creation" {
  let loc = SourceLocation::new(10, 5, 100, 3)
  assert_eq!(loc.line, Some(10))
  assert_eq!(loc.column, Some(5))
  assert_eq!(loc.offset, 100)
  assert_eq!(loc.length, 3)
}

test "ErrorContext format with location" {
  let source = "let x = 10\nlet y = 20\nlet z = x + y"
  let loc = SourceLocation::new(3, 9, 33, 5)
  let context = ErrorContext::new(
    Some(loc),
    source,
    "Test error message",
    ["function1", "function2"]
  )
  
  let formatted = context.format()
  assert_true!(formatted.contains("Error: Test error message"))
  assert_true!(formatted.contains("line 3"))
  assert_true!(formatted.contains("column 9"))
  assert_true!(formatted.contains("Stack trace"))
}

test "ErrorContext format without location" {
  let context = ErrorContext::new(
    None,
    "",
    "Generic error",
    []
  )
  
  let formatted = context.format()
  assert_true!(formatted.contains("Error: Generic error"))
  assert_false!(formatted.contains("line"))
}

test "SimpleLocationTracker advance" {
  let tracker = SimpleLocationTracker::new()
  assert_eq!(tracker.get_line(), 1)
  assert_eq!(tracker.get_column(), 1)
  assert_eq!(tracker.get_offset(), 0)
  
  tracker.advance('a')
  assert_eq!(tracker.get_line(), 1)
  assert_eq!(tracker.get_column(), 2)
  assert_eq!(tracker.get_offset(), 1)
  
  tracker.advance('\n')
  assert_eq!(tracker.get_line(), 2)
  assert_eq!(tracker.get_column(), 1)
  assert_eq!(tracker.get_offset(), 2)
}

test "SimpleLocationTracker snapshot" {
  let tracker = SimpleLocationTracker::new()
  tracker.advance('h')
  tracker.advance('e')
  tracker.advance('l')
  tracker.advance('l')
  tracker.advance('o')
  
  let loc = tracker.snapshot(5)
  assert_eq!(loc.line, Some(1))
  assert_eq!(loc.column, Some(6))
  assert_eq!(loc.offset, 5)
  assert_eq!(loc.length, 5)
}

test "SimpleLocationTracker advance_by" {
  let tracker = SimpleLocationTracker::new()
  tracker.advance_by("hello")
  
  assert_eq!(tracker.get_line(), 1)
  assert_eq!(tracker.get_column(), 6)
  assert_eq!(tracker.get_offset(), 5)
}

test "SimpleLocationTracker advance_by with newline" {
  let tracker = SimpleLocationTracker::new()
  tracker.advance_by("line1\nline2")
  
  assert_eq!(tracker.get_line(), 2)
  assert_eq!(tracker.get_column(), 6)
  assert_eq!(tracker.get_offset(), 11)
}

test "CachedLocationTracker save and restore" {
  let tracker = CachedLocationTracker::new()
  
  tracker.advance('a')
  tracker.advance('b')
  tracker.save_position()
  
  tracker.advance('c')
  tracker.advance('d')
  assert_eq!(tracker.get_column(), 5)
  
  let restored = tracker.restore_position()
  assert_true!(restored)
  assert_eq!(tracker.get_column(), 3)
}

test "split_lines helper" {
  let source = "line1\nline2\nline3"
  let lines = split_lines(source)
  assert_eq!(lines.length(), 3)
  assert_eq!(lines[0], "line1")
  assert_eq!(lines[1], "line2")
  assert_eq!(lines[2], "line3")
}

test "ErrorContext with_stack_trace" {
  let context = ErrorContext::new(
    None,
    "source code",
    "error message",
    []
  )
  
  let with_stack = context.with_stack_trace(["func1", "func2"])
  assert_eq!(with_stack.stack_trace.length(), 2)
  assert_eq!(with_stack.stack_trace[0], "func1")
}

test "Locatable trait for ErrorContext" {
  let loc = SourceLocation::new(5, 10, 50, 3)
  let context = ErrorContext::new(
    None,
    "code",
    "message",
    []
  )
  
  let with_loc = context.with_location(loc)
  match with_loc.get_location() {
    Some(l) => {
      assert_eq!(l.line, Some(5))
      assert_eq!(l.column, Some(10))
    }
    None => abort("Expected location")
  }
}
