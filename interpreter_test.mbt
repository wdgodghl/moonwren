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

///|
test "multi-statement functions return explicit values" {
  let source = "var double = Fn.new { |value|\n" +
    "  var result = value * 2\n" +
    "  return result\n" +
    "}\n" +
    "double.call(21)\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "bare return produces null" {
  let source = "var stop = Fn.new {\n  return\n  42\n}\nstop.call()\n"
  expect_program_value(source, @moonwren.Value::null())
}

///|
test "return escapes nested blocks and skips later statements" {
  let source = "var choose = Fn.new {\n" +
    "  if (true) {\n" +
    "    return 42\n" +
    "  }\n" +
    "  System.print(\"unreachable\")\n" +
    "}\n" +
    "System.print(choose.call())\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["42"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "return escapes loops" {
  let source = "var first = Fn.new {\n" +
    "  for (item in 4..8) {\n" +
    "    return item\n" +
    "  }\n" +
    "  return 0\n" +
    "}\n" +
    "first.call()\n"
  expect_program_value(source, @moonwren.Value::number(4.0))
}

///|
test "return outside a function reports its source location" {
  match @moonwren.run("return 42\n") {
    @moonwren.ProgramCompleted(_, _) => fail("program should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ReturnOutsideFunction)
      assert_eq(issues[0].span.start.line, 1)
      assert_eq(issues[0].span.start.column, 1)
    }
  }
}

///|
test "returned closures retain function-local mutable state" {
  let source = "var makeCounter = Fn.new {\n" +
    "  var count = 0\n" +
    "  return Fn.new {\n" +
    "    count = count + 1\n" +
    "    return count\n" +
    "  }\n" +
    "}\n" +
    "var counter = makeCounter.call()\n" +
    "System.print(counter.call())\n" +
    "System.print(counter.call())\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["1", "2"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "recursive function calls share the execution budget" {
  let source = "var forever = Fn.new { forever.call() }\nforever.call()\n"
  match @moonwren.run_with_limit(source, 20) {
    @moonwren.ProgramCompleted(_, _) => fail("program should stop")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
  }
}

///|
test "default runtime stops runaway recursion before exhausting the host stack" {
  let source = "var forever = Fn.new { forever.call() }\nforever.call()\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("program should stop")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.CallStackLimit)
  }
}

///|
test "classes construct instances and expose state through getters" {
  let source = "class Point {\n" +
    "  construct new(x, y) {\n" +
    "    _x = x\n" +
    "    _y = y\n" +
    "  }\n" +
    "  sum { return _x + _y }\n" +
    "}\n" +
    "var point = Point.new(19, 23)\n" +
    "point.sum\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "instance methods update persistent fields" {
  let source = "class Counter {\n" +
    "  construct new(start) { _value = start }\n" +
    "  add(amount) { _value = _value + amount }\n" +
    "  value { return _value }\n" +
    "}\n" +
    "var counter = Counter.new(40)\n" +
    "counter.add(2)\n" +
    "counter.value\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "instances keep independent field storage" {
  let source = "class Box {\n" +
    "  construct new(value) { _value = value }\n" +
    "  value { return _value }\n" +
    "}\n" +
    "var first = Box.new(20)\n" +
    "var second = Box.new(22)\n" +
    "first.value + second.value\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "this refers to the receiving instance" {
  let source = "class Identity {\n" +
    "  construct new() {}\n" +
    "  self { return this }\n" +
    "}\n" +
    "var value = Identity.new()\n" +
    "value.self == value\n"
  expect_program_value(source, @moonwren.Value::bool(true))
}

///|
test "uninitialized instance fields read as null" {
  let source = "class Empty {\n" +
    "  construct new() {}\n" +
    "  value { return _value }\n" +
    "}\n" +
    "Empty.new().value\n"
  expect_program_value(source, @moonwren.Value::null())
}

///|
test "class methods capture their declaration environment" {
  let source = "var offset = 40\n" +
    "class Calculator {\n" +
    "  construct new() {}\n" +
    "  add(value) { return offset + value }\n" +
    "}\n" +
    "Calculator.new().add(2)\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "duplicate method signatures are rejected" {
  let source = "class Invalid {\n" +
    "  value { return 1 }\n" +
    "  value { return 2 }\n" +
    "}\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("class should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.DuplicateMethod)
  }
}

