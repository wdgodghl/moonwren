///|
/// Observable state of one task managed by `VmScheduler`.
pub(all) enum VmScheduledTaskStatus {
  ScheduledReady
  ScheduledWaitingForHost
  ScheduledSleeping
  ScheduledJoining
  ScheduledCompleted
  ScheduledFailed
  ScheduledCancelled
} derive(Eq, Debug)

///|
pub extend VmScheduledTaskStatus with Eq::{equal, not_equal}

///|
pub extend VmScheduledTaskStatus with Debug::{to_repr}

///|
/// Result of adding a Fiber or zero-argument function to a scheduler.
pub(all) enum VmSchedulerSpawnResult {
  VmSchedulerSpawned(Int)
  VmSchedulerSpawnFailed(Diagnostic)
}

///|
/// One externally visible scheduler transition. Timer, spawn and join requests
/// are consumed internally; arbitrary yielded values are returned to the host.
pub(all) enum VmSchedulerEvent {
  VmSchedulerIdle
  VmSchedulerExternalRequest(Int, VmAsyncRequest, Array[String])
  VmSchedulerTaskCompleted(Int, Value, Array[String])
  VmSchedulerTaskFailed(Int, Array[Diagnostic], Array[String])
}

///|
pub struct ScheduledTaskEntry {
  identifier : Int
  task : VmAsyncTask
  mut status : VmScheduledTaskStatus
  mut request : VmAsyncRequest?
  mut response : Value?
  mut wake_at : Double
  mut joined : Array[Int]
  mut race : Bool
  mut result : Value
  mut result_root : VmHandle?
  mut issues : Array[Diagnostic]
  pending_output : Array[String]
}

///|
/// Deterministic cooperative task scheduler layered over the resumable Fiber
/// bridge. Time advances only when the host calls `advance`, making tests and
/// embedded event-loop integration reproducible.
pub struct VmScheduler {
  vm : Vm
  entries : Array[ScheduledTaskEntry]
  mut now_milliseconds : Double
  max_tasks : Int
  mut closed : Bool
}

///|
fn snapshot_scheduler_value(
  context : RuntimeContext,
  value : Value,
  depth : Int,
) -> ForeignOwnedValue? {
  if depth > 64 {
    return None
  }
  match value {
    NullValue => Some(ForeignNull)
    BoolValue(item) => Some(ForeignBool(item))
    NumberValue(item) => Some(ForeignNumber(item))
    StringValue(item) => Some(ForeignString(item))
    RawStringValue(bytes) => Some(ForeignBytes(bytes.copy()))
    RangeValue(from, to, inclusive) => Some(ForeignRange(from, to, inclusive))
    ListValue(identifier) => {
      if identifier < 0 ||
        identifier >= context.lists.length() ||
        !context.lists[identifier].alive {
        return None
      }
      let items : Array[ForeignOwnedValue] = []
      for item in context.lists[identifier].items {
        match snapshot_scheduler_value(context, item, depth + 1) {
          Some(snapshot) => items.push(snapshot)
          None => return None
        }
      }
      Some(ForeignList(items))
    }
    MapValue(identifier) => {
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        return None
      }
      let entries : Array[ForeignOwnedMapEntry] = []
      for entry in context.maps[identifier].entries {
        let key = match
          snapshot_scheduler_value(context, entry.key, depth + 1) {
          Some(snapshot) => snapshot
          None => return None
        }
        let item = match
          snapshot_scheduler_value(context, entry.value, depth + 1) {
          Some(snapshot) => snapshot
          None => return None
        }
        entries.push(ForeignOwnedMapEntry::new(key, item))
      }
      Some(ForeignMap(entries))
    }
    _ => None
  }
}

///|
/// Copy an external request into host-owned recursive data. This makes HTTP and
/// other structured yielded requests inspectable without exposing VM-local
/// collection identifiers. Unsupported runtime objects and excessive nesting
/// return None.
pub fn VmScheduler::snapshot_request(
  self : VmScheduler,
  request : VmAsyncRequest,
) -> ForeignOwnedValue? {
  if self.closed ||
    request.vm_identity != self.vm.identity ||
    request.generation != self.vm.generation {
    return None
  }
  snapshot_scheduler_value(self.vm.runtime(), request.value(), 0)
}

