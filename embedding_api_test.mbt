///|
test "host collection API reads and mutates retained lists and maps" {
  let vm = standard_vm()
  match vm.interpret("main", "var values = [1, 2]\nvar table = {\"a\": 3}\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  assert_true(vm.has_module("main"))
  assert_true(vm.has_variable("main", "values"))
  let values = match vm.capture("main", "values") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.list_add(values, @moonwren.Value::number(3.0)) {
    @moonwren.VmHostSucceeded(_) => ()
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.list_set(values, -1, @moonwren.Value::number(4.0)) {
    @moonwren.VmHostSucceeded(_) => ()
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.list_snapshot(values) {
    @moonwren.VmHostSucceeded(items) =>
      assert_eq(items, [
        @moonwren.Value::number(1.0),
        @moonwren.Value::number(2.0),
        @moonwren.Value::number(4.0),
      ])
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  let table = match vm.capture("main", "table") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match
    vm.map_set(
      table,
      @moonwren.Value::string("b"),
      @moonwren.Value::number(5.0),
    ) {
    @moonwren.VmHostSucceeded(_) => ()
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.map_get(table, @moonwren.Value::string("b")) {
    @moonwren.VmHostSucceeded(value) =>
      assert_eq(value, Some(@moonwren.Value::number(5.0)))
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.map_remove(table, @moonwren.Value::string("a")) {
    @moonwren.VmHostSucceeded(value) =>
      assert_eq(value, Some(@moonwren.Value::number(3.0)))
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  vm.close()
}

///|
test "bound methods validate generations and arity" {
  let vm = standard_vm()
  match vm.interpret("main", "var add = Fn.new { |a, b| a + b }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let function = match vm.capture("main", "add") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let call = match vm.bind_method(function, "call", 2) {
    @moonwren.VmMethodHandleCreated(handle) => handle
    @moonwren.VmMethodHandleFailed(issue) => fail(issue.message)
  }
  match
    vm.call_bound(call, [
      @moonwren.Value::number(20.0),
      @moonwren.Value::number(22.0),
    ]) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.call_bound(call, []) {
    @moonwren.ProgramCompleted(_, _) => fail("arity mismatch should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidArity)
  }
  vm.close()
}

///|
test "automatic GC runs between operations and System.gc requests a pass" {
  let vm = standard_vm()
  assert_true(vm.configure_automatic_gc(@moonwren.VmGcPolicy::new(1, 50)))
  match vm.interpret("main", "Fn.new { [1, 2, 3] }.call()\nSystem.gc()\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.read("main", "System") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.last_automatic_gc() {
    Some(stats) => assert_true(stats.reclaimed_objects >= 2)
    None => fail("automatic collection should have run")
  }
  vm.close()
}

///|
test "result delivery invokes output and diagnostic callbacks" {
  let output : Array[String] = []
  let diagnostics : Array[@moonwren.DiagnosticCode] = []
  ignore(
    @moonwren.run("System.print(42)\n1.missing\n").deliver(
      line => output.push(line),
      issue => diagnostics.push(issue.code),
    ),
  )
  assert_eq(output, ["42"])
  assert_eq(diagnostics, [@moonwren.UndefinedMethod])
}

///|
test "host collection helpers reject wrong released and out-of-range values" {
  let vm = standard_vm()
  match
    vm.interpret(
      "main", "var values = [1, 2]\nvar table = {\"a\": 3}\nvar number = 42\n",
    ) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  assert_false(vm.has_module("missing"))
  assert_false(vm.has_variable("main", "missing"))
  assert_false(vm.has_variable("missing", "value"))
  let values = match vm.capture("main", "values") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let table = match vm.capture("main", "table") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let number = match vm.capture("main", "number") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let list_value = match vm.read("main", "values") {
    @moonwren.ProgramCompleted(value, _) => value
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.list_set(values, 20, @moonwren.Value::null()) {
    @moonwren.VmHostSucceeded(_) => fail("out-of-range list write must fail")
    @moonwren.VmHostFailed(issue) =>
      assert_true(issue.message.contains("out of bounds"))
  }
  match vm.list_snapshot(number) {
    @moonwren.VmHostSucceeded(_) => fail("number is not a list")
    @moonwren.VmHostFailed(issue) => assert_true(issue.message.contains("List"))
  }
  match vm.list_add(number, @moonwren.Value::null()) {
    @moonwren.VmHostSucceeded(_) => fail("number is not a list")
    @moonwren.VmHostFailed(issue) => assert_true(issue.message.contains("List"))
  }
  match vm.map_snapshot(table) {
    @moonwren.VmHostSucceeded(entries) => assert_eq(entries.length(), 1)
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.map_get(table, @moonwren.Value::string("missing")) {
    @moonwren.VmHostSucceeded(value) => assert_eq(value, None)
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.map_remove(table, @moonwren.Value::string("missing")) {
    @moonwren.VmHostSucceeded(value) => assert_eq(value, None)
    @moonwren.VmHostFailed(issue) => fail(issue.message)
  }
  match vm.map_set(table, list_value, @moonwren.Value::null()) {
    @moonwren.VmHostSucceeded(_) => fail("mutable map key must fail")
    @moonwren.VmHostFailed(issue) =>
      assert_true(issue.message.contains("immutable"))
  }
  match vm.map_snapshot(number) {
    @moonwren.VmHostSucceeded(_) => fail("number is not a map")
    @moonwren.VmHostFailed(issue) => assert_true(issue.message.contains("Map"))
  }
  assert_true(vm.release(values))
  match vm.list_snapshot(values) {
    @moonwren.VmHostSucceeded(_) => fail("released handle must fail")
    @moonwren.VmHostFailed(issue) =>
      assert_true(issue.message.contains("invalid"))
  }
  match vm.list_set(values, 0, @moonwren.Value::null()) {
    @moonwren.VmHostSucceeded(_) => fail("released handle must fail")
    @moonwren.VmHostFailed(issue) =>
      assert_true(issue.message.contains("invalid"))
  }
  match vm.map_get(values, @moonwren.Value::string("a")) {
    @moonwren.VmHostSucceeded(_) => fail("released handle must fail")
    @moonwren.VmHostFailed(issue) =>
      assert_true(issue.message.contains("invalid"))
  }
  vm.close()
}

///|
test "bound host handles reject invalid names generations and closed VMs" {
  let vm = standard_vm()
  match vm.interpret("main", "var function = Fn.new { 42 }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let function = match vm.capture("main", "function") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.bind_method(function, "", -1) {
    @moonwren.VmMethodHandleCreated(_) => fail("invalid method must fail")
    @moonwren.VmMethodHandleFailed(issue) =>
      assert_true(issue.message.contains("non-empty"))
  }
  let bound = match vm.bind_method(function, "call", 0) {
    @moonwren.VmMethodHandleCreated(value) => value
    @moonwren.VmMethodHandleFailed(issue) => fail(issue.message)
  }
  match vm.reload_module("main", "var function = Fn.new { 43 }\n", []) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.call_bound(bound, []) {
    @moonwren.ProgramCompleted(_, _) => fail("old bound method must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("generation"))
  }
  vm.close()
  assert_false(vm.has_module("main"))
  match vm.capture("main", "function") {
    @moonwren.VmHandleCreated(_) => fail("closed capture must fail")
    @moonwren.VmHandleFailed(issue) =>
      assert_true(issue.message.contains("closed"))
  }
  match vm.bind_method(function, "call", 0) {
    @moonwren.VmMethodHandleCreated(_) => fail("closed bind must fail")
    @moonwren.VmMethodHandleFailed(issue) =>
      assert_true(issue.message.contains("closed"))
  }
}
