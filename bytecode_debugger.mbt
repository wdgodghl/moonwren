///|
/// Result of advancing a captured bytecode execution trace.
pub(all) enum BytecodeDebugResult {
  DebuggerPaused(BytecodeTraceEvent)
  DebuggerFinished(BytecodeRunResult)
}

///|
/// Deterministic debugger cursor over a bytecode trace. It is intentionally a
/// replay debugger: execution is captured once, then frontends can single-step
/// or continue between source-line breakpoints without changing program state.
pub struct BytecodeTraceDebugger {
  trace : BytecodeTrace
  breakpoints : Array[Int32]
  mut cursor : Int32
}

///|
pub fn BytecodeTraceDebugger::new(
  trace : BytecodeTrace,
  breakpoints : Array[Int32],
) -> BytecodeTraceDebugger {
  { trace, breakpoints, cursor: 0, }
}

///|
pub fn BytecodeTraceDebugger::position(self : BytecodeTraceDebugger) -> Int32 {
  self.cursor
}

///|
pub fn BytecodeTraceDebugger::event_count(
  self : BytecodeTraceDebugger,
) -> Int32 {
  self.trace.events.length()
}

///|
pub fn BytecodeTraceDebugger::reset(self : BytecodeTraceDebugger) -> Unit {
  self.cursor = 0
}

///|
pub fn BytecodeTraceDebugger::step(
  self : BytecodeTraceDebugger,
) -> BytecodeDebugResult {
  if self.cursor >= self.trace.events.length() {
    return DebuggerFinished(self.trace.result)
  }
  let event = self.trace.events[self.cursor]
  self.cursor = self.cursor + 1
  DebuggerPaused(event)
}

///|
fn BytecodeTraceDebugger::is_breakpoint(
  self : BytecodeTraceDebugger,
  line : Int32,
) -> Bool {
  for breakpoint in self.breakpoints {
    if breakpoint == line {
      return true
    }
  }
  false
}

///|
/// Advance until the next event whose source line is a configured breakpoint.
/// If no later breakpoint is hit, return the program's final result.
pub fn BytecodeTraceDebugger::continue_execution(
  self : BytecodeTraceDebugger,
) -> BytecodeDebugResult {
  while self.cursor < self.trace.events.length() {
    let event = self.trace.events[self.cursor]
    self.cursor = self.cursor + 1
    if self.is_breakpoint(event.instruction.span.line()) {
      return DebuggerPaused(event)
    }
  }
  DebuggerFinished(self.trace.result)
}
