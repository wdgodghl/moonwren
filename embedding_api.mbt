///|
/// Typed result returned by host-side inspection and mutation helpers.
pub(all) enum VmHostResult[T] {
  VmHostSucceeded(T)
  VmHostFailed(Diagnostic)
}

///|
pub(all) struct VmMapEntry {
  key : Value
  value : Value
}

///|
/// Cached receiver, method name, and arity for repeated host calls.
pub struct VmMethodHandle {
  vm_identity : Int
  generation : Int
  receiver : VmHandle
  method_name : String
  arity : Int
}

///|
pub(all) enum VmMethodHandleResult {
  VmMethodHandleCreated(VmMethodHandle)
  VmMethodHandleFailed(Diagnostic)
}

///|
fn host_access_error(message : String) -> Diagnostic {
  Diagnostic::new(Runtime, InvalidOperand, message, SourceSpan::empty()).with_source(
    "<host>",
  )
}

///|
pub fn Vm::has_module(self : Vm, module_name : String) -> Bool {
  !self.closed && find_runtime_module(self.runtime(), module_name) is Some(_)
}

///|
pub fn Vm::has_variable(
  self : Vm,
  module_name : String,
  variable : String,
) -> Bool {
  if self.closed {
    return false
  }
  match find_runtime_module(self.runtime(), module_name) {
    None => false
    Some(index) =>
      self.runtime().modules[index].environment.get(variable) is Some(_)
  }
}

///|
pub fn Vm::bind_method(
  self : Vm,
  receiver : VmHandle,
  method_name : String,
  arity : Int,
) -> VmMethodHandleResult {
  if self.closed {
    return VmMethodHandleFailed(host_access_error("VM is closed"))
  }
  if method_name.length() == 0 || arity < 0 {
    return VmMethodHandleFailed(
      host_access_error("method name must be non-empty and arity non-negative"),
    )
  }
  match self.resolve_handle(receiver) {
    None =>
      VmMethodHandleFailed(host_access_error("receiver handle is invalid"))
    Some(_) =>
      VmMethodHandleCreated({
        vm_identity: self.identity,
        generation: self.generation,
        receiver,
        method_name,
        arity,
      })
  }
}

///|
pub fn Vm::call_bound(
  self : Vm,
  bound : VmMethodHandle,
  arguments : Array[Value],
) -> ProgramRunResult {
  if bound.vm_identity != self.identity || bound.generation != self.generation {
    return ProgramFailed(
      [host_access_error("method handle belongs to another VM generation")],
      [],
    )
  }
  if arguments.length() != bound.arity {
    return ProgramFailed(
      [
        Diagnostic::new(
          Runtime,
          InvalidArity,
          "bound method expects \{bound.arity} arguments, received \{arguments.length()}",
          SourceSpan::empty(),
        ).with_source("<host>"),
      ],
      [],
    )
  }
  self.call_method(bound.receiver, bound.method_name, arguments)
}

///|
fn Vm::resolved_collection(self : Vm, handle : VmHandle) -> VmHostResult[Value] {
  if self.closed {
    return VmHostFailed(host_access_error("VM is closed"))
  }
  match self.resolve_handle(handle) {
    Some(value) => VmHostSucceeded(value)
    None => VmHostFailed(host_access_error("collection handle is invalid"))
  }
}

///|
pub fn Vm::list_snapshot(
  self : Vm,
  handle : VmHandle,
) -> VmHostResult[Array[Value]] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(ListValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.lists.length() ||
        !context.lists[identifier].alive {
        return VmHostFailed(host_access_error("list has been collected"))
      }
      let copied : Array[Value] = []
      for value in context.lists[identifier].items {
        copied.push(value)
      }
      VmHostSucceeded(copied)
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected List, received \{value.type_name()}"),
      )
  }
}

