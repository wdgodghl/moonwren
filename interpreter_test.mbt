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
test "classes support operator subscript and setter signatures" {
  expect_program_value(
    "class Box {\n" +
    "  construct new(value) { _value = value }\n" +
    "  value { return _value }\n" +
    "  value=(next) { _value = next }\n" +
    "  +(other) { return _value + other.value }\n" +
    "  - { return -_value }\n" +
    "  [index] { return _value + index }\n" +
    "  [index]=(next) { _value = next + index }\n" +
    "}\n" +
    "var box = Box.new(10)\n" +
    "box.value = 12\n" +
    "box[3] = 20\n" +
    "(box + Box.new(7)) + box[2] + -box\n",
    @moonwren.Value::number(32.0),
  )
}

///|
test "method calls accept trailing block arguments" {
  expect_program_value(
    "[1, 2, 3].map {|value| value * 4}.toList[2]\n",
    @moonwren.Value::number(12.0),
  )
}

///|
test "string interpolation parses nested expressions and escaped percent" {
  expect_program_value(
    "var name = \"Moon\"\n\"Hello %(name), %(1 + (2 * 3)) and \\%(literal)\"\n",
    @moonwren.Value::string("Hello Moon, 7 and %(literal)"),
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

///|
test "list literals support indexed reads writes and count" {
  let source = "var values = [10, 20, 30]\n" +
    "values[1] = 12\n" +
    "values[0] + values[1] + values.count\n"
  expect_program_value(source, @moonwren.Value::number(25.0))
}

///|
test "list methods add insert remove contains and clear" {
  let source = "var values = [1, 3]\n" +
    "values.insert(1, 2)\n" +
    "values.add(4)\n" +
    "var removed = values.removeAt(0)\n" +
    "var found = values.contains(3)\n" +
    "values.clear()\n" +
    "removed + (found ? 10 : 0) + values.count\n"
  expect_program_value(source, @moonwren.Value::number(11.0))
}

///|
test "map literals support lookup update and duplicate keys" {
  let source = "var values = {\"answer\": 1, \"answer\": 40}\n" +
    "values[\"answer\"] = values[\"answer\"] + 2\n" +
    "values[\"missing\"] = 7\n" +
    "values[\"answer\"] + values.count\n"
  expect_program_value(source, @moonwren.Value::number(44.0))
}

///|
test "map methods inspect remove and clear entries" {
  let source = "var values = {\"one\": 1, \"two\": 2}\n" +
    "var hadTwo = values.containsKey(\"two\")\n" +
    "var removed = values.remove(\"one\")\n" +
    "var absent = values.remove(\"missing\")\n" +
    "values.clear()\n" +
    "removed + (hadTwo ? 10 : 0) + (absent == null ? 30 : 0) + values.count\n"
  expect_program_value(source, @moonwren.Value::number(41.0))
}

///|
test "missing map keys read as null" {
  expect_program_value(
    "var values = {}\nvalues[\"missing\"]\n",
    @moonwren.Value::null(),
  )
}

///|
test "for loops iterate over a stable list snapshot" {
  let source = "var values = [1, 2, 3, 4]\n" +
    "var total = 0\n" +
    "for (item in values) {\n" +
    "  values.add(99)\n" +
    "  if (item == 2) continue\n" +
    "  if (item == 4) break\n" +
    "  total = total + item\n" +
    "}\n" +
    "total + values.count\n"
  expect_program_value(source, @moonwren.Value::number(12.0))
}

///|
test "collections preserve identity equality" {
  let source = "var left = [1]\n" +
    "var same = left\n" +
    "var other = [1]\n" +
    "(left == same) && (left != other)\n"
  expect_program_value(source, @moonwren.Value::bool(true))
}

///|
test "nested collections have readable output" {
  let source = "var values = [1, {\"two\": 2}]\n" +
    "System.print(values)\n" +
    "values.toString\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(@moonwren.StringValue(text), output) => {
      assert_eq(text, "[1, {two: 2}]")
      assert_eq(output, ["[1, {two: 2}]"])
    }
    _ => fail("collection output should succeed")
  }
}

