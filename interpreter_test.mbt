///|
fn expect_program_value(
  source : String,
  expected : @moonwren.Value,
) -> Unit raise {
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(value, _) => assert_eq(value, expected)
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "program execution supports variables and assignment" {
  expect_program_value(
    "var answer = 20\nanswer = answer + 22\nanswer\n",
    @moonwren.Value::number(42.0),
  )
}

///|
test "block variables shadow outer bindings" {
  expect_program_value(
    "var value = 1\n{\n  var value = 2\n  value = value + 1\n}\nvalue\n",
    @moonwren.Value::number(1.0),
  )
}

///|
test "conditional execution chooses one branch" {
  expect_program_value(
    "var value = 0\nif (2 > 1) {\n  value = 7\n} else {\n  value = 9\n}\nvalue\n",
    @moonwren.Value::number(7.0),
  )
}

///|
test "while execution updates variables" {
  expect_program_value(
    "var count = 0\nwhile (count < 5) {\n  count = count + 1\n}\ncount\n",
    @moonwren.Value::number(5.0),
  )
}

///|
test "duplicate variables fail in the same scope" {
  match @moonwren.run("var item = 1\nvar item = 2\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.DuplicateVariable)
  }
}

///|
test "execution limit stops unbounded loops" {
  match @moonwren.run_with_limit("while (true) {\n  1\n}\n", 10) {
    @moonwren.ProgramCompleted(_, _) => fail("program should stop")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
}

///|
test "System.print captures values and returns its argument" {
  match @moonwren.run("var result = System.print(40 + 2)\nresult\n") {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["42"])
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "System.print supports its zero argument overload" {
  match @moonwren.run("System.print()\n") {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::null())
      assert_eq(output, [""])
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "System.print reports unsupported arity" {
  match @moonwren.run("System.print(1, 2)\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidArity)
  }
}

///|
test "unknown methods produce structured diagnostics" {
  match @moonwren.run("1.missing()\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}
