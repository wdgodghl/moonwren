var sequence = Fn.new { |values|
  return values.map { |value|
    System.print("before %(value)")
    var resumed = Fiber.yield(value)
    System.print("after [%(resumed)]")
    return resumed
  }
}

var joined = Fiber.new { sequence.call([1, 2]).join(",") }
System.print(joined.call())
System.print(joined.call(""))
System.print(joined.call("two"))

var found = Fiber.new { sequence.call([1, 2, 3]).contains(20) }
System.print(found.call())
System.print(found.call(10))
System.print(found.call(20))

var missing = Fiber.new { sequence.call([1]).contains(20) }
System.print(missing.call())
System.print(missing.call(10))

var counted = Fiber.new { sequence.call([1, 2]).count }
System.print(counted.call())
System.print(counted.call(null))
System.print(counted.call(false))

var noSeparator = Fiber.new { sequence.call([1, 2]).join() }
System.print(noSeparator.call())
System.print(noSeparator.call("a"))
System.print(noSeparator.call("b"))

var empty = Fiber.new {
  var values = sequence.call([])
  var text = values.join(",")
  System.print("[%(text)]")
  System.print(values.contains(null))
  System.print(values.count)
}
empty.call()