///|
test "self-referential collections have bounded output" {
  let source = "var values = []\n" +
    "values.add(values)\n" +
    "System.print(values)\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, [text]) => assert_true(text.length() < 100)
    _ => fail("recursive collection output should succeed")
  }
}

///|
test "list indexes produce structured diagnostics" {
  match @moonwren.run("[1][1.5]\n") {
    @moonwren.ProgramCompleted(_, _) => fail("fractional index should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidIndex)
  }
  match @moonwren.run("[1][2]\n") {
    @moonwren.ProgramCompleted(_, _) => fail("large index should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.IndexOutOfBounds)
  }
}

///|
test "user classes can implement the iteration protocol" {
  let source = "class Pair {\n" +
    "  construct new() {}\n" +
    "  iterate(iterator) {\n" +
    "    if (iterator == null) return 0\n" +
    "    return iterator < 1 ? iterator + 1 : false\n" +
    "  }\n" +
    "  iteratorValue(iterator) { return iterator + 10 }\n" +
    "}\n" +
    "var total = 0\n" +
    "for (value in Pair.new()) total = total + value\n" +
    "total\n"
  expect_program_value(source, @moonwren.Value::number(21.0))
}

///|
test "iterable classes must implement both protocol methods" {
  let source = "class Broken {\n" +
    "  construct new() {}\n" +
    "  iterate(iterator) { return iterator == null ? 0 : false }\n" +
    "}\n" +
    "for (value in Broken.new()) value\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, _) => fail("incomplete iterator should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedMethod)
  }
}

///|
test "list indexes accept negative offsets" {
  let source = "var values = [10, 20, 30]\n" +
    "values[-1] = 12\n" +
    "values[-3] + values[-1]\n"
  expect_program_value(source, @moonwren.Value::number(22.0))
}

///|
test "list methods normalize negative indexes" {
  let source = "var values = [1, 2, 3]\n" +
    "values.insert(-1, 8)\n" +
    "var removed = values.removeAt(-2)\n" +
    "removed + values[-1]\n"
  expect_program_value(source, @moonwren.Value::number(11.0))
}

///|
test "list range subscripts support inclusive exclusive and descending slices" {
  let source = "var values = [0, 1, 2, 3, 4]\n" +
    "values[1..3].toString + \"|\" + values[1...4].toString + \"|\" + values[3..1].toString\n"
  expect_program_value(
    source,
    @moonwren.Value::string("[1, 2, 3]|[1, 2, 3]|[3, 2, 1]"),
  )
}

///|
test "list indexOf remove and swap mutate predictably" {
  let source = "var values = [10, 20, 30]\n" +
    "var index = values.indexOf(20)\n" +
    "var removed = values.remove(20)\n" +
    "var absent = values.remove(99)\n" +
    "values.swap(0, -1)\n" +
    "index + removed + (absent == null ? 1 : 0) + values[0]\n"
  expect_program_value(source, @moonwren.Value::number(52.0))
}

///|
test "map key and value views are stable iterable snapshots" {
  let source = "var values = {\"a\": 1, \"b\": 2}\n" +
    "var keys = values.keys\n" +
    "var numbers = values.values\n" +
    "values[\"c\"] = 100\n" +
    "var keyCount = 0\n" +
    "for (key in keys) keyCount = keyCount + 1\n" +
    "var total = 0\n" +
    "for (number in numbers) total = total + number\n" +
    "keyCount + total + keys.count + numbers.count\n"
  expect_program_value(source, @moonwren.Value::number(9.0))
}

