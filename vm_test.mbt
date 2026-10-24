///|
fn no_vm_modules(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn standard_vm() -> @moonwren.Vm {
  @moonwren.Vm::new(@moonwren.VmLimits::standard(100000), no_vm_modules, [], [])
}

///|
fn expect_vm_number(
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
test "persistent VM retains closure state across host calls" {
  let vm = standard_vm()
  let source = "var count = 0\n" + "var next = Fn.new { count = count + 1 }\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let next = match vm.capture("main", "next") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  expect_vm_number(vm.call(next, []), 1.0)
  expect_vm_number(vm.call(next, []), 2.0)
  expect_vm_number(vm.read("main", "count"), 2.0)
  vm.close()
}

///|
test "persistent VM calls instance methods through a strong handle" {
  let vm = standard_vm()
  let source = "class Counter {\n" +
    "  construct new(value) { _value = value }\n" +
    "  add(amount) {\n" +
    "    _value = _value + amount\n" +
    "    return _value\n" +
    "  }\n" +
    "  value { return _value }\n" +
    "}\n" +
    "var counter = Counter.new(40)\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let counter = match vm.capture("main", "counter") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  expect_vm_number(
    vm.call_method(counter, "add", [@moonwren.Value::number(2.0)]),
    42.0,
  )
  expect_vm_number(vm.get(counter, "value"), 42.0)
  vm.close()
}

///|
test "successful reload migrates primitives and invalidates old handles" {
  let vm = standard_vm()
  let original = "var count = 40\nvar get = Fn.new { count }\n"
  match vm.interpret("main", original) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let old_get = match vm.capture("main", "get") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let replacement = "var count = 0\nvar get = Fn.new { count + 2 }\n"
  match vm.reload_module("main", replacement, ["count"]) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.call(old_get, []) {
    @moonwren.ProgramCompleted(_, _) => fail("old handle should be invalid")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  let new_get = match vm.capture("main", "get") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  expect_vm_number(vm.call(new_get, []), 42.0)
  vm.close()
}

///|
test "failed reload leaves the current runtime and handles untouched" {
  let vm = standard_vm()
  let source = "var get = Fn.new { 42 }\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let get = match vm.capture("main", "get") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.reload_module("main", "var broken =\n", []) {
    @moonwren.ProgramCompleted(_, _) => fail("reload should fail")
    @moonwren.ProgramFailed(_, _) => ()
  }
  expect_vm_number(vm.call(get, []), 42.0)
  vm.close()
}

///|
test "reloading an imported module rebuilds dependent roots" {
  let loader = fn(_importer : String, name : String) {
    if name == "lib" {
      @moonwren.ModuleLoaded("lib", "var answer = 40\n")
    } else {
      @moonwren.ModuleLoadFailed("missing module")
    }
  }
  let vm = @moonwren.Vm::new(@moonwren.VmLimits::standard(100000), loader, [], [])
  let main = "import \"lib\" for answer\nvar read = Fn.new { answer }\n"
  match vm.interpret("main", main) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let old_read = match vm.capture("main", "read") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  expect_vm_number(vm.call(old_read, []), 40.0)
  match vm.reload_module("lib", "var answer = 42\n", []) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let read = match vm.capture("main", "read") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  expect_vm_number(vm.call(read, []), 42.0)
  vm.close()
}

///|
test "persistent VM enforces output and source limits" {
  let limits = @moonwren.VmLimits::new(1000, 64, 3, 10, 1000, 20)
  let output_vm = @moonwren.Vm::new(limits, no_vm_modules, [], [])
  match output_vm.interpret("main", "System.print(\"four\")\n") {
    @moonwren.ProgramCompleted(_, _) => fail("output should be limited")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  output_vm.close()
  let source_vm = @moonwren.Vm::new(limits, no_vm_modules, [], [])
  match source_vm.interpret("main", "var value = 12345678901234567890\n") {
    @moonwren.ProgramCompleted(_, _) => fail("source should be limited")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  source_vm.close()
}

///|
test "persistent VM enforces module count limits" {
  let loader = fn(_importer : String, name : String) {
    if name == "lib" {
      @moonwren.ModuleLoaded("lib", "var answer = 42\n")
    } else {
      @moonwren.ModuleLoadFailed("missing module")
    }
  }
  let limits = @moonwren.VmLimits::new(1000, 64, 1000, 1, 1000, 1000)
  let vm = @moonwren.Vm::new(limits, loader, [], [])
  match vm.interpret("main", "import \"lib\" for answer\nanswer\n") {
    @moonwren.ProgramCompleted(_, _) => fail("module count should be limited")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  vm.close()
}

///|
test "persistent VM enforces the runtime object limit after allocation" {
  let limits = @moonwren.VmLimits::new(1000, 64, 1000, 10, 1, 1000)
  let vm = @moonwren.Vm::new(limits, no_vm_modules, [], [])
  match vm.interpret("main", "var values = []\n") {
    @moonwren.ProgramCompleted(_, _) => fail("object count should be limited")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  vm.close()
}

///|
test "host cancellation stops a VM operation" {
  let cancelled = [true]
  let vm = @moonwren.Vm::new_cancellable(
    @moonwren.VmLimits::standard(100000),
    no_vm_modules,
    [],
    [],
    fn() { cancelled[0] },
  )
  match vm.interpret("main", "var answer = 42\n") {
    @moonwren.ProgramCompleted(_, _) => fail("operation should be cancelled")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  vm.close()
}

///|
test "reachability collection finalizes unreachable foreign instances" {
  let finalized : Array[Int] = []
  let binding = @moonwren.ForeignClassBinding::new(
    "main",
    "Box",
    fn(_) { @moonwren.ForeignAllocationSucceeded(7) },
    fn(handle) { finalized.push(handle) },
  )
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    no_vm_modules,
    [],
    [binding],
  )
  let source = "foreign class Box { construct new() {} }\n" +
    "Fn.new { Box.new() }.call()\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let stats = vm.collect_garbage()
  assert_eq(stats.before_instances, 1)
  assert_eq(stats.reachable_instances, 0)
  assert_eq(stats.reclaimed_instances, 1)
  assert_eq(stats.finalized_foreign_instances, 1)
  assert_eq(finalized, [7])
  vm.close()
  assert_eq(finalized, [7])
}

///|
test "retained host values remain reachable until their handle is released" {
  let finalized : Array[Int] = []
  let binding = @moonwren.ForeignClassBinding::new(
    "main",
    "Box",
    fn(_) { @moonwren.ForeignAllocationSucceeded(9) },
    fn(handle) { finalized.push(handle) },
  )
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    no_vm_modules,
    [],
    [binding],
  )
  let source = "foreign class Box { construct new() {} }\n" +
    "var make = Fn.new { Box.new() }\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let make = match vm.capture("main", "make") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let instance = match vm.call(make, []) {
    @moonwren.ProgramCompleted(value, _) => value
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let retained = match vm.retain(instance) {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let retained_stats = vm.collect_garbage()
  assert_eq(retained_stats.reachable_instances, 1)
  assert_eq(retained_stats.reclaimed_instances, 0)
  assert_eq(finalized, [])
  assert_true(vm.release(retained))
  let released = vm.collect_garbage()
  assert_eq(released.reclaimed_instances, 1)
  assert_eq(released.finalized_foreign_instances, 1)
  assert_eq(finalized, [9])
  let replacement_instance = match vm.call(make, []) {
    @moonwren.ProgramCompleted(value, _) => value
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let replacement_handle = match vm.retain(replacement_instance) {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  assert_true(vm.release(replacement_handle))
  let reused = vm.collect_garbage()
  assert_eq(reused.before_instances, 1)
  assert_eq(reused.reclaimed_instances, 1)
  assert_eq(finalized, [9, 9])
  vm.close()
}

///|
test "VM handles cannot cross runtimes and closed VMs fail safely" {
  let first = standard_vm()
  let second = standard_vm()
  match first.interpret("main", "var value = Fn.new { 42 }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match second.interpret("main", "var value = Fn.new { 7 }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let first_value = match first.capture("main", "value") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match second.call(first_value, []) {
    @moonwren.ProgramCompleted(_, _) => fail("cross-VM handle should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  first.close()
  match first.call(first_value, []) {
    @moonwren.ProgramCompleted(_, _) => fail("closed VM call should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  let closed_stats = first.collect_garbage()
  assert_eq(closed_stats.before_instances, 0)
  second.close()
  let replacement = standard_vm()
  match replacement.interpret("main", "var value = Fn.new { 9 }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match replacement.call(first_value, []) {
    @moonwren.ProgramCompleted(_, _) =>
      fail("reused slot should reject old handle")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
  replacement.close()
}
