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
    "var fiber = Fiber.new {\n ran = true\n return 42\n}\n" +
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
  let source = "var fiber = Fiber.new {\n Fiber.abort(null)\n return 42\n}\n" +
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
    "var outer = Fiber.new { inner.call() + 2 }\n" +
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

///|
test "fibers preserve suspension inside called functions" {
  let source = "var worker = Fn.new { |base|\n" +
    "  { var local = base + 1\n" +
    "    var first = Fiber.yield(\"from function\")\n" +
    "    var second = Fiber.yield(local + first)\n" +
    "    return second\n" +
    "  }\n" +
    "}\n" +
    "var fiber = Fiber.new {\n" +
    "  var value = worker.call(40)\n" +
    "  return value + 1\n" +
    "}\n" +
    "System.print(fiber.call())\n" +
    "System.print(fiber.call(1))\n" +
    "System.print(fiber.call(41))\n"
  expect_fiber_output(source, ["from function", "42", "42"])
}

///|
test "called functions keep the visible fiber identity" {
  let source = "var current = null\n" +
    "var helper = Fn.new {\n" +
    "  current = Fiber.current\n" +
    "  Fiber.yield(\"pause\")\n" +
    "  return 7\n" +
    "}\n" +
    "var fiber = Fiber.new { helper.call() }\n" +
    "System.print(fiber.call())\n" +
    "System.print(Object.same(current, fiber))\n" +
    "System.print(fiber.call())\n"
  expect_fiber_output(source, ["pause", "true", "7"])
}

///|
test "fibers suspend and resume through Sequence each callbacks" {
  let source = "var worker = Fiber.new {\n" +
    "  (1..3).each(Fn.new { |number| Fiber.yield(number * 2) })\n" +
    "  return \"done\"\n" +
    "}\n" +
    "System.print(worker.call())\n" +
    "System.print(worker.call())\n" +
    "System.print(worker.call())\n" +
    "System.print(worker.call())\n"
  expect_fiber_output(source, ["2", "4", "6", "done"])
}

///|
test "fibers suspend through instance static methods and getters" {
  let source = "class Worker {\n" +
    "  construct new() {}\n" +
    "  run(value) {\n" +
    "    System.print(\"method-before\")\n" +
    "    var resumed = Fiber.yield(value)\n" +
    "    System.print(\"method-after\")\n" +
    "    return resumed + 1\n" +
    "  }\n" +
    "  answer { return Fiber.yield(20) + 2 }\n" +
    "  static twice(value) { return Fiber.yield(value) * 2 }\n" +
    "}\n" +
    "var worker = Fiber.new {\n" +
    "  var instance = Worker.new()\n" +
    "  var first = 1 + instance.run(10) * 2\n" +
    "  var second = instance.answer\n" +
    "  var third = Worker.twice(30)\n" +
    "  return first + second + third\n" +
    "}\n" +
    "System.print(worker.call())\n" +
    "System.print(worker.call(3))\n" +
    "System.print(worker.call(4))\n" +
    "System.print(worker.call(5))\n"
  expect_fiber_output(source, [
    "method-before", "10", "method-after", "20", "30", "25",
  ])
}

///|
test "nested Fiber calls do not replay completed arguments" {
  let source = "var sideEffects = 0\n" +
    "var pause = Fn.new {|value| Fiber.yield(value) }\n" +
    "var worker = Fiber.new {\n" +
    "  sideEffects = sideEffects + 1\n" +
    "  var result = [sideEffects, pause.call(7), sideEffects]\n" +
    "  return result\n" +
    "}\n" +
    "System.print(worker.call())\n" +
    "System.print(worker.call(9))\n" +
    "System.print(sideEffects)\n"
  expect_fiber_output(source, ["7", "[1, 9, 1]", "1"])
}

///|
test "fibers suspend through operator and subscript methods" {
  let source = "class Yielding {\n" +
    "  construct new() {}\n" +
    "  +(right) { return Fiber.yield(\"operator\") + right }\n" +
    "  [index] { return Fiber.yield(\"get\") + index }\n" +
    "  [index]=(value) { return Fiber.yield(\"set\") + index + value }\n" +
    "}\n" +
    "var fiber = Fiber.new {\n" +
    "  var object = Yielding.new()\n" +
    "  var first = object + 2\n" +
    "  var second = object[3]\n" +
    "  var third = object[4] = 5\n" +
    "  return first + second + third\n" +
    "}\n" +
    "System.print(fiber.call())\n" +
    "System.print(fiber.call(10))\n" +
    "System.print(fiber.call(20))\n" +
    "System.print(fiber.call(30))\n"
  expect_fiber_output(source, ["operator", "get", "set", "74"])
}

///|
test "fiber sequence predicates resume callback state" {
  let source = "var fiber = Fiber.new {\n" +
    "  var all = [1, 2].all {|n|\n Fiber.yield(\"all%(n)\")\n return n > 0\n }\n" +
    "  var any = [1, 2, 3].any {|n|\n Fiber.yield(\"any%(n)\")\n return n == 2\n }\n" +
    "  var count = [1, 2, 3].count {|n|\n Fiber.yield(\"count%(n)\")\n return n > 1\n }\n" +
    "  return \"%(all)|%(any)|%(count)\"\n" +
    "}\n" +
    "while (!fiber.isDone) { System.print(fiber.call()) }\n"
  expect_fiber_output(source, [
    "all1", "all2", "any1", "any2", "count1", "count2", "count3", "true|true|2",
  ])
}

///|
test "fibers suspend through constructors and super constructors" {
  let source = "class Base {\n" +
    "  construct new() { _base = Fiber.yield(\"base\") }\n" +
    "  base { return _base }\n" +
    "}\n" +
    "class Child is Base {\n" +
    "  construct new() { super()\n _child = Fiber.yield(\"child\") }\n" +
    "  total { return this.base + _child }\n" +
    "}\n" +
    "var fiber = Fiber.new {\n var child = Child.new()\n return child.total\n}\n" +
    "System.print(fiber.call())\n" +
    "System.print(fiber.call(20))\n" +
    "System.print(fiber.call(22))\n"
  expect_fiber_output(source, ["base", "child", "42"])
}

///|
test "worker fibers transfer control and values directly" {
  let source = "var main = Fiber.current\n" +
    "var left = null\n" +
    "var right = null\n" +
    "left = Fiber.new {\n" +
    "  var reply = right.transfer(\"left to right\")\n" +
    "  System.print(reply)\n" +
    "  var resumed = main.transfer(\"left to main\")\n" +
    "  return resumed\n" +
    "}\n" +
    "right = Fiber.new { |message|\n" +
    "  System.print(message)\n" +
    "  return left.transfer(\"right to left\")\n" +
    "}\n" +
    "System.print(left.transfer())\n" +
    "System.print(left.transfer(\"finish left\"))\n" +
    "System.print(left.isDone)\n" +
    "System.print(right.transfer(\"finish right\"))\n" +
    "System.print(right.isDone)\n"
  expect_fiber_output(source, [
    "left to right", "right to left", "left to main", "finish left",
  ])
}

///|
test "a fiber can transfer directly to itself" {
  let source = "var fiber = Fiber.new { fiber.transfer() }\n" +
    "System.print(fiber.call())\n"
  expect_fiber_output(source, ["null"])
}
