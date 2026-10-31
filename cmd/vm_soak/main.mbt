///|
fn no_modules(_importer : String, name : String) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn fail_soak(message : String) -> Unit {
  println("soak_failed: \{message}")
  @sys.exit(1)
}

///|
fn main {
  let arguments = @env.args()
  let iterations = if arguments.contains("--quick") { 500 } else { 10000 }
  let allocations = [0]
  let finalizations = [0]
  let callbacks = [0]
  let foreign_class = @moonwren.ForeignClassBinding::new(
    "main",
    "Token",
    fn(_) {
      allocations[0] = allocations[0] + 1
      @moonwren.ForeignAllocationSucceeded(allocations[0])
    },
    fn(_) { finalizations[0] = finalizations[0] + 1 },
  )
  let token_value = @moonwren.ForeignMethodBinding::new_for_foreign_class(
    "main",
    "Token",
    "value",
    fn(handle, _) {
      @moonwren.ForeignCallSucceeded(
        @moonwren.Value::number((handle - 1).to_double()),
      )
    },
  )
  let audit = @moonwren.ForeignMethodBinding::new(
    "main",
    "Host",
    true,
    "audit(_)",
    fn(_, arguments) {
      callbacks[0] = callbacks[0] + 1
      @moonwren.ForeignCallSucceeded(arguments[0])
    },
  )
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::new(100000, 64, 10000, 8, 2048, 100000),
    no_modules,
    [token_value, audit],
    [foreign_class],
  )
  if !vm.configure_automatic_gc(@moonwren.VmGcPolicy::new(64, 25)) {
    fail_soak("automatic GC policy was rejected")
  }
  let source =
    #|foreign class Token {
    #|  construct new(value) {}
    #|  foreign value
    #|}
    #|class Host { foreign static audit(value) }
    #|var total = 0
    #|var process = Fn.new { |input|
    #|  var token = Token.new(input)
    #|  var temporary = [token.value, {"input": input}, Fn.new { input }]
    #|  total = total + Host.audit(temporary[0])
    #|  return total
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail_soak(issues[0].message)
  }
  let process = match vm.capture("main", "process") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => {
      fail_soak(issue.message)
      return
    }
  }
  let mut peak_reachable = 0
  for index = 0; index < iterations; index = index + 1 {
    let expected = (index * (index + 1) / 2).to_double()
    match vm.call(process, [@moonwren.Value::number(index.to_double())]) {
      @moonwren.ProgramCompleted(value, _) =>
        if value != @moonwren.Value::number(expected) {
          fail_soak("wrong result at iteration \{index}: \{value.to_text()}")
        }
      @moonwren.ProgramFailed(issues, _) => fail_soak(issues[0].message)
    }
    if index % 25 == 24 {
      let stats = vm.collect_garbage()
      if stats.reachable_objects > peak_reachable {
        peak_reachable = stats.reachable_objects
      }
      if stats.reachable_objects > 64 {
        fail_soak(
          "reachable object count grew beyond the bound: \{stats.reachable_objects}",
        )
      }
    }
  }
  if !vm.release(process) {
    fail_soak("process handle could not be released")
  }
  let final_stats = vm.collect_garbage()
  if allocations[0] != iterations {
    fail_soak("expected \{iterations} allocations, got \{allocations[0]}")
  }
  if callbacks[0] != iterations {
    fail_soak("expected \{iterations} callbacks, got \{callbacks[0]}")
  }
  if finalizations[0] != allocations[0] {
    fail_soak(
      "foreign finalizer mismatch: \{finalizations[0]}/\{allocations[0]}",
    )
  }
  vm.close()
  if finalizations[0] != allocations[0] {
    fail_soak("VM close finalized a foreign object more than once")
  }
  println(
    "soak_passed iterations=\{iterations} callbacks=\{callbacks[0]} finalized=\{finalizations[0]} peak_reachable=\{peak_reachable} remaining=\{final_stats.reachable_objects}",
  )
}
