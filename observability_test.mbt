///|
test "observed VM records runtime metrics and notifies subscribers" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let observed = @moonwren.ObservedVm::new(vm, 8)
  let notifications : Array[@moonwren.VmTelemetry] = []
  observed.subscribe(fn(item) { notifications.push(item) })
  let source =
    #|import "moon/json" for Json
    #|var double = Fn.new { |value| value * 2 }
    #|System.print(Json.parse("{\"answer\":42}")["answer"])
    #|double.call(21)
  match observed.interpret("main", source) {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["42"])
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let telemetry = observed.history()[0]
  assert_true(telemetry.succeeded)
  assert_true(telemetry.steps > 0)
  assert_true(telemetry.duration_milliseconds >= 0.0)
  assert_true(telemetry.loaded_modules >= 2)
  assert_true(telemetry.allocated_objects > 0)
  assert_true(telemetry.live_fibers > 0)
  assert_eq(telemetry.foreign_calls, 1)
  assert_true(telemetry.peak_call_depth > 0)
  assert_eq(notifications.length(), 1)
  observed.close()
}

///|
test "telemetry history is bounded and exports Prometheus and Chrome trace" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(1000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let observed = @moonwren.ObservedVm::new(vm, 2)
  ignore(observed.interpret("one", "1\n"))
  ignore(observed.interpret("two", "missing\n"))
  ignore(observed.read("one", "missing"))
  let history = observed.history()
  assert_eq(history.length(), 2)
  assert_true(!history[0].succeeded)
  assert_true(!history[1].succeeded)
  let metrics = @moonwren.telemetry_prometheus(history, "moon-wren")
  assert_true(metrics.contains("moon_wren_operations_total"))
  assert_true(metrics.contains("result=\"failure\"} 2"))
  let trace = @moonwren.telemetry_chrome_trace(history)
  assert_true(trace.contains("\"traceEvents\""))
  assert_true(trace.contains("\"name\":\"read\""))
  observed.close()
}
