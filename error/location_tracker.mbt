/// Trait: 位置跟踪器
/// 
/// 任何需要跟踪源代码位置的类型都可以实现这个 trait
pub trait LocationTracker {
  /// 获取当前行号
  get_line(Self) -> Int
  
  /// 获取当前列号
  get_column(Self) -> Int
  
  /// 获取当前偏移量
  get_offset(Self) -> Int
  
  /// 前进一个字符
  advance(Self, Char) -> Unit
  
  /// 创建当前位置的快照
  snapshot(Self, Int) -> SourceLocation
}

/// 简单的位置跟踪器实现
pub struct SimpleLocationTracker {
  mut line : Int
  mut column : Int
  mut offset : Int
} derive(Show)

/// 创建新的简单位置跟踪器
pub fn SimpleLocationTracker::new() -> SimpleLocationTracker {
  SimpleLocationTracker::{ line: 1, column: 1, offset: 0 }
}

/// 为 SimpleLocationTracker 实现 LocationTracker trait
pub impl LocationTracker for SimpleLocationTracker with get_line(self) {
  self.line
}

pub impl LocationTracker for SimpleLocationTracker with get_column(self) {
  self.column
}

pub impl LocationTracker for SimpleLocationTracker with get_offset(self) {
  self.offset
}

pub impl LocationTracker for SimpleLocationTracker with advance(self, ch) {
  if ch == '\n' {
    self.line = self.line + 1
    self.column = 1
  } else {
    self.column = self.column + 1
  }
  self.offset = self.offset + 1
}

pub impl LocationTracker for SimpleLocationTracker with snapshot(self, length) {
  SourceLocation::new(self.line, self.column, self.offset, length)
}

/// 辅助方法：前进多个字符
pub fn SimpleLocationTracker::advance_by(self : SimpleLocationTracker, text : String) -> Unit {
  let mut i = 0
  while i < text.length() {
    match text.get(i) {
      Some(ch_code) => self.advance(ch_code.unsafe_to_char())
      None => break
    }
    i = i + 1
  }
}

/// 辅助方法：前进指定数量的字符
pub fn SimpleLocationTracker::advance_count(self : SimpleLocationTracker, count : Int) -> Unit {
  let mut i = 0
  while i < count {
    self.column = self.column + 1
    self.offset = self.offset + 1
    i = i + 1
  }
}

/// 示例：带缓存的位置跟踪器
/// 可以保存和恢复位置
pub struct CachedLocationTracker {
  mut line : Int
  mut column : Int
  mut offset : Int
  saved_positions : Array[SourceLocation]
} derive(Show)

/// 创建新的带缓存的位置跟踪器
pub fn CachedLocationTracker::new() -> CachedLocationTracker {
  CachedLocationTracker::{ 
    line: 1, 
    column: 1, 
    offset: 0,
    saved_positions: []
  }
}

/// 为 CachedLocationTracker 实现 LocationTracker trait
pub impl LocationTracker for CachedLocationTracker with get_line(self) {
  self.line
}

pub impl LocationTracker for CachedLocationTracker with get_column(self) {
  self.column
}

pub impl LocationTracker for CachedLocationTracker with get_offset(self) {
  self.offset
}

pub impl LocationTracker for CachedLocationTracker with advance(self, ch) {
  if ch == '\n' {
    self.line = self.line + 1
    self.column = 1
  } else {
    self.column = self.column + 1
  }
  self.offset = self.offset + 1
}

pub impl LocationTracker for CachedLocationTracker with snapshot(self, length) {
  SourceLocation::new(self.line, self.column, self.offset, length)
}

/// 保存当前位置
pub fn CachedLocationTracker::save_position(self : CachedLocationTracker) -> Unit {
  let pos = self.snapshot(0)
  self.saved_positions.push(pos)
}

/// 恢复到上一个保存的位置
pub fn CachedLocationTracker::restore_position(self : CachedLocationTracker) -> Bool {
  if self.saved_positions.length() > 0 {
    let pos = self.saved_positions.pop().unwrap()
    match (pos.line, pos.column) {
      (Some(l), Some(c)) => {
        self.line = l
        self.column = c
        self.offset = pos.offset
      }
      _ => ()
    }
    true
  } else {
    false
  }
}

/// 清除所有保存的位置
pub fn CachedLocationTracker::clear_saved(self : CachedLocationTracker) -> Unit {
  self.saved_positions.clear()
}

/// 辅助方法：前进多个字符
pub fn CachedLocationTracker::advance_by(self : CachedLocationTracker, text : String) -> Unit {
  let mut i = 0
  while i < text.length() {
    match text.get(i) {
      Some(ch_code) => self.advance(ch_code.unsafe_to_char())
      None => break
    }
    i = i + 1
  }
}
