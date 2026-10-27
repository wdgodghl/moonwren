///|
/// A source breakpoint for the live tree-walking interpreter.
pub(all) struct DebugBreakpoint {
  source_name : String
  line : Int
}

///|
pub fn DebugBreakpoint::new(
  source_name : String,
  line : Int,
) -> DebugBreakpoint {
  { source_name, line, }
}

///|
/// One visible variable copied at a debugger stop.
pub(all) struct DebugVariable {
  name : String
  value : Value
}

///|
/// Live state captured immediately before a statement executes.
pub(all) struct DebugSnapshot {
  source_name : String
  span : SourceSpan
  call_depth : Int
  variables : Array[DebugVariable]
}

///|
/// The command returned synchronously by a live debugger hook.
pub(all) enum DebugCommand {
  DebugContinue
  DebugStepInto
  DebugStepOver
  DebugStepOut
  DebugTerminate
}

///|
priv struct RuntimeDebugger {
  breakpoints : Array[DebugBreakpoint]
  hook : (DebugSnapshot) -> DebugCommand
  mut mode : Int
  mut target_depth : Int
}

///|
fn debug_breakpoint_matches(
  breakpoints : Array[DebugBreakpoint],
  source_name : String,
  line : Int,
) -> Bool {
  for breakpoint in breakpoints {
    if breakpoint.source_name == source_name && breakpoint.line == line {
      return true
    }
  }
  false
}

///|
fn RuntimeContext::debug_before_statement(
  self : RuntimeContext,
  span : SourceSpan,
  environment : Environment,
) -> Diagnostic? {
  let debugger = match self.debugger {
    Some(debugger) => debugger
    None => return None
  }
  let should_pause = debug_breakpoint_matches(
      debugger.breakpoints,
      self.current_source,
      span.line(),
    ) ||
    debugger.mode == 1 ||
    (debugger.mode == 2 && self.call_depth <= debugger.target_depth) ||
    (debugger.mode == 3 && self.call_depth < debugger.target_depth)
  if !should_pause {
    return None
  }
  let snapshot : DebugSnapshot = {
    source_name: self.current_source,
    span,
    call_depth: self.call_depth,
    variables: environment.debug_bindings(),
  }
  match (debugger.hook)(snapshot) {
    DebugContinue => debugger.mode = 0
    DebugStepInto => debugger.mode = 1
    DebugStepOver => {
      debugger.mode = 2
      debugger.target_depth = self.call_depth
    }
    DebugStepOut => {
      debugger.mode = 3
      debugger.target_depth = self.call_depth
    }
    DebugTerminate =>
      return Some(
        Diagnostic::new(
          Runtime,
          DebugTerminated,
          "execution terminated by debugger",
          span,
        ).with_source(self.current_source),
      )
  }
  None
}

///|
/// Attach a synchronous live debugger to this VM. The hook executes before a
/// statement and may inspect current variables and select the next stop mode.
/// A hook used by a UI may block while waiting for user input, but must not
/// re-enter the same VM.
pub fn Vm::attach_debugger(
  self : Vm,
  breakpoints : Array[DebugBreakpoint],
  pause_on_entry : Bool,
  hook : (DebugSnapshot) -> DebugCommand,
) -> Bool {
  if self.closed {
    return false
  }
  let copied : Array[DebugBreakpoint] = []
  for breakpoint in breakpoints {
    if breakpoint.source_name.length() > 0 && breakpoint.line > 0 {
      copied.push(breakpoint)
    }
  }
  self.runtime().debugger = Some({
    breakpoints: copied,
    hook,
    mode: if pause_on_entry {
      1
    } else {
      0
    },
    target_depth: 0,
  })
  true
}

///|
pub fn Vm::detach_debugger(self : Vm) -> Bool {
  if self.closed {
    return false
  }
  self.runtime().debugger = None
  true
}
