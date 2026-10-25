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
test "bytecode reports unsupported object syntax explicitly" {
  match @moonwren.compile_bytecode("class Example {}\n") {
    @moonwren.BytecodeCompiled(_) => fail("class should not compile yet")
    @moonwren.BytecodeCompileFailed(issues) =>
      assert_eq(issues[0].code, @moonwren.UnsupportedFeature)
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
  let listing = @moonwren.disassemble_bytecode(program)
  assert_eq(listing.length(), program.instructions.length())
  assert_true(listing[0].contains("PushConstant"))
  let trace = @moonwren.trace_bytecode(program, 100)
  assert_eq(trace.events.length(), profile.executed_instructions)
  assert_eq(trace.events[0].instruction_pointer, 0)
  assert_eq(trace.events[0].step, 1)
}
