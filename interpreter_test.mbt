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

///|
test "for loops iterate inclusive ascending ranges" {
  let source = "var total = 0\nfor (item in 1..5) {\n  total = total + item\n}\ntotal\n"
  expect_program_value(source, @moonwren.Value::number(15.0))
}

///|
test "for loops iterate exclusive descending ranges" {
  let source = "var total = 0\nfor (item in 3...0) {\n  total = total + item\n}\ntotal\n"
  expect_program_value(source, @moonwren.Value::number(6.0))
}

///|
test "for loop variables remain scoped to the loop" {
  match @moonwren.run("for (item in 1..1) {\n  item\n}\nitem\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedVariable)
  }
}

///|
test "for loops reject non-range values" {
  match @moonwren.run("for (item in 3) {\n  item\n}\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}

///|
test "getter results can be passed to System.print" {
  match @moonwren.run("System.print((4..2).min)\n") {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["2"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "unknown getters produce structured diagnostics" {
  match @moonwren.run("1.missing\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}

///|
test "closures retain and update captured variables" {
  let source = "var count = 0\n" +
    "var counter = Fn.new { count = count + 1 }\n" +
    "System.print(counter.call())\n" +
    "System.print(counter.call())\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["1", "2"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "nested closures preserve function parameters" {
  let source = "var make = Fn.new { |value| Fn.new { value } }\n" +
    "var get = make.call(42)\n" +
    "get.call()\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "function variables support recursive expression bodies" {
  let source = "var sum = Fn.new { |number| number <= 0 ? 0 : number + sum.call(number - 1) }\n" +
    "sum.call(5)\n"
  expect_program_value(source, @moonwren.Value::number(15.0))
}
