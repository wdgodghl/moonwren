///|
/// A host-owned, resumable Wren Fiber. The task retains the Fiber while it is
/// suspended, so unrelated VM operations and garbage collections are safe.
pub struct VmAsyncTask {
  vm_identity : Int32
  generation : Int32
  fiber : VmHandle
  mut sequence : Int32
  mut started : Bool
  mut waiting : Bool
  mut finished : Bool
  mut cancelled : Bool
  mut request_root : VmHandle?
}

///|
/// A single yielded host request. Requests are one-shot: only the matching
/// task and sequence can consume them.
pub struct VmAsyncRequest {
  vm_identity : Int32
  generation : Int32
  task_handle : Int32
  sequence : Int32
  value : Value
}

///|
pub(all) enum VmAsyncTaskResult {
  VmAsyncTaskCreated(VmAsyncTask)
  VmAsyncTaskCreateFailed(Diagnostic)
}

///|
pub(all) enum VmAsyncRunResult {
  VmAsyncYielded(VmAsyncRequest, Array[String])
  VmAsyncCompleted(Value, Array[String])
  VmAsyncFailed(Array[Diagnostic], Array[String])
}

///|
pub fn VmAsyncRequest::value(self : VmAsyncRequest) -> Value {
  self.value
}

///|
pub fn VmAsyncRequest::sequence(self : VmAsyncRequest) -> Int32 {
  self.sequence
}

///|
fn async_issue(message : String) -> Diagnostic {
  Diagnostic::new(Runtime, InvalidFiberState, message, SourceSpan::empty()).with_source(
    "<host>",
  )
}

///|
fn async_failure(message : String) -> VmAsyncRunResult {
  VmAsyncFailed([async_issue(message)], [])
}

///|
/// Retain a captured Fiber as a resumable host task.
pub fn Vm::new_async_task(self : Vm, fiber : VmHandle) -> VmAsyncTaskResult {
  if self.closed {
    return VmAsyncTaskCreateFailed(async_issue("VM is closed"))
  }
  let value = match self.resolve_handle(fiber) {
    Some(value) => value
    None =>
      return VmAsyncTaskCreateFailed(
        async_issue("Fiber handle is invalid or released"),
      )
  }
  match value {
    FiberValue(identifier) => {
      let context = self.runtime()
      if identifier <= 0 ||
        identifier >= context.fibers.length() ||
        !context.fibers[identifier].alive {
        return VmAsyncTaskCreateFailed(
          async_issue("Fiber is not available in this runtime"),
        )
      }
    }
    other =>
      return VmAsyncTaskCreateFailed(
        async_issue("expected Fiber, received \{other.type_name()}"),
      )
  }
  match self.retain(value) {
    VmHandleFailed(issue) => VmAsyncTaskCreateFailed(issue)
    VmHandleCreated(retained) =>
      VmAsyncTaskCreated({
        vm_identity: self.identity,
        generation: self.generation,
        fiber: retained,
        sequence: 0,
        started: false,
        waiting: false,
        finished: false,
        cancelled: false,
        request_root: None,
      })
  }
}

///|
fn Vm::validate_async_task(self : Vm, task : VmAsyncTask) -> String? {
  if self.closed {
    Some("VM is closed")
  } else if task.vm_identity != self.identity ||
    task.generation != self.generation {
    Some("async task belongs to another VM generation")
  } else if task.cancelled {
    Some("async task is cancelled")
  } else if task.finished {
    Some("async task is already complete")
  } else if self.resolve_handle(task.fiber) is None {
    Some("async task Fiber is no longer available")
  } else {
    None
  }
}

///|
fn Vm::finish_async_task(self : Vm, task : VmAsyncTask) -> Unit {
  match task.request_root {
    Some(root) => ignore(self.release(root))
    None => ()
  }
  task.request_root = None
  ignore(self.release(task.fiber))
  task.waiting = false
  task.finished = true
}

///|
fn Vm::drive_async_task(
  self : Vm,
  task : VmAsyncTask,
  input : Value?,
) -> VmAsyncRunResult {
  let result = match input {
    Some(value) => self.call_method(task.fiber, "call", [value])
    None => self.call_method(task.fiber, "call", [])
  }
  match result {
    ProgramFailed(issues, output) => {
      self.finish_async_task(task)
      VmAsyncFailed(issues, output)
    }
    ProgramCompleted(value, output) => {
      let fiber_identifier = match self.resolve_handle(task.fiber) {
        Some(FiberValue(identifier)) => identifier
        _ => {
          self.finish_async_task(task)
          return async_failure("async task Fiber is no longer available")
        }
      }
      let context = self.runtime()
      if fiber_identifier < 0 || fiber_identifier >= context.fibers.length() {
        self.finish_async_task(task)
        return async_failure("async task Fiber is no longer available")
      }
      let fiber = context.fibers[fiber_identifier]
      if fiber.state == 2 {
        let root = match self.retain(value) {
          VmHandleFailed(issue) => {
            self.finish_async_task(task)
            return VmAsyncFailed([issue], output)
          }
          VmHandleCreated(root) => root
        }
        task.sequence = task.sequence + 1
        task.waiting = true
        task.request_root = Some(root)
        VmAsyncYielded(
          {
            vm_identity: self.identity,
            generation: self.generation,
            task_handle: task.fiber.identifier,
            sequence: task.sequence,
            value,
          },
          output,
        )
      } else {
        self.finish_async_task(task)
        VmAsyncCompleted(value, output)
      }
    }
  }
}

///|
/// Start a task. `initial` is delivered as the optional first Fiber argument.
pub fn Vm::start_async(
  self : Vm,
  task : VmAsyncTask,
  initial : Value?,
) -> VmAsyncRunResult {
  match self.validate_async_task(task) {
    Some(message) => return async_failure(message)
    None => ()
  }
  if task.started {
    return async_failure("async task has already started")
  }
  task.started = true
  self.drive_async_task(task, initial)
}

///|
/// Resume a suspended task with the result of its yielded host request.
pub fn Vm::resume_async(
  self : Vm,
  task : VmAsyncTask,
  request : VmAsyncRequest,
  response : Value,
) -> VmAsyncRunResult {
  match self.validate_async_task(task) {
    Some(message) => return async_failure(message)
    None => ()
  }
  if !task.started || !task.waiting {
    return async_failure("async task is not waiting for a host response")
  }
  if request.vm_identity != self.identity ||
    request.generation != self.generation ||
    request.task_handle != task.fiber.identifier ||
    request.sequence != task.sequence {
    return async_failure("async request is stale or belongs to another task")
  }
  match task.request_root {
    Some(root) => ignore(self.release(root))
    None => ()
  }
  task.request_root = None
  task.waiting = false
  self.drive_async_task(task, Some(response))
}

///|
/// Cancel a task and release all VM roots owned by it.
pub fn Vm::cancel_async(self : Vm, task : VmAsyncTask) -> Bool {
  if task.vm_identity != self.identity ||
    task.generation != self.generation ||
    task.finished ||
    task.cancelled {
    return false
  }
  match task.request_root {
    Some(root) => ignore(self.release(root))
    None => ()
  }
  task.request_root = None
  ignore(self.release(task.fiber))
  task.waiting = false
  task.cancelled = true
  true
}