///|
pub fn Vm::list_set(
  self : Vm,
  handle : VmHandle,
  index : Int,
  value : Value,
) -> VmHostResult[Unit] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(ListValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.lists.length() ||
        !context.lists[identifier].alive {
        return VmHostFailed(host_access_error("list has been collected"))
      }
      let items = context.lists[identifier].items
      let normalized = if index < 0 { items.length() + index } else { index }
      if normalized < 0 || normalized >= items.length() {
        VmHostFailed(host_access_error("list index is out of bounds"))
      } else {
        items[normalized] = value
        VmHostSucceeded(())
      }
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected List, received \{value.type_name()}"),
      )
  }
}

///|
pub fn Vm::list_add(
  self : Vm,
  handle : VmHandle,
  value : Value,
) -> VmHostResult[Unit] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(ListValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.lists.length() ||
        !context.lists[identifier].alive {
        return VmHostFailed(host_access_error("list has been collected"))
      }
      context.lists[identifier].items.push(value)
      VmHostSucceeded(())
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected List, received \{value.type_name()}"),
      )
  }
}

///|
pub fn Vm::map_snapshot(
  self : Vm,
  handle : VmHandle,
) -> VmHostResult[Array[VmMapEntry]] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(MapValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        return VmHostFailed(host_access_error("map has been collected"))
      }
      let copied : Array[VmMapEntry] = []
      for entry in context.maps[identifier].entries {
        copied.push({ key: entry.key, value: entry.value, })
      }
      VmHostSucceeded(copied)
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected Map, received \{value.type_name()}"),
      )
  }
}

///|
pub fn Vm::map_get(
  self : Vm,
  handle : VmHandle,
  key : Value,
) -> VmHostResult[Value?] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(MapValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        return VmHostFailed(host_access_error("map has been collected"))
      }
      let entries = context.maps[identifier].entries
      match find_map_key(entries, key) {
        Some(index) => VmHostSucceeded(Some(entries[index].value))
        None => VmHostSucceeded(None)
      }
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected Map, received \{value.type_name()}"),
      )
  }
}

///|
pub fn Vm::map_set(
  self : Vm,
  handle : VmHandle,
  key : Value,
  value : Value,
) -> VmHostResult[Unit] {
  if !is_valid_map_key(key) {
    return VmHostFailed(host_access_error("map key must be immutable"))
  }
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(MapValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        return VmHostFailed(host_access_error("map has been collected"))
      }
      ignore(context.set_map_entry(identifier, key, value))
      VmHostSucceeded(())
    }
    VmHostSucceeded(other) =>
      VmHostFailed(
        host_access_error("expected Map, received \{other.type_name()}"),
      )
  }
}

///|
pub fn Vm::map_remove(
  self : Vm,
  handle : VmHandle,
  key : Value,
) -> VmHostResult[Value?] {
  match self.resolved_collection(handle) {
    VmHostFailed(issue) => VmHostFailed(issue)
    VmHostSucceeded(MapValue(identifier)) => {
      let context = self.runtime()
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        return VmHostFailed(host_access_error("map has been collected"))
      }
      let entries = context.maps[identifier].entries
      match find_map_key(entries, key) {
        Some(index) => VmHostSucceeded(Some(entries.remove(index).value))
        None => VmHostSucceeded(None)
      }
    }
    VmHostSucceeded(value) =>
      VmHostFailed(
        host_access_error("expected Map, received \{value.type_name()}"),
      )
  }
}

///|
/// Deliver captured output and diagnostics through host callbacks while
/// retaining the ordinary result for further inspection.
pub fn ProgramRunResult::deliver(
  self : ProgramRunResult,
  write : (String) -> Unit,
  report : (Diagnostic) -> Unit,
) -> ProgramRunResult {
  match self {
    ProgramCompleted(_, output) =>
      for line in output {
        write(line)
      }
    ProgramFailed(issues, output) => {
      for line in output {
        write(line)
      }
      for issue in issues {
        report(issue)
      }
    }
  }
  self
}
