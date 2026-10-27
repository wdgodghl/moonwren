///|
test "live debugger stops before execution and exposes visible variables" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let stops : Array[@moonwren.DebugSnapshot] = []
  assert_true(
    vm.attach_debugger([@moonwren.DebugBreakpoint::new("main", 3)], false, fn(
      snapshot,
    ) {
      stops.push(snapshot)
      @moonwren.DebugContinue
    }),
  )
  match
    vm.interpret(
      "main", "var answer = 40\nanswer = answer + 1\nanswer = answer + 1\n",
    ) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
  assert_eq(stops.length(), 1)
  assert_eq(stops[0].source_name, "main")
  assert_eq(stops[0].span.line(), 3)
  let mut found = false
  for variable in stops[0].variables {
    if variable.name == "answer" {
      found = true
      assert_eq(variable.value, @moonwren.Value::number(41.0))
    }
  }
  assert_true(found)
}

///|
test "live debugger supports stepping and termination" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let lines : Array[Int] = []
  ignore(
    vm.attach_debugger([], true, fn(snapshot) {
      lines.push(snapshot.span.line())
      if lines.length() >= 2 {
        @moonwren.DebugTerminate
      } else {
        @moonwren.DebugStepInto
      }
    }),
  )
  match vm.interpret("main", "var first = 1\nvar second = 2\nvar third = 3\n") {
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.DebugTerminated)
    _ => abort("debugger should terminate execution")
  }
  assert_eq(lines, [1, 2])
}
