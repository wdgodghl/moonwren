///|
fn expect_fiber_output(source : String, expected : Array[String]) -> Unit raise {
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, expected)
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "Fiber.new is lazy and call completes with a result" {
  let source = "var ran = false\n" +
    "var fiber = Fiber.new { ran = true\n return 42 }\n" +
    "System.print(ran)\n" +
    "System.print(fiber.isDone)\n" +
    "System.print(fiber.call())\n" +
    "System.print(ran)\n" +
    "System.print(fiber.isDone)\n"
  expect_fiber_output(source, ["false", "false", "42", "true", "true"])
}

///|
test "Fiber.yield returns values and receives resume values" {
  let source = "var fiber = Fiber.new { |first|\n" +
    "  System.print(first)\n" +
    "  var resumed = Fiber.yield(\"paused\")\n" +
    "  System.print(resumed)\n" +
    "  return resumed + \"!\"\n" +
    "}\n" +
    "System.print(fiber.call(\"start\"))\n" +
    "System.print(fiber.isDone)\n" +
    "System.print(fiber.call(\"resume\"))\n" +
    "System.print(fiber.isDone)\n"
  expect_fiber_output(source, [
    "start", "paused", "false", "resume", "resume!", "true",
  ])
}

///|
test "yield continuations support nested and repeated expressions" {
  let source = "var nested = Fiber.new { System.print(Fiber.yield(\"ready\")) }\n" +
    "System.print(nested.call())\n" +
    "nested.call(\"continued\")\n" +
    "var repeated = Fiber.new {\n" +
    "  return Fiber.yield(\"left\") + Fiber.yield(\"right\")\n" +
    "}\n" +
    "System.print(repeated.call())\n" +
    "System.print(repeated.call(20))\n" +
    "System.print(repeated.call(22))\n"
  expect_fiber_output(source, ["ready", "continued", "left", "right", "42"])
}

///|
test "Fiber.current identifies the active fiber" {
  let source = "var main = Fiber.current\n" +
    "System.print(main.type.name)\n" +
    "var fiber = Fiber.new { System.print(Object.same(Fiber.current, fiber)) }\n" +
    "fiber.call()\n" +
    "System.print(Object.same(Fiber.current, main))\n"
  expect_fiber_output(source, ["Fiber", "true", "true"])
}

///|
test "Fiber.try captures aborts and exposes error state" {
  let source = "var fiber = Fiber.new { Fiber.abort(\"boom\") }\n" +
    "System.print(fiber.try())\n" +
    "System.print(fiber.error)\n" +
    "System.print(fiber.isDone)\n"
  expect_fiber_output(source, ["boom", "boom", "true"])
}

///|
test "Fiber.suspend pauses with null and accepts a resume value" {
  let source = "var fiber = Fiber.new {\n" +
    "  var resumed = Fiber.suspend()\n" +
    "  return resumed\n" +
    "}\n" +
    "System.print(fiber.call())\n" +
    "System.print(fiber.call(42))\n"
  expect_fiber_output(source, ["null", "42"])
}

///|
test "Fiber.abort null is a no-op" {
  let source = "var fiber = Fiber.new { Fiber.abort(null)\n return 42 }\n" +
    "System.print(fiber.call())\n"
  expect_fiber_output(source, ["42"])
}

///|
test "transferError marks a target fiber as aborted" {
  let source = "var fiber = Fiber.new { 42 }\n" +
    "fiber.transferError(\"cancelled\")\n" +
    "System.print(fiber.error)\n" +
    "System.print(fiber.isDone)\n"
  expect_fiber_output(source, ["cancelled", "true"])
}

///|
test "transfer to the main fiber suspends and later resumes" {
  let source = "var main = Fiber.current\n" +
    "var fiber = Fiber.new { |initial|\n" +
    "  System.print(initial)\n" +
    "  var resumed = main.transfer(\"back\")\n" +
    "  System.print(resumed)\n" +
    "  return \"done\"\n" +
    "}\n" +
    "System.print(fiber.transfer(\"start\"))\n" +
    "System.print(fiber.transfer(\"again\"))\n"
  expect_fiber_output(source, ["start", "back", "again", "done"])
}

///|
test "fibers can call other fibers without losing active identity" {
  let source = "var inner = Fiber.new {\n" +
    "  System.print(Fiber.current.type.name)\n" +
    "  return 40\n" +
    "}\n" +
    "var outer = Fiber.new { return inner.call() + 2 }\n" +
    "System.print(outer.call())\n"
  expect_fiber_output(source, ["Fiber", "42"])
}

///|
test "Fiber.new rejects functions with more than one parameter" {
  match @moonwren.run("Fiber.new { |a, b| a + b }\n") {
    @moonwren.ProgramCompleted(_, _) => fail("two parameter fiber should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidArity)
  }
}

///|
test "completed and aborted fibers cannot be resumed" {
  let completed = "var fiber = Fiber.new { 42 }\nfiber.call()\nfiber.call()\n"
  match @moonwren.run(completed) {
    @moonwren.ProgramCompleted(_, _) =>
      fail("completed fiber should not resume")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidFiberState)
  }
  let aborted = "var fiber = Fiber.new { Fiber.abort(\"stop\") }\n" +
    "fiber.try()\n" +
    "fiber.call()\n"
  match @moonwren.run(aborted) {
    @moonwren.ProgramCompleted(_, _) => fail("aborted fiber should not resume")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidFiberState)
  }
}

///|
test "fibers preserve block scopes across suspension" {
  let source = "var fiber = Fiber.new {\n" +
    "  { var local = 40\n" +
    "    var resumed = Fiber.yield(\"block\")\n" +
    "    System.print(local + resumed)\n" +
    "  }\n" +
    "  return \"done\"\n" +
    "}\n" +
    "System.print(fiber.call())\n" +
    "System.print(fiber.call(2))\n"
  expect_fiber_output(source, ["block", "42", "done"])
}

///|
test "fibers suspend in conditional branches" {
  let source = "var fiber = Fiber.new { |enabled|\n" +
    "  if (enabled) {\n" +
    "    var value = Fiber.yield(\"if\")\n" +
    "    return value\n" +
    "  } else { return \"disabled\" }\n" +
    "}\n" +
    "System.print(fiber.call(true))\n" +
    "System.print(fiber.call(\"resumed\"))\n"
  expect_fiber_output(source, ["if", "resumed"])
}

///|
test "fibers resume while and for loops without replaying iterations" {
  let source = "var whileFiber = Fiber.new {\n" +
    "  var index = 0\n" +
    "  while (index < 3) {\n" +
    "    index = index + 1\n" +
    "    Fiber.yield(index)\n" +
    "  }\n" +
    "  return index\n" +
    "}\n" +
    "System.print(whileFiber.call())\n" +
    "System.print(whileFiber.call())\n" +
    "System.print(whileFiber.call())\n" +
    "System.print(whileFiber.call())\n" +
    "var forFiber = Fiber.new {\n" +
    "  for (item in [4, 5]) { Fiber.yield(item) }\n" +
    "  return 6\n" +
    "}\n" +
    "System.print(forFiber.call())\n" +
    "System.print(forFiber.call())\n" +
    "System.print(forFiber.call())\n"
  expect_fiber_output(source, ["1", "2", "3", "3", "4", "5", "6"])
}
