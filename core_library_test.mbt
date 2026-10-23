///|
fn expect_core_output(source : String, expected : Array[String]) -> Unit raise {
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, expected)
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "core class objects expose names supertypes and constructors" {
  let source = "var list = List.new()\n" +
    "var map = Map.new()\n" +
    "System.print(List.name)\n" +
    "System.print(List.supertype.name)\n" +
    "System.print(list is List)\n" +
    "System.print(list is Sequence)\n" +
    "System.print(map is Map)\n" +
    "System.print(42 is Num)\n" +
    "System.print(Num.type.name)\n"
  expect_core_output(source, [
    "List", "Sequence", "true", "true", "true", "true", "Class",
  ])
}

///|
test "List.filled and Object.same preserve reference identity" {
  let source = "var list = List.filled(3, 7)\n" +
    "System.print(list)\n" +
    "System.print(Object.same(list, list))\n" +
    "System.print(Object.same(list, List.filled(3, 7)))\n"
  expect_core_output(source, ["[7, 7, 7]", "true", "false"])
}

///|
test "Fn.new identity and arity getters are available" {
  let source = "var original = Fn.new { |a, b| a + b }\n" +
    "var copied = Fn.new(original)\n" +
    "System.print(copied.arity)\n" +
    "System.print(Object.same(original, copied))\n" +
    "copied.call(20, 22)\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["2", "true"])
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "Num getters and methods cover common mathematics" {
  let source = "System.print((-3.2).abs)\n" +
    "System.print((-3.2).ceil)\n" +
    "System.print((-3.2).floor)\n" +
    "System.print((-3.2).fraction)\n" +
    "System.print(9.sqrt)\n" +
    "System.print(2.pow(5))\n" +
    "System.print(12.clamp(0, 10))\n" +
    "System.print(2.5.isInteger)\n" +
    "System.print(3.isInteger)\n"
  expect_core_output(source, [
    "3.2", "-3", "-4", "-0.20000000000000018", "3", "32", "10", "false", "true",
  ])
}

///|
test "Num.fromString accepts decimals and rejects malformed input" {
  let source = "System.print(Num.fromString(\"-12.5e2\"))\n" +
    "System.print(Num.fromString(\"not a number\"))\n" +
    "System.print(Num.maxSafeInteger)\n"
  expect_core_output(source, ["-1250", "null", "9007199254740991"])
}

///|
test "String search and trim overloads use character indexes" {
  let source = "System.print(\"  moon  \".trim())\n" +
    "System.print(\"xxmoonxy\".trim(\"xy\"))\n" +
    "System.print(\"banana\".indexOf(\"na\"))\n" +
    "System.print(\"banana\".indexOf(\"na\", 3))\n" +
    "System.print(\"banana\".indexOf(\"ba\", -6))\n"
  expect_core_output(source, ["moon", "moon", "2", "4", "0"])
}

///|
test "String byte and code point views are iterable" {
  let source = "System.print(\"Aé\".bytes.toList)\n" +
    "System.print(\"Aé\".codePoints.toList)\n" +
    "System.print(String.fromCodePoint(9731))\n" +
    "System.print(String.fromByte(65))\n"
  expect_core_output(source, ["[65, 195, 169]", "[65, 233]", "☃", "A"])
}

///|
test "String indexes and search use Wren UTF-8 byte offsets" {
  let source = "var text = \"Aé𐍈\"\n" +
    "System.print(text.count)\n" +
    "System.print(text.bytes.count)\n" +
    "System.print(text.indexOf(\"𐍈\"))\n" +
    "System.print(text[1])\n" +
    "System.print(text.codePoints[2])\n"
  expect_core_output(source, ["3", "7", "3", "é", "-1"])
}

///|
test "String.fromByte preserves invalid UTF-8 bytes" {
  let source = "var raw = String.fromByte(255)\n" +
    "System.print(raw.count)\n" +
    "System.print(raw.bytes[0])\n" +
    "System.print(raw.codePoints[0])\n"
  expect_core_output(source, ["1", "255", "-1"])
}

///|
test "mixed valid and invalid String bytes share complete operations" {
  let source = "var invalid = String.fromByte(255)\n" +
    "var mixed = \"A\" + invalid + \"é\"\n" +
    "System.print(mixed.count)\n" +
    "System.print(mixed.bytes.toList)\n" +
    "System.print(mixed.codePoints.toList)\n" +
    "System.print(mixed[1..3].bytes.toList)\n" +
    "System.print(mixed[3..1].bytes.toList)\n" +
    "System.print(mixed.contains(invalid))\n" +
    "System.print(mixed.indexOf(\"é\"))\n" +
    "System.print(mixed.replace(invalid, \"?\").bytes.toList)\n"
  expect_core_output(source, [
    "3", "[65, 255, 195, 169]", "[65, -1, 233]", "[255, 195, 169]", "[195, 169, 255]",
    "true", "2", "[65, 63, 195, 169]",
  ])
}

///|
test "byte-identical Strings compare and hash as the same Map key" {
  let source = "var left = String.fromByte(255) + \"A\"\n" +
    "var right = String.fromByte(255) + String.fromByte(65)\n" +
    "var values = {}\n" +
    "values[left] = 42\n" +
    "System.print(left == right)\n" +
    "System.print(Object.same(left, right))\n" +
    "System.print(values[right])\n"
  expect_core_output(source, ["true", "true", "42"])
}

///|
test "List addAll concatenation repetition and default sort work" {
  let source = "var values = [3, 1]\n" +
    "values.addAll(2..4)\n" +
    "System.print(values.sort())\n" +
    "System.print([1, 2] + (3..4))\n" +
    "System.print([1, 2] * 3)\n" +
    "System.print(\"ab\" * 3)\n"
  expect_core_output(source, [
    "[1, 2, 3, 3, 4]", "[1, 2, 3, 4]", "[1, 2, 1, 2, 1, 2]", "ababab",
  ])
}

///|
test "List custom sort invokes a two argument comparer" {
  let source = "var values = [1, 4, 2, 3]\n" +
    "values.sort(Fn.new { |a, b| a > b })\n" +
    "values\n"
  match @moonwren.run(source) {
    @moonwren.ProgramCompleted(value, _) => assert_eq(value.to_text(), "<list>")
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  expect_core_output(source + "System.print(values)\n", ["[4, 3, 2, 1]"])
}

///|
test "Sequence predicates aggregation and joining work on builtins" {
  let source = "var even = Fn.new { |n| n % 2 == 0 }\n" +
    "System.print((1..4).all(even))\n" +
    "System.print((1..4).any(even))\n" +
    "System.print((1..6).count(even))\n" +
    "System.print((1..4).contains(3))\n" +
    "System.print((1..4).join(\"-\"))\n" +
    "System.print((1..4).reduce(Fn.new { |a, b| a + b }))\n" +
    "System.print((1..4).reduce(10, Fn.new { |a, b| a + b }))\n"
  expect_core_output(source, [
    "false", "true", "3", "true", "1-2-3-4", "10", "20",
  ])
}

///|
test "Sequence predicates and emptiness short circuit infinite sources" {
  let source = "var numbers = 0..Num.infinity\n" +
    "System.print(numbers.all(Fn.new { |n| n < 0 }))\n" +
    "System.print(numbers.any(Fn.new { |n| n == 0 }))\n" +
    "System.print(numbers.contains(0))\n" +
    "System.print(numbers.isEmpty)\n"
  expect_core_output(source, ["false", "true", "true", "false"])
}

///|
test "lazy Sequence map observes later source mutations" {
  let source = "var values = [1, 2]\n" +
    "var doubled = values.map(Fn.new { |n| n * 2 })\n" +
    "values.add(3)\n" +
    "System.print(doubled.toList)\n"
  expect_core_output(source, ["[2, 4, 6]"])
}

///|
test "lazy Sequence where skip and take compose" {
  let source = "var selected = (1..10).where(Fn.new { |n| n % 2 == 0 }).skip(1).take(3)\n" +
    "System.print(selected.toList)\n" +
    "System.print(selected.count)\n" +
    "System.print([].isEmpty)\n"
  expect_core_output(source, ["[4, 6, 8]", "3", "true"])
}

///|
test "Sequence each runs callbacks in iteration order" {
  let source = "[1, 2, 3].each(Fn.new { |n| System.print(n) })\n"
  expect_core_output(source, ["1", "2", "3"])
}

///|
test "Map iteration exposes MapEntry key value and text" {
  let source = "var entries = {\"a\": 1, \"b\": 2}.toList\n" +
    "System.print(entries[0].key)\n" +
    "System.print(entries[0].value)\n" +
    "System.print(entries[1])\n"
  expect_core_output(source, ["a", "1", "b:2"])
}

///|
test "System write and aggregate output preserve line boundaries" {
  let source = "System.write(\"a\")\n" +
    "System.writeAll([\"b\", 3])\n" +
    "System.print(\"c\")\n" +
    "System.printAll([1, 2, 3])\n" +
    "System.gc()\n"
  expect_core_output(source, ["ab3c", "123"])
}

///|
test "System exposes class metadata" {
  let source = "System.print(System.name)\n" +
    "System.print(System.type.name)\n" +
    "System.print(System.supertype.name)\n"
  expect_core_output(source, ["System", "Class", "Object"])
}

///|
test "System clock is a non-negative monotonic duration" {
  expect_core_output(
    "System.print(System.clock >= 0)\nSystem.print(System.clock >= 0)\n",
    ["true", "true"],
  )
}

///|
test "string views expose their Wren core classes" {
  let source = "var text = \"Aé\"\n" +
    "System.print(text.bytes is StringByteSequence)\n" +
    "System.print(text.codePoints is StringCodePointSequence)\n" +
    "System.print(text.bytes is Sequence)\n" +
    "System.print(StringByteSequence.supertype.name)\n"
  expect_core_output(source, ["true", "true", "true", "Sequence"])
}

///|
test "Num.fromString handles extreme exponents without unbounded work" {
  let source = "System.print(Num.fromString(\"0e999999999999999999\"))\n" +
    "System.print(Num.fromString(\"1e-999999999999999999\"))\n" +
    "System.print(Num.fromString(\"1e999999999999999999\").isInfinity)\n"
  expect_core_output(source, ["0", "0", "true"])
}

///|
test "Sequence reduce rejects an empty unseeded sequence" {
  match @moonwren.run("[].reduce(Fn.new { |a, b| a + b })\n") {
    @moonwren.ProgramCompleted(_, _) => fail("empty reduce should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}

///|
test "Sequence take validates non-negative integral counts" {
  match @moonwren.run("[1, 2].take(-1)\n") {
    @moonwren.ProgramCompleted(_, _) => fail("negative take should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidOperand)
  }
}