///|
fn scheduler_issue(message : String) -> Diagnostic {
  Diagnostic::new(Runtime, InvalidFiberState, message, SourceSpan::empty()).with_source(
    "<scheduler>",
  )
}

///|
fn scheduler_map_value(
  context : RuntimeContext,
  value : Value,
  key : String,
) -> Value? {
  match value {
    MapValue(identifier) =>
      if identifier < 0 ||
        identifier >= context.maps.length() ||
        !context.maps[identifier].alive {
        None
      } else {
        let entries = context.maps[identifier].entries
        match find_map_key(entries, Value::string(key)) {
          Some(index) => Some(entries[index].value)
          None => None
        }
      }
    _ => None
  }
}

///|
fn scheduler_task_ids(context : RuntimeContext, value : Value) -> Array[Int]? {
  match value {
    ListValue(identifier) =>
      if identifier < 0 ||
        identifier >= context.lists.length() ||
        !context.lists[identifier].alive {
        None
      } else {
        let identifiers : Array[Int] = []
        for item in context.lists[identifier].items {
          match item {
            NumberValue(number) => identifiers.push(number.to_int())
            _ => return None
          }
        }
        Some(identifiers)
      }
    _ => None
  }
}

///|
fn Vm::new_scheduled_task(self : Vm, value : Value) -> VmAsyncTaskResult {
  let fiber = match value {
    FiberValue(_) => value
    FunctionValue(identifier) => self.runtime().new_fiber(identifier)
    _ =>
      return VmAsyncTaskCreateFailed(
        scheduler_issue("scheduler expects a Fiber or zero-argument function"),
      )
  }
  let root = match self.retain(fiber) {
    VmHandleFailed(issue) => return VmAsyncTaskCreateFailed(issue)
    VmHandleCreated(handle) => handle
  }
  let result = self.new_async_task(root)
  ignore(self.release(root))
  result
}

///|
/// Create a scheduler with virtual time starting at zero.
pub fn Vm::new_scheduler(self : Vm, max_tasks : Int) -> VmScheduler {
  {
    vm: self,
    entries: [],
    now_milliseconds: 0.0,
    max_tasks: if max_tasks > 0 {
      max_tasks
    } else {
      1
    },
    closed: false,
  }
}

///|
fn VmScheduler::spawn_value(
  self : VmScheduler,
  value : Value,
) -> VmSchedulerSpawnResult {
  if self.closed {
    return VmSchedulerSpawnFailed(scheduler_issue("scheduler is closed"))
  }
  if self.entries.length() >= self.max_tasks {
    return VmSchedulerSpawnFailed(
      scheduler_issue("scheduler task limit exceeded"),
    )
  }
  match self.vm.new_scheduled_task(value) {
    VmAsyncTaskCreateFailed(issue) => VmSchedulerSpawnFailed(issue)
    VmAsyncTaskCreated(task) => {
      let identifier = self.entries.length()
      self.entries.push({
        identifier,
        task,
        status: ScheduledReady,
        request: None,
        response: None,
        wake_at: 0.0,
        joined: [],
        race: false,
        result: Value::null(),
        result_root: None,
        issues: [],
        pending_output: [],
      })
      VmSchedulerSpawned(identifier)
    }
  }
}

///|
/// Add a retained Fiber or zero-argument function to the scheduler.
pub fn VmScheduler::spawn(
  self : VmScheduler,
  callable : VmHandle,
) -> VmSchedulerSpawnResult {
  match self.vm.resolve_handle(callable) {
    Some(value) => self.spawn_value(value)
    None =>
      VmSchedulerSpawnFailed(
        scheduler_issue("callable handle is invalid or released"),
      )
  }
}

///|
pub fn VmScheduler::now(self : VmScheduler) -> Double {
  self.now_milliseconds
}

///|
/// Advance virtual monotonic time and make due sleepers runnable.
pub fn VmScheduler::advance(self : VmScheduler, milliseconds : Double) -> Bool {
  if self.closed || milliseconds < 0.0 {
    return false
  }
  self.now_milliseconds = self.now_milliseconds + milliseconds
  self.wake_waiters()
  true
}

///|
pub fn VmScheduler::status(
  self : VmScheduler,
  task_identifier : Int,
) -> VmScheduledTaskStatus? {
  if task_identifier < 0 || task_identifier >= self.entries.length() {
    None
  } else {
    Some(self.entries[task_identifier].status)
  }
}

