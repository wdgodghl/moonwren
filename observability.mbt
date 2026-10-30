///|
pub(all) struct VmTelemetry {
  operation_id : Int32
  operation : String
  source_name : String
  succeeded : Bool
  diagnostic_count : Int32
  steps : Int32
  duration_milliseconds : Double
  output_lines : Int32
  output_characters : Int32
  loaded_modules : Int32
  allocated_objects : Int32
  live_fibers : Int32
  foreign_calls : Int32
  peak_call_depth : Int32
  last_gc_reclaimed_objects : Int32
}

///|
pub struct ObservedVm {
  vm : Vm
  history_limit : Int32
  history : Array[VmTelemetry]
  observers : Array[(VmTelemetry) -> Unit]
  mut next_operation_id : Int32
}

///|
pub fn ObservedVm::new(vm : Vm, history_limit : Int32) -> ObservedVm {
  {
    vm,
    history_limit: if history_limit > 0 {
      history_limit
    } else {
      1
    },
    history: [],
    observers: [],
    next_operation_id: 1,
  }
}

///|
pub fn ObservedVm::subscribe(
  self : ObservedVm,
  observer : (VmTelemetry) -> Unit,
) -> Unit {
  self.observers.push(observer)
}

///|
fn ObservedVm::record(
  self : ObservedVm,
  operation : String,
  source_name : String,
  started : @bench.Timestamp,
  result : ProgramRunResult,
) -> ProgramRunResult {
  let context = self.vm.runtime()
  let (succeeded, diagnostic_count, output_lines) = match result {
    ProgramCompleted(_, output) => (true, 0, output.length())
    ProgramFailed(issues, output) => (false, issues.length(), output.length())
  }
  let last_gc_reclaimed_objects = match self.vm.last_gc_stats {
    Some(stats) => stats.reclaimed_objects
    None => 0
  }
  let telemetry : VmTelemetry = {
    operation_id: self.next_operation_id,
    operation,
    source_name,
    succeeded,
    diagnostic_count,
    steps: context.steps,
    duration_milliseconds: @bench.monotonic_clock_end(started) / 1000000.0,
    output_lines,
    output_characters: context.output_characters,
    loaded_modules: context.modules.length(),
    allocated_objects: context.allocated_objects(),
    live_fibers: context.fibers.length() - context.free_fibers.length(),
    foreign_calls: context.foreign_calls,
    peak_call_depth: context.peak_call_depth,
    last_gc_reclaimed_objects,
  }
  self.next_operation_id = self.next_operation_id + 1
  self.history.push(telemetry)
  while self.history.length() > self.history_limit {
    ignore(self.history.remove(0))
  }
  for observer in self.observers {
    observer(telemetry)
  }
  result
}

///|
pub fn ObservedVm::interpret(
  self : ObservedVm,
  source_name : String,
  source : String,
) -> ProgramRunResult {
  let started = @bench.monotonic_clock_start()
  let result = self.vm.interpret(source_name, source)
  self.record("interpret", source_name, started, result)
}

///|
pub fn ObservedVm::read(
  self : ObservedVm,
  module_name : String,
  variable : String,
) -> ProgramRunResult {
  let started = @bench.monotonic_clock_start()
  let result = self.vm.read(module_name, variable)
  self.record("read", module_name, started, result)
}

///|
pub fn ObservedVm::call(
  self : ObservedVm,
  handle : VmHandle,
  arguments : Array[Value],
) -> ProgramRunResult {
  let started = @bench.monotonic_clock_start()
  let result = self.vm.call(handle, arguments)
  self.record("call", "<host>", started, result)
}

///|
pub fn ObservedVm::reload_modules(
  self : ObservedVm,
  replacements : Array[ModuleSource],
  preserve : Array[ReloadStateSelection],
) -> ProgramRunResult {
  let started = @bench.monotonic_clock_start()
  let result = self.vm.reload_modules(replacements, preserve)
  self.record("reload", "<reload>", started, result)
}

///|
pub fn ObservedVm::capture(
  self : ObservedVm,
  module_name : String,
  variable : String,
) -> VmHandleResult {
  self.vm.capture(module_name, variable)
}

///|
pub fn ObservedVm::release(self : ObservedVm, handle : VmHandle) -> Bool {
  self.vm.release(handle)
}

///|
pub fn ObservedVm::history(self : ObservedVm) -> Array[VmTelemetry] {
  self.history.copy()
}

///|
pub fn ObservedVm::underlying(self : ObservedVm) -> Vm {
  self.vm
}

///|
pub fn ObservedVm::close(self : ObservedVm) -> Unit {
  self.vm.close()
}

///|
/// Export aggregate counters in Prometheus text exposition format. The prefix
/// is normalized to letters, digits, underscores, and colons.
pub fn telemetry_prometheus(
  history : Array[VmTelemetry],
  prefix : String,
) -> String {
  let normalized : Array[Char] = []
  for character in prefix {
    let code = character.to_int()
    if (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95 ||
      code == 58 {
      normalized.push(character)
    } else {
      normalized.push('_')
    }
  }
  let name = if normalized.is_empty() {
    "moonwren"
  } else {
    String::from_array(normalized)
  }
  let mut successes = 0
  let mut failures = 0
  let mut steps = 0
  let mut foreign_calls = 0
  let mut duration = 0.0
  for item in history {
    if item.succeeded {
      successes = successes + 1
    } else {
      failures = failures + 1
    }
    steps = steps + item.steps
    foreign_calls = foreign_calls + item.foreign_calls
    duration = duration + item.duration_milliseconds
  }
  "# TYPE " +
  name +
  "_operations_total counter\n" +
  name +
  "_operations_total{result=\"success\"} " +
  successes.to_string() +
  "\n" +
  name +
  "_operations_total{result=\"failure\"} " +
  failures.to_string() +
  "\n" +
  "# TYPE " +
  name +
  "_steps_total counter\n" +
  name +
  "_steps_total " +
  steps.to_string() +
  "\n" +
  "# TYPE " +
  name +
  "_foreign_calls_total counter\n" +
  name +
  "_foreign_calls_total " +
  foreign_calls.to_string() +
  "\n" +
  "# TYPE " +
  name +
  "_duration_milliseconds_total counter\n" +
  name +
  "_duration_milliseconds_total " +
  duration.to_string() +
  "\n"
}

///|
fn telemetry_json_escape(text : String) -> String {
  text
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\r", new="\\r")
}

///|
/// Export complete-duration events accepted by Chrome, Perfetto, and other
/// trace-event viewers.
pub fn telemetry_chrome_trace(history : Array[VmTelemetry]) -> String {
  let events : Array[String] = []
  let mut timestamp_microseconds = 0.0
  for item in history {
    let duration_microseconds = item.duration_milliseconds * 1000.0
    let status = if item.succeeded { "success" } else { "failure" }
    events.push(
      "{\"name\":\"" +
      telemetry_json_escape(item.operation) +
      "\",\"cat\":\"moonwren.vm\",\"ph\":\"X\",\"ts\":" +
      timestamp_microseconds.to_string() +
      ",\"dur\":" +
      duration_microseconds.to_string() +
      ",\"pid\":1,\"tid\":1,\"args\":{\"source\":\"" +
      telemetry_json_escape(item.source_name) +
      "\",\"result\":\"" +
      status +
      "\",\"steps\":" +
      item.steps.to_string() +
      ",\"objects\":" +
      item.allocated_objects.to_string() +
      "}}",
    )
    timestamp_microseconds = timestamp_microseconds + duration_microseconds
  }
  "{\"traceEvents\":[" + events.join(",") + "]}"
}
