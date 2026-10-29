///|
/// Transport-neutral Debug Adapter Protocol session backed by MoonWren's live
/// debugger. Frontends queue commands before execution; every real stop is
/// retained as a DAP-style snapshot.
pub(all) struct DebugAdapterSession {
  mut breakpoints : Array[DebugBreakpoint]
  commands : Array[DebugCommand]
  snapshots : Array[DebugSnapshot]
  mut pause_on_entry : Bool
}

///|
pub fn DebugAdapterSession::new() -> DebugAdapterSession {
  { breakpoints: [], commands: [], snapshots: [], pause_on_entry: true, }
}

///|
pub fn DebugAdapterSession::set_breakpoints(
  self : DebugAdapterSession,
  source_name : String,
  lines : Array[Int],
) -> Array[DebugBreakpoint] {
  let retained : Array[DebugBreakpoint] = []
  for breakpoint in self.breakpoints {
    if breakpoint.source_name != source_name {
      retained.push(breakpoint)
    }
  }
  for line in lines {
    if line > 0 {
      retained.push(DebugBreakpoint::new(source_name, line))
    }
  }
  self.breakpoints = retained
  self.breakpoints
}

///|
pub fn DebugAdapterSession::set_pause_on_entry(
  self : DebugAdapterSession,
  enabled : Bool,
) -> Unit {
  self.pause_on_entry = enabled
}

///|
pub fn DebugAdapterSession::enqueue(
  self : DebugAdapterSession,
  command : DebugCommand,
) -> Unit {
  self.commands.push(command)
}

///|
pub fn DebugAdapterSession::clear_stops(self : DebugAdapterSession) -> Unit {
  self.snapshots.clear()
}

///|
pub fn DebugAdapterSession::stops(
  self : DebugAdapterSession,
) -> Array[DebugSnapshot] {
  self.snapshots.copy()
}

///|
pub fn DebugAdapterSession::attach(self : DebugAdapterSession, vm : Vm) -> Bool {
  vm.attach_debugger(self.breakpoints, self.pause_on_entry, fn(snapshot) {
    self.snapshots.push(snapshot)
    if self.commands.is_empty() {
      DebugContinue
    } else {
      self.commands.remove(0)
    }
  })
}

///|
pub fn DebugAdapterSession::detach(self : DebugAdapterSession, vm : Vm) -> Bool {
  ignore(self)
  vm.detach_debugger()
}