///|
fn make_scheduler_entry_ready(
  entry : ScheduledTaskEntry,
  response : Value,
) -> Unit {
  entry.status = ScheduledReady
  entry.response = Some(response)
  entry.joined = []
  entry.race = false
}

///|
fn append_scheduled_output(
  entry : ScheduledTaskEntry,
  output : Array[String],
) -> Unit {
  for line in output {
    entry.pending_output.push(line)
  }
}

///|
fn take_scheduled_output(entry : ScheduledTaskEntry) -> Array[String] {
  let output = entry.pending_output.copy()
  entry.pending_output.clear()
  output
}

///|
fn VmScheduler::fail_waiter(
  self : VmScheduler,
  entry : ScheduledTaskEntry,
  message : String,
) -> Unit {
  ignore(self.vm.cancel_async(entry.task))
  entry.status = ScheduledFailed
  entry.issues = [scheduler_issue(message)]
}

///|
fn VmScheduler::wake_waiters(self : VmScheduler) -> Unit {
  let context = self.vm.runtime()
  for entry in self.entries {
    if entry.status == ScheduledSleeping &&
      entry.wake_at <= self.now_milliseconds {
      make_scheduler_entry_ready(entry, Value::null())
    } else if entry.status == ScheduledJoining {
      let values : Array[Value] = []
      let mut complete = !entry.joined.is_empty()
      let mut winner : Value? = None
      for identifier in entry.joined {
        if identifier < 0 || identifier >= self.entries.length() {
          self.fail_waiter(entry, "joined task does not exist")
          complete = false
          break
        }
        let child = self.entries[identifier]
        if child.status == ScheduledFailed || child.status == ScheduledCancelled {
          self.fail_waiter(entry, "joined task did not complete successfully")
          complete = false
          break
        }
        if child.status == ScheduledCompleted {
          values.push(child.result)
          if winner is None {
            winner = Some(child.result)
          }
        } else if !entry.race {
          complete = false
        }
      }
      if entry.status == ScheduledJoining {
        if entry.race {
          match winner {
            Some(value) => make_scheduler_entry_ready(entry, value)
            None => ()
          }
        } else if complete {
          make_scheduler_entry_ready(entry, context.new_list(values))
        }
      }
    }
  }
}

///|
fn VmScheduler::handle_internal_request(
  self : VmScheduler,
  entry : ScheduledTaskEntry,
  request : VmAsyncRequest,
) -> Bool {
  let context = self.vm.runtime()
  let kind = match scheduler_map_value(context, request.value(), "$moonwren") {
    Some(StringValue(text)) => text
    _ => return false
  }
  match kind {
    "sleep" =>
      match scheduler_map_value(context, request.value(), "milliseconds") {
        Some(NumberValue(milliseconds)) => {
          entry.status = ScheduledSleeping
          entry.wake_at = self.now_milliseconds + milliseconds
          true
        }
        _ => {
          self.fail_waiter(entry, "invalid Timer.sleep request")
          true
        }
      }
    "spawn" =>
      match scheduler_map_value(context, request.value(), "callable") {
        Some(callable) => {
          match self.spawn_value(callable) {
            VmSchedulerSpawned(identifier) =>
              make_scheduler_entry_ready(
                entry,
                Value::number(identifier.to_double()),
              )
            VmSchedulerSpawnFailed(issue) =>
              self.fail_waiter(entry, issue.message)
          }
          true
        }
        None => {
          self.fail_waiter(entry, "invalid Task.run request")
          true
        }
      }
    "join" =>
      match scheduler_map_value(context, request.value(), "task") {
        Some(NumberValue(identifier)) => {
          entry.status = ScheduledJoining
          entry.joined = [identifier.to_int()]
          entry.race = false
          true
        }
        _ => {
          self.fail_waiter(entry, "invalid Task.await request")
          true
        }
      }
    "joinAll" | "race" =>
      match scheduler_map_value(context, request.value(), "tasks") {
        Some(tasks) =>
          match scheduler_task_ids(context, tasks) {
            Some(identifiers) => {
              entry.status = ScheduledJoining
              entry.joined = identifiers
              entry.race = kind == "race"
              if identifiers.is_empty() {
                make_scheduler_entry_ready(entry, context.new_list([]))
              }
              true
            }
            None => {
              self.fail_waiter(entry, "invalid task identifier list")
              true
            }
          }
        None => {
          self.fail_waiter(entry, "task identifier list is missing")
          true
        }
      }
    _ => false
  }
}