///|
test "mutable values cannot be used as map keys" {
  match @moonwren.run("var key = [1]\nvar values = {key: 2}\n") {
    @moonwren.ProgramCompleted(_, _) => fail("mutable map key should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidMapKey)
  }
  match @moonwren.run("var values = {}\nvalues[[1]]\n") {
    @moonwren.ProgramCompleted(_, _) => fail("mutable lookup key should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidMapKey)
  }
}

///|
test "built-in iteration protocol can be invoked directly" {
  let source = "var values = [4, 5]\n" +
    "var first = values.iterate(null)\n" +
    "var second = values.iterate(first)\n" +
    "values.iteratorValue(first) + values.iteratorValue(second)\n"
  expect_program_value(source, @moonwren.Value::number(9.0))
}

///|
test "string count uses Unicode characters" {
  expect_program_value("\"A🤣中\".count\n", @moonwren.Value::number(3.0))
}

///|
test "string subscripts use Wren UTF-8 byte offsets" {
  let source = "var text = \"A🤣中\"\ntext[1] + text[-3]\n"
  expect_program_value(source, @moonwren.Value::string("🤣中"))
}

///|
test "string range subscripts preserve Unicode boundaries" {
  let source = "var text = \"A🤣中文\"\n" +
    "text[1..2] + \"|\" + text[0...2] + \"|\" + text[3..1]\n"
  expect_program_value(source, @moonwren.Value::string("🤣|A🤣|🤣"))
}

///|
test "for loops iterate over Unicode characters" {
  let source = "var result = \"\"\n" +
    "for (character in \"A🤣中\") result = result + character\n" +
    "result\n"
  expect_program_value(source, @moonwren.Value::string("A🤣中"))
}

///|
test "string search predicates support Unicode text" {
  let source = "var text = \"月亮Moon🤣\"\n" +
    "text.contains(\"Moon\") && text.startsWith(\"月亮\") && text.endsWith(\"🤣\")\n"
  expect_program_value(source, @moonwren.Value::bool(true))
}

///|
test "string indexOf returns Wren UTF-8 byte offsets" {
  let source = "var text = \"A🤣中🤣\"\n" +
    "text.indexOf(\"中\") + text.indexOf(\"missing\")\n"
  expect_program_value(source, @moonwren.Value::number(4.0))
}

///|
test "string split returns a mutable list" {
  let source = "var parts = \"红|绿|蓝\".split(\"|\")\n" +
    "parts.add(\"紫\")\n" +
    "parts.count.toString + \"|\" + parts[-1]\n"
  expect_program_value(source, @moonwren.Value::string("4|紫"))
}

///|
test "string replace replaces every occurrence" {
  expect_program_value(
    "\"月-月-星\".replace(\"月\", \"Moon\")\n",
    @moonwren.Value::string("Moon-Moon-星"),
  )
}

///|
test "string methods validate argument types" {
  match @moonwren.run("\"text\".contains(42)\n") {
    @moonwren.ProgramCompleted(_, _) => fail("non-string argument should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
  match @moonwren.run("\"text\".replace(\"t\", 42)\n") {
    @moonwren.ProgramCompleted(_, _) =>
      fail("non-string replacement should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}

///|
test "string split and replace reject empty search text" {
  match @moonwren.run("\"text\".split(\"\")\n") {
    @moonwren.ProgramCompleted(_, _) => fail("empty separator should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
  match @moonwren.run("\"text\".replace(\"\", \"x\")\n") {
    @moonwren.ProgramCompleted(_, _) => fail("empty search should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}

///|
test "string values reject indexed assignment" {
  match @moonwren.run("var text = \"abc\"\ntext[0] = \"z\"\n") {
    @moonwren.ProgramCompleted(_, _) => fail("string assignment should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}

///|
test "empty built-in iterables skip the loop body" {
  let source = "var visits = 0\n" +
    "for (item in []) visits = visits + 1\n" +
    "for (item in \"\") visits = visits + 1\n" +
    "for (item in 1...1) visits = visits + 1\n" +
    "visits\n"
  expect_program_value(source, @moonwren.Value::number(0.0))
}

///|
test "list slices normalize negative range endpoints" {
  expect_program_value(
    "[0, 1, 2, 3, 4][-4..-2].toString\n",
    @moonwren.Value::string("[1, 2, 3]"),
  )
}

///|
test "string slices normalize negative range endpoints" {
  expect_program_value(
    "\"甲乙丙丁\"[-3..-1]\n",
    @moonwren.Value::string("丁"),
  )
}

///|
test "exclusive slices may be empty at the collection end" {
  let source = "[1, 2][2...2].toString + \"|\" + \"ab\"[2...2]\n"
  expect_program_value(source, @moonwren.Value::string("[]|"))
}

///|
test "map views preserve insertion order" {
  let source = "var values = {\"first\": 1, \"second\": 2}\n" +
    "values.keys.toString + \"|\" + values.values.toString\n"
  expect_program_value(
    source,
    @moonwren.Value::string("(first, second)|(1, 2)"),
  )
}

///|
test "string split supports multi-character separators" {
  let source = "\"甲--乙--丙\".split(\"--\").toString\n"
  expect_program_value(source, @moonwren.Value::string("[甲, 乙, 丙]"))
}

///|
test "modules import values classes and aliases" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main",
      "import \"math\" for Calculator as Calc, answer\n" +
      "Calc.double(answer)\n",
    ),
    @moonwren.ModuleSource::new(
      "math",
      "var answer = 21\n" +
      "class Calculator { static double(value) { return value * 2 } }\n",
    ),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("module import should succeed")
  }
}

///|
test "module environments keep top-level names isolated" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main", "var value = 40\nimport \"other\" for value as otherValue\nvalue + otherValue\n",
    ),
    @moonwren.ModuleSource::new("other", "var value = 2\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("module scopes should remain isolated")
  }
}

///|
test "module cache executes each canonical module once" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main", "import \"boot\"\nimport \"boot\"\n42\n",
    ),
    @moonwren.ModuleSource::new("boot", "System.print(\"loaded\")\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["loaded"])
    }
    _ => fail("cached module should execute once")
  }
}

///|
test "missing modules produce source-located diagnostics" {
  let modules = [
    @moonwren.ModuleSource::new("main.wren", "import \"missing\"\n"),
  ]
  match @moonwren.run_modules("main.wren", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("missing module should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ModuleNotFound)
      assert_eq(issues[0].source_name, "main.wren")
    }
  }
}

///|
test "imports reject undefined exported names" {
  let modules = [
    @moonwren.ModuleSource::new("main", "import \"values\" for missing\n"),
    @moonwren.ModuleSource::new("values", "var present = 42\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("undefined export should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.UndefinedExport)
  }
}

///|
test "circular imports are detected" {
  let modules = [
    @moonwren.ModuleSource::new("a", "import \"b\"\n"),
    @moonwren.ModuleSource::new("b", "import \"a\"\n"),
  ]
  match @moonwren.run_modules("a", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("cycle should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.CircularImport)
      assert_eq(issues[0].source_name, "a")
      assert_eq(issues[0].frames.length(), 2)
    }
  }
}

///|
test "module parse failures retain the imported source name" {
  let modules = [
    @moonwren.ModuleSource::new("main", "import \"broken.wren\"\n"),
    @moonwren.ModuleSource::new("broken.wren", "var value =\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("broken module should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].phase, @moonwren.Parse)
      assert_eq(issues[0].source_name, "broken.wren")
      assert_eq(issues[0].frames.length(), 1)
    }
  }
}

///|
test "module loaders can canonicalize multiple specifiers" {
  let loader = fn(
    _importer : String,
    specifier : String,
  ) -> @moonwren.ModuleLoadResult {
    if specifier == "util" || specifier == "./util" {
      @moonwren.ModuleLoaded(
        "lib/util.wren", "System.print(\"once\")\nvar value = 21\n",
      )
    } else {
      @moonwren.ModuleLoadFailed("not found")
    }
  }
  let source = "import \"util\" for value as first\n" +
    "import \"./util\" for value as second\n" +
    "first + second\n"
  match @moonwren.run_with_loader("main.wren", source, 100000, loader) {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["once"])
    }
    _ => fail("canonical loader should share the module cache")
  }
}

///|
test "runtime failures retain cross-module call stacks" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main.wren",
      "import \"math.wren\" for Calculator\n" +
      "var run = Fn.new { return Calculator.divide() }\n" +
      "run.call()\n",
    ),
    @moonwren.ModuleSource::new(
      "math.wren", "class Calculator { static divide() { return 1 / 0 } }\n",
    ),
  ]
  match @moonwren.run_modules("main.wren", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("division should fail")
    @moonwren.ProgramFailed(issues, _) => {
      let issue = issues[0]
      assert_eq(issue.code, @moonwren.DivisionByZero)
      assert_eq(issue.source_name, "math.wren")
      assert_eq(issue.frames.length(), 2)
      assert_eq(issue.frames[0].callable, "Calculator.divide")
      assert_eq(issue.frames[1].callable, "Fn.call")
      let rendered = issue.render("fallback")
      assert_true(rendered.contains("math.wren"))
      assert_true(rendered.contains("Calculator.divide"))
      assert_true(rendered.contains("main.wren"))
    }
  }
}

