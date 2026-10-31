///|
fn resilience_no_modules(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn resilience_expect_number(
  result : @moonwren.ProgramRunResult,
  expected : Double,
) -> Unit raise {
  match result {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(expected))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "persistent VM remains correct through repeated allocation and collection" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    resilience_no_modules,
    [],
    [],
  )
  assert_true(vm.configure_automatic_gc(@moonwren.VmGcPolicy::new(32, 25)))
  let source =
    #|var count = 0
    #|var process = Fn.new { |input|
    #|  count = count + 1
    #|  var temporary = [input, count, {"copy": input}]
    #|  return temporary[0] + temporary[1]
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let process = match vm.capture("main", "process") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  for index = 0; index < 1000; index = index + 1 {
    resilience_expect_number(
      vm.call(process, [@moonwren.Value::number(index.to_double())]),
      (index * 2 + 1).to_double(),
    )
    if index % 50 == 49 {
      let stats = vm.collect_garbage()
      assert_true(stats.reclaimed_objects > 0)
      assert_true(stats.reachable_objects < 32)
    }
  }
  resilience_expect_number(vm.read("main", "count"), 1000.0)
  assert_true(vm.release(process))
  ignore(vm.collect_garbage())
  vm.close()
}

///|
test "execution limit failure does not poison the next persistent VM call" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::new(300, 64, 1000, 8, 1000, 10000),
    resilience_no_modules,
    [],
    [],
  )
  let source =
    #|var spin = Fn.new { |remaining|
    #|  while (remaining > 0) remaining = remaining - 1
    #|}
    #|var healthy = Fn.new { 42 }
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let spin = match vm.capture("main", "spin") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let healthy = match vm.capture("main", "healthy") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.call(spin, [@moonwren.Value::number(10000.0)]) {
    @moonwren.ProgramCompleted(_, _) => fail("loop must exceed the step limit")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  resilience_expect_number(vm.call(healthy, []), 42.0)
  vm.close()
}

///|
test "suspended Fiber survives GC and invokes host callbacks exactly once" {
  let audits : Array[String] = []
  let audit = @moonwren.ForeignMethodBinding::new(
    "main",
    "Host",
    true,
    "audit(_)",
    fn(_, arguments) {
      match arguments[0] {
        @moonwren.StringValue(value) => {
          audits.push(value)
          @moonwren.ForeignCallSucceeded(@moonwren.Value::null())
        }
        _ => @moonwren.ForeignCallFailed("audit expects a string")
      }
    },
  )
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    resilience_no_modules,
    [audit],
    [],
  )
  let source =
    #|class Host { foreign static audit(value) }
    #|var worker = Fiber.new {
    #|  Host.audit("before")
    #|  var response = Fiber.yield("request")
    #|  Host.audit(response)
    #|  return 42
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(value) => value
    @moonwren.VmAsyncTaskCreateFailed(issue) => fail(issue.message)
  }
  let request = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(request, _) => request
    _ => fail("worker must yield")
  }
  assert_eq(audits, ["before"])
  ignore(vm.collect_garbage())
  match vm.resume_async(task, request, @moonwren.Value::string("after")) {
    @moonwren.VmAsyncCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("worker must complete")
  }
  assert_eq(audits, ["before", "after"])
  ignore(vm.collect_garbage())
  assert_eq(audits, ["before", "after"])
  vm.close()
}

///|
test "failed hot reload leaves a suspended Fiber resumable" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    resilience_no_modules,
    [],
    [],
  )
  let source =
    #|var version = 1
    #|var worker = Fiber.new {
    #|  var value = Fiber.yield("waiting")
    #|  return value + version
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(value) => value
    @moonwren.VmAsyncTaskCreateFailed(issue) => fail(issue.message)
  }
  let request = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(value, _) => value
    _ => fail("worker must yield")
  }
  match vm.reload_module("main", "var broken =\n", ["version"]) {
    @moonwren.ProgramCompleted(_, _) => fail("reload must fail")
    @moonwren.ProgramFailed(_, _) => ()
  }
  ignore(vm.collect_garbage())
  match vm.resume_async(task, request, @moonwren.Value::number(41.0)) {
    @moonwren.VmAsyncCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("task must remain resumable after rollback")
  }
  vm.close()
}

///|
test "successful hot reload invalidates a suspended task explicitly" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    resilience_no_modules,
    [],
    [],
  )
  let original =
    #|var version = 1
    #|var worker = Fiber.new { Fiber.yield("waiting") }
  match vm.interpret("main", original) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(value) => value
    @moonwren.VmAsyncTaskCreateFailed(issue) => fail(issue.message)
  }
  let request = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(value, _) => value
    _ => fail("worker must yield")
  }
  let replacement =
    #|var version = 2
    #|var worker = Fiber.new { 42 }
  match vm.reload_module("main", replacement, ["version"]) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.resume_async(task, request, @moonwren.Value::null()) {
    @moonwren.VmAsyncFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidFiberState)
    _ => fail("pre-reload task must be rejected")
  }
  resilience_expect_number(vm.read("main", "version"), 1.0)
  vm.close()
}

///|
test "foreign callback failure is isolated to one host operation" {
  let calls = [0]
  let binding = @moonwren.ForeignMethodBinding::new(
    "main",
    "Host",
    true,
    "sometimes(_)",
    fn(_, arguments) {
      calls[0] = calls[0] + 1
      if arguments[0] == @moonwren.Value::string("fail") {
        @moonwren.ForeignCallFailed("injected host failure")
      } else {
        @moonwren.ForeignCallSucceeded(arguments[0])
      }
    },
  )
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    resilience_no_modules,
    [binding],
    [],
  )
  let source =
    #|class Host { foreign static sometimes(value) }
    #|var invoke = Fn.new { |value| Host.sometimes(value) }
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let invoke = match vm.capture("main", "invoke") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.call(invoke, [@moonwren.Value::string("fail")]) {
    @moonwren.ProgramCompleted(_, _) => fail("callback must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ForeignCallFailed)
  }
  match vm.call(invoke, [@moonwren.Value::string("healthy")]) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::string("healthy"))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  assert_eq(calls[0], 2)
  vm.close()
}
