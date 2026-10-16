///|
/// A one-based location in a source file.
pub(all) struct SourcePosition {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub extend SourcePosition with Eq::{equal, not_equal}

///|
pub extend SourcePosition with Debug::{to_repr}

///|
/// Half-open source range. `start` is inclusive and `end` is exclusive.
pub(all) struct SourceSpan {
  start : SourcePosition
  end : SourcePosition
} derive(Eq, Debug)

///|
pub extend SourceSpan with Eq::{equal, not_equal}

///|
pub extend SourceSpan with Debug::{to_repr}

///|
pub fn SourcePosition::start() -> SourcePosition {
  { offset: 0, line: 1, column: 1, }
}

///|
pub fn SourceSpan::empty() -> SourceSpan {
  let position = SourcePosition::start()
  { start: position, end: position, }
}

///|
pub fn SourceSpan::merge(first : SourceSpan, second : SourceSpan) -> SourceSpan {
  { start: first.start, end: second.end, }
}

///|
pub fn SourceSpan::line(self : SourceSpan) -> Int {
  self.start.line
}

///|
pub fn SourceSpan::column(self : SourceSpan) -> Int {
  self.start.column
}

///|
pub fn SourceSpan::length(self : SourceSpan) -> Int {
  self.end.offset - self.start.offset
}