///|
/// Run until one task completes, fails, yields a host request, or no task is
/// currently runnable. Call again after `resume` or `advance`.
pub fn VmScheduler::poll(self : VmScheduler) -> VmSchedulerEvent {
  if self.closed {
    return VmSchedulerIdle
  }
  self.wake_waiters()
  let mut transitions = 0
  while transitions <= self.max_tasks * 4 + 4 {
    self.wake_waiters()
    let mut ready : ScheduledTaskEntry? = None
    for entry in self.entries {
      if entry.status == ScheduledFailed && !entry.issues.is_empty() {
        let issues = entry.issues
        entry.issues = []
        return VmSchedulerTaskFailed(
          entry.identifier,
          issues,
          take_scheduled_output(entry),
        )
      }
      if ready is None && entry.status == ScheduledReady {
        ready = Some(entry)
      }
    }
    let entry = match ready {
      Some(value) => value
      None => return VmSchedulerIdle
    }
    let result = if !entry.task.started {
      self.vm.start_async(entry.task, None)
    } else {
      let request = match entry.request {
        Some(value) => value
        None => {
          self.fail_waiter(entry, "scheduler lost a suspended request")
          transitions = transitions + 1
          continue
        }
      }
      let response = entry.response.unwrap_or(Value::null())
      entry.request = None
      entry.response = None
      self.vm.resume_async(entry.task, request, response)
    }
    match result {
      VmAsyncYielded(request, output) => {
        append_scheduled_output(entry, output)
        entry.request = Some(request)
        if self.handle_internal_request(entry, request) {
          transitions = transitions + 1
          continue
        }
        entry.status = ScheduledWaitingForHost
        return VmSchedulerExternalRequest(
          entry.identifier,
          request,
          take_scheduled_output(entry),
        )
      }
      VmAsyncCompleted(value, output) => {
        append_scheduled_output(entry, output)
        entry.status = ScheduledCompleted
        entry.result = value
        match self.vm.retain(value) {
          VmHandleCreated(root) => entry.result_root = Some(root)
          VmHandleFailed(_) => ()
        }
        self.wake_waiters()
        return VmSchedulerTaskCompleted(
          entry.identifier,
          value,
          take_scheduled_output(entry),
        )
      }
      VmAsyncFailed(issues, output) => {
        append_scheduled_output(entry, output)
        entry.status = ScheduledFailed
        self.wake_waiters()
        return VmSchedulerTaskFailed(
          entry.identifier,
          issues,
          take_scheduled_output(entry),
        )
      }
    }
  }
  VmSchedulerIdle
}

///|
/// Supply the result of an arbitrary host request yielded by a task.
pub fn VmScheduler::deliver(
  self : VmScheduler,
  task_identifier : Int,
  response : Value,
) -> Bool {
  if self.closed ||
    task_identifier < 0 ||
    task_identifier >= self.entries.length() {
    return false
  }
  let entry = self.entries[task_identifier]
  if entry.status != ScheduledWaitingForHost || entry.request is None {
    return false
  }
  make_scheduler_entry_ready(entry, response)
  true
}

///|
pub fn VmScheduler::cancel(self : VmScheduler, task_identifier : Int) -> Bool {
  if self.closed ||
    task_identifier < 0 ||
    task_identifier >= self.entries.length() {
    return false
  }
  let entry = self.entries[task_identifier]
  if entry.status == ScheduledCompleted ||
    entry.status == ScheduledFailed ||
    entry.status == ScheduledCancelled {
    return false
  }
  if !self.vm.cancel_async(entry.task) {
    return false
  }
  entry.status = ScheduledCancelled
  true
}

///|
/// Cancel unfinished work and release all retained task results.
pub fn VmScheduler::close(self : VmScheduler) -> Unit {
  if self.closed {
    return
  }
  for entry in self.entries {
    if entry.status != ScheduledCompleted &&
      entry.status != ScheduledFailed &&
      entry.status != ScheduledCancelled {
      ignore(self.vm.cancel_async(entry.task))
    }
    match entry.result_root {
      Some(root) => ignore(self.vm.release(root))
      None => ()
    }
    entry.result_root = None
  }
  self.closed = true
}