///|
test "transitive imports resolve through isolated modules" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main", "import \"middle\" for answer\nanswer\n",
    ),
    @moonwren.ModuleSource::new(
      "middle", "import \"base\" for value\nvar answer = value + 2\n",
    ),
    @moonwren.ModuleSource::new("base", "var value = 40\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("transitive import should succeed")
  }
}

///|
test "imported closures retain private module state" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main", "import \"private\" for reveal\nreveal.call()\n",
    ),
    @moonwren.ModuleSource::new(
      "private", "var secret = 42\nvar reveal = Fn.new { return secret }\n",
    ),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("imported closure should retain module state")
  }
}

///|
test "repeated imports share class state" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main",
      "import \"counter\" for Counter as First\n" +
      "import \"counter\" for Counter as Second\n" +
      "First.next()\nSecond.next()\n",
    ),
    @moonwren.ModuleSource::new(
      "counter",
      "class Counter {\n" +
      "  static next() {\n" +
      "    __value = __value == null ? 1 : __value + 1\n" +
      "    return __value\n" +
      "  }\n" +
      "}\n",
    ),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(2.0))
    _ => fail("cached class should share static state")
  }
}

///|
test "imports reject duplicate local bindings" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main", "var answer = 0\nimport \"values\" for answer\n",
    ),
    @moonwren.ModuleSource::new("values", "var answer = 42\n"),
  ]
  match @moonwren.run_modules("main", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("duplicate binding should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.DuplicateVariable)
  }
}

