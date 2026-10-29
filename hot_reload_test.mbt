///|
fn hot_reload_vm() -> @moonwren.Vm {
  @moonwren.Vm::new(
    @moonwren.VmLimits::standard(200000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
}

///|
test "batch reload preserves cyclic collection state and updates dependents" {
  let vm = hot_reload_vm()
  match
    vm.interpret(
      "lib", "var state = {\"count\": 40}\nstate[\"self\"] = state\nvar answer = 1\n",
    ) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match
    vm.interpret(
      "main", "import \"lib\" for state, answer\nvar read = Fn.new { state[\"count\"] + answer }\n",
    ) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match
    vm.reload_modules(
      [
        @moonwren.ModuleSource::new("lib", "var state = {}\nvar answer = 2\n"),
        @moonwren.ModuleSource::new(
          "main", "import \"lib\" for state, answer\nvar read = Fn.new { state[\"count\"] + answer }\n",
        ),
      ],
      [@moonwren.ReloadStateSelection::new("lib", ["state"])],
    ) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let read = match vm.capture("main", "read") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match vm.call(read, []) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  ignore(vm.release(read))
  let archive = match vm.save_state("lib", ["state"]) {
    @moonwren.VmStateSaved(value) => value
    @moonwren.VmStateSaveFailed(issue) => fail(issue.message)
  }
  assert_true(archive.contains("MWS1"))
  vm.close()
}

///|
test "batch reload migration failure rolls back sources state and handles" {
  let vm = hot_reload_vm()
  match vm.interpret("main", "var value = 41\nvar read = Fn.new { value }\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let handle = match vm.capture("main", "read") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  match
    vm.reload_modules_with_migration(
      [
        @moonwren.ModuleSource::new(
          "main", "var value = 100\nvar read = Fn.new { value }\n",
        ),
      ],
      [@moonwren.ReloadStateSelection::new("main", ["value"])],
      fn(_) { Err("schema rejected") },
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("migration must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("schema rejected"))
  }
  match vm.call(handle, []) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(41.0))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  ignore(vm.release(handle))
  vm.close()
}

///|
test "batch reload rejects duplicate replacements before commit" {
  let vm = hot_reload_vm()
  match vm.interpret("main", "var value = 1\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match
    vm.reload_modules(
      [
        @moonwren.ModuleSource::new("main", "var value = 2\n"),
        @moonwren.ModuleSource::new("main", "var value = 3\n"),
      ],
      [],
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("duplicates must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("duplicate"))
  }
  match vm.read("main", "value") {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(1.0))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  vm.close()
}

///|
test "batch reload rejects cyclic replacement dependencies" {
  let vm = hot_reload_vm()
  match vm.interpret("main", "var value = 1\n") {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match
    vm.reload_modules(
      [
        @moonwren.ModuleSource::new(
          "first", "import \"second\" for value\nvar first = value\n",
        ),
        @moonwren.ModuleSource::new(
          "second", "import \"first\" for first\nvar value = first\n",
        ),
      ],
      [],
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("dependency cycle must fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("cyclic"))
  }
  vm.close()
}
