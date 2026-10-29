///|
fn assert_compiled_number(source : String, expected : Double) -> Unit raise {
  match @moonwren.run_compiled(source, 10000) {
    @moonwren.BytecodeCompleted(value, steps) => {
      assert_eq(value, @moonwren.Value::number(expected))
      assert_true(steps > 0)
    }
    @moonwren.BytecodeFailed(issue, _) => fail(issue.message)
  }
}

///|
test "bytecode executes variables, assignments, and loops" {
  assert_compiled_number(
    "var total = 0\n" +
    "var n = 1\n" +
    "while (n <= 6) { total = total + n\n n = n + 1 }\n" +
    "total\n",
    21.0,
  )
}

///|
test "bytecode preserves logical short-circuit behavior" {
  assert_compiled_number("false && missing\n true ? 7 : missing\n", 7.0)
}

///|
test "bytecode agrees with the tree-walking interpreter" {
  let source = "var x = 3\n if (x > 2) x = x * 4 else x = 0\n x\n"
  let interpreted = match @moonwren.run(source) {
    @moonwren.ProgramCompleted(value, _) => value
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match @moonwren.run_compiled(source, 10000) {
    @moonwren.BytecodeCompleted(value, _) => assert_eq(value, interpreted)
    @moonwren.BytecodeFailed(issue, _) => fail(issue.message)
  }
}

///|
test "bytecode enforces a deterministic instruction budget" {
  match @moonwren.run_compiled("while (true) {}\n", 30) {
    @moonwren.BytecodeCompleted(_, _) => fail("infinite loop should stop")
    @moonwren.BytecodeFailed(issue, steps) => {
      assert_eq(issue.code, @moonwren.ExecutionLimit)
      assert_true(steps > 30)
    }
  }
}

///|
test "hybrid bytecode executes classes, closures, loops, and fibers" {
  assert_compiled_number(
    "class Example {\n static answer { return 40 }\n}\n" +
    "var offset = 2\n" +
    "var add = Fn.new { |value| value + offset }\n" +
    "add.call(Example.answer)\n",
    42.0,
  )
  assert_compiled_number(
    "var total = 0\n" +
    "for (number in 1..10) { if (number == 4) break\n total = total + number }\n" +
    "total\n",
    6.0,
  )
  assert_compiled_number(
    "var fiber = Fiber.new {\n Fiber.yield(20)\n return 42\n}\n" +
    "fiber.call()\n" +
    "fiber.call()\n",
    42.0,
  )
  let program = match @moonwren.compile_bytecode("class Example {}\n") {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => fail(issues[0].message)
  }
  assert_true(@moonwren.profile_bytecode(program, 100).semantic_fallbacks > 0)
}

///|
test "hybrid bytecode executes imported modules with a host loader" {
  let program = match
    @moonwren.compile_module_bytecode(
      "main", "import \"dep\" for answer\nanswer + 2\n",
    ) {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => fail(issues[0].message)
  }
  let loader = fn(_from, name) {
    if name == "dep" {
      @moonwren.ModuleLoaded("dep", "var answer = 40\n")
    } else {
      @moonwren.ModuleLoadFailed("missing module")
    }
  }
  match @moonwren.run_bytecode_with_loader(program, 1000, loader) {
    @moonwren.BytecodeCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    @moonwren.BytecodeFailed(issue, _) => fail(issue.message)
  }
}

///|
test "bytecode profiler and disassembler expose execution details" {
  let program = match @moonwren.compile_bytecode("var x = 2\n x * 5\n") {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => fail(issues[0].message)
  }
  let profile = @moonwren.profile_bytecode(program, 100)
  assert_true(profile.executed_instructions > 0)
  assert_true(profile.max_stack_depth > 0)
  assert_true(profile.loads > 0)
  assert_true(profile.stores > 0)
  assert_true(profile.arithmetic_operations > 0)
  assert_eq(profile.calls, 0)
  let listing = @moonwren.disassemble_bytecode(program)
  assert_eq(listing.length(), program.instructions.length())
  assert_true(listing[0].contains("PushConstant"))
  let trace = @moonwren.trace_bytecode(program, 100)
  assert_eq(trace.events.length(), profile.executed_instructions)
  assert_eq(trace.events[0].instruction_pointer, 0)
  assert_eq(trace.events[0].step, 1)
}

///|
test "bytecode executes collection literals, subscripts, and core methods" {
  assert_compiled_number(
    "var values = [1, 2]\n" +
    "values.add(3)\n" +
    "values[0] = 5\n" +
    "values[0] + values.count\n",
    8.0,
  )
  assert_compiled_number(
    "var values = {\"left\": 2}\n" +
    "values[\"right\"] = 4\n" +
    "values[\"left\"] + values[\"right\"]\n",
    6.0,
  )
  let program = match @moonwren.compile_bytecode("[1, 2].count\n") {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => fail(issues[0].message)
  }
  assert_true(@moonwren.profile_bytecode(program, 100).calls > 0)
}

///|
test "bytecode trace debugger steps and stops on source breakpoints" {
  let program = match
    @moonwren.compile_bytecode("var x = 1\nx = x + 2\nx * 4\n") {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => fail(issues[0].message)
  }
  let trace = @moonwren.trace_bytecode(program, 100)
  let debugger = @moonwren.BytecodeTraceDebugger::new(trace, [2])
  match debugger.step() {
    @moonwren.DebuggerFinished(_) => fail("first instruction should be visible")
    @moonwren.DebuggerPaused(event) => assert_eq(event.step, 1)
  }
  match debugger.continue_execution() {
    @moonwren.DebuggerFinished(_) => fail("line two breakpoint should be hit")
    @moonwren.DebuggerPaused(event) =>
      assert_eq(event.instruction.span.line(), 2)
  }
  debugger.reset()
  assert_eq(debugger.position(), 0)
  assert_true(debugger.event_count() > 0)
}