///|
test "run_modules reports a missing entry module" {
  match @moonwren.run_modules("missing", [], 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("missing entry should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ModuleNotFound)
      assert_eq(issues[0].source_name, "missing")
    }
  }
}

///|
test "execution budgets are shared across imported modules" {
  let modules = [
    @moonwren.ModuleSource::new("main", "import \"loop\"\n"),
    @moonwren.ModuleSource::new("loop", "while (true) { 1 }\n"),
  ]
  match @moonwren.run_modules("main", modules, 20) {
    @moonwren.ProgramCompleted(_, _) => fail("loop should exhaust budget")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ExecutionLimit)
      assert_eq(issues[0].source_name, "loop")
    }
  }
}

///|
test "entry parsing preserves every diagnostic and source name" {
  let modules = [
    @moonwren.ModuleSource::new("broken.wren", "var first =\nvar second =\n"),
  ]
  match @moonwren.run_modules("broken.wren", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("broken entry should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_true(issues.length() > 1)
      for issue in issues {
        assert_eq(issue.source_name, "broken.wren")
      }
    }
  }
}

///|
test "imported function failures identify definition and caller modules" {
  let modules = [
    @moonwren.ModuleSource::new(
      "main.wren", "import \"failure.wren\" for failNow\nfailNow.call()\n",
    ),
    @moonwren.ModuleSource::new(
      "failure.wren", "var failNow = Fn.new { return missing }\n",
    ),
  ]
  match @moonwren.run_modules("main.wren", modules, 100000) {
    @moonwren.ProgramCompleted(_, _) => fail("function should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].source_name, "failure.wren")
      assert_eq(issues[0].frames.length(), 1)
      assert_eq(issues[0].frames[0].source_name, "main.wren")
    }
  }
}