///|
test "missing constructors and method arities are diagnosed" {
  match @moonwren.run("class Empty {}\nEmpty.new()\n") {
    @moonwren.ProgramCompleted(_, _) => fail("construction should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
  let source = "class Box {\n" +
    "  construct new() {}\n" +
    "  set(value) { return value }\n" +
    "}\n" +
    "Box.new().set()\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("method call should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}

///|
test "instance fields are unavailable outside methods" {
  match @moonwren.run("_value\n") {
    @moonwren.ProgramCompleted(_, _) => fail("field access should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedVariable)
  }
}

///|
test "instance methods can recurse through this" {
  let source = "class Counter {\n" +
    "  construct new() {}\n" +
    "  count(value) {\n" +
    "    return value <= 0 ? 0 : 1 + this.count(value - 1)\n" +
    "  }\n" +
    "}\n" +
    "Counter.new().count(42)\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "closures returned by methods retain their receiving instance" {
  let source = "class Counter {\n" +
    "  construct new() { _value = 0 }\n" +
    "  callback {\n" +
    "    return Fn.new {\n" +
    "      _value = _value + 1\n" +
    "      return _value\n" +
    "    }\n" +
    "  }\n" +
    "}\n" +
    "var callback = Counter.new().callback\n" +
    "callback.call()\n" +
    "callback.call()\n"
  expect_program_value(source, @moonwren.Value::number(2.0))
}

///|
test "method dispatch distinguishes signatures by arity" {
  let source = "class Select {\n" +
    "  construct new() {}\n" +
    "  value() { return 20 }\n" +
    "  value(extra) { return 20 + extra }\n" +
    "}\n" +
    "var select = Select.new()\n" +
    "select.value() + select.value(2)\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "subclasses inherit methods getters and initialized fields" {
  let source = "class Base {\n" +
    "  construct new(value) { _value = value }\n" +
    "  add(amount) { _value = _value + amount }\n" +
    "  value { return _value }\n" +
    "}\n" +
    "class Child is Base {\n" +
    "  construct new(value) { super(value) }\n" +
    "}\n" +
    "var child = Child.new(40)\n" +
    "child.add(2)\n" +
    "child.value\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "overrides can call superclass methods and getters" {
  let source = "class Base {\n" +
    "  construct new() {}\n" +
    "  number { return 20 }\n" +
    "  add(value) { return value + 1 }\n" +
    "}\n" +
    "class Child is Base {\n" +
    "  construct new() { super() }\n" +
    "  number { return super.number + 1 }\n" +
    "  add(value) { return super.add(value) + 1 }\n" +
    "}\n" +
    "var child = Child.new()\n" +
    "child.number + child.add(19)\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "super lookup advances from each declaring class" {
  let source = "class First {\n" +
    "  construct new() {}\n" +
    "  value() { return 1 }\n" +
    "}\n" +
    "class Second is First {\n" +
    "  construct new() { super() }\n" +
    "  value() { return super.value() + 1 }\n" +
    "}\n" +
    "class Third is Second {\n" +
    "  construct new() { super() }\n" +
    "  value() { return super.value() + 40 }\n" +
    "}\n" +
    "Third.new().value()\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "is recognizes instance and class inheritance" {
  let source = "class Animal { construct new() {} }\n" +
    "class Dog is Animal { construct new() { super() } }\n" +
    "var dog = Dog.new()\n" +
    "(dog is Dog) && (dog is Animal) && (Dog is Animal) && !(Animal is Dog)\n"
  expect_program_value(source, @moonwren.Value::bool(true))
}

///|
test "constructors are not inherited implicitly" {
  let source = "class Base { construct new() {} }\n" +
    "class Child is Base {}\n" +
    "Child.new()\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("construction should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}

///|
test "invalid and undefined superclasses are diagnosed" {
  match @moonwren.run("var value = 42\nclass Child is value {}\n") {
    @moonwren.ProgramCompleted(_, _) => fail("class should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidSuperclass)
  }
  match @moonwren.run("class Child is Missing {}\n") {
    @moonwren.ProgramCompleted(_, _) => fail("class should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidSuperclass)
  }
}

///|
test "super is unavailable without a superclass method context" {
  match @moonwren.run("super.missing()\n") {
    @moonwren.ProgramCompleted(_, _) => fail("super call should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedVariable)
  }
}

///|
test "missing superclass members produce structured diagnostics" {
  let source = "class Base { construct new() {} }\n" +
    "class Child is Base {\n" +
    "  construct new() { super() }\n" +
    "  value() { return super.missing() }\n" +
    "}\n" +
    "Child.new().value()\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("super call should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}

///|
test "static methods and getters retain class state" {
  let source = "class Registry {\n" +
    "  static put(value) { __value = value }\n" +
    "  static value { return __value }\n" +
    "}\n" +
    "Registry.put(42)\n" +
    "Registry.value\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "uninitialized static fields read as null" {
  let source = "class Registry {\n" +
    "  static value { return __value }\n" +
    "}\n" +
    "Registry.value\n"
  expect_program_value(source, @moonwren.Value::null())
}

///|
test "static methods are inherited and can be overridden" {
  let source = "class Base {\n" +
    "  static value() { return 20 }\n" +
    "  static total() { return this.value() }\n" +
    "}\n" +
    "class Child is Base {\n" +
    "  static value() { return super.value() + 2 }\n" +
    "}\n" +
    "Child.total()\n"
  expect_program_value(source, @moonwren.Value::number(22.0))
}

///|
test "inherited static fields belong to their declaring class" {
  let source = "class Base {\n" +
    "  static increment() { __count = __count == null ? 1 : __count + 1 }\n" +
    "  static count { return __count }\n" +
    "}\n" +
    "class Child is Base {}\n" +
    "Base.increment()\n" +
    "Child.increment()\n" +
    "Base.count\n"
  expect_program_value(source, @moonwren.Value::number(2.0))
}

///|
test "instance and static signatures can coexist" {
  let source = "class Both {\n" +
    "  construct new() {}\n" +
    "  value() { return 20 }\n" +
    "  static value() { return 22 }\n" +
    "}\n" +
    "Both.new().value() + Both.value()\n"
  expect_program_value(source, @moonwren.Value::number(42.0))
}

///|
test "static fields are rejected outside static methods" {
  let source = "class Invalid {\n" +
    "  construct new() {}\n" +
    "  value { return __value }\n" +
    "}\n" +
    "Invalid.new().value\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("field access should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedVariable)
  }
}

///|
test "constructors cannot be declared static" {
  match @moonwren.run("class Invalid { static construct new() {} }\n") {
    @moonwren.ProgramCompleted(_, _) => fail("class should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UnexpectedToken)
  }
}

///|
test "while loops support continue and break through nested blocks" {
  let source = "var count = 0\n" +
    "var total = 0\n" +
    "while (count < 6) {\n" +
    "  count = count + 1\n" +
    "  if (count == 3) { continue }\n" +
    "  if (count > 4) { break }\n" +
    "  total = total + count\n" +
    "}\n" +
    "total\n"
  expect_program_value(source, @moonwren.Value::number(7.0))
}

///|
test "range loops consume their own continue and break" {
  let source = "var total = 0\n" +
    "for (item in 1..10) {\n" +
    "  if (item % 2 == 0) continue\n" +
    "  if (item > 7) break\n" +
    "  total = total + item\n" +
    "}\n" +
    "total\n"
  expect_program_value(source, @moonwren.Value::number(16.0))
}

///|
test "break exits only the innermost loop" {
  let source = "var visits = 0\n" +
    "for (outer in 1..3) {\n" +
    "  for (inner in 1..3) {\n" +
    "    if (inner == 2) break\n" +
    "    visits = visits + 1\n" +
    "  }\n" +
    "}\n" +
    "visits\n"
  expect_program_value(source, @moonwren.Value::number(3.0))
}

///|
test "top-level break and continue produce structured diagnostics" {
  match @moonwren.run("break\n") {
    @moonwren.ProgramCompleted(_, _) => fail("break should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.BreakOutsideLoop)
  }
  match @moonwren.run("continue\n") {
    @moonwren.ProgramCompleted(_, _) => fail("continue should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ContinueOutsideLoop)
  }
}

///|
test "loop control cannot escape a called function" {
  let source = "var stop = Fn.new { break }\n" +
    "while (true) { stop.call() }\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("function should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.BreakOutsideLoop)
  }
}

///|
test "loop control cannot escape a called method" {
  let source = "class Invalid {\n" +
    "  construct new() {}\n" +
    "  skip() { continue }\n" +
    "}\n" +
    "while (true) { Invalid.new().skip() }\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("method should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ContinueOutsideLoop)
  }
}
