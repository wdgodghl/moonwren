class Counter is Sequence {
  construct new() {}
  iterate(previous) {
    if (previous == 2) return false
    var next = previous ? previous + 1 : 1
    Fiber.yield("iterate %(next)")
    return next
  }
  iteratorValue(index) {
    Fiber.yield("value %(index)")
    return index * 10
  }
}

class Custom {
  construct new() {}
  each(callback) {
    Fiber.yield("custom each")
    return callback.call(42)
  }
}

class Label {
  construct new() {}
  toString {
    Fiber.yield("format label")
    return "label"
  }
}

class Search {
  construct new() {}
  ==(value) {
    Fiber.yield("match %(value)")
    return value == 2
  }
}

class Rank {
  construct new(value) { _value = value }
  value { _value }
  <(other) {
    Fiber.yield("rank %(_value) %(other.value)")
    return _value < other.value
  }
}

var worker = Fiber.new {
  import "random" for Random
  System.print(Random.new(1).int(1))
  var values = []
  for (value in Counter.new()) values.add(value)
  System.print(values)
  System.print(Counter.new().join(","))
  System.print(Counter.new().count)
  System.print(Counter.new().isEmpty)
  values.addAll(Counter.new())
  System.print(values)
  System.print([0] + Counter.new())
  var filtered = [1, 2].where { |value|
    Fiber.yield("predicate %(value)")
    return value == 2
  }.map { |value| Fiber.abort("isEmpty must not map") }
  System.print(filtered.isEmpty)
  var positioned = [10, 20].map { |value|
    Fiber.abort("position checks must not map")
  }
  System.print(positioned.skip(1).isEmpty)
  System.print(positioned.skip(2).isEmpty)
  System.print(positioned.take(1).isEmpty)
  System.print(positioned.take(0).isEmpty)
  System.print(positioned.take(1).skip(1).isEmpty)
  var filters = [1].map { |value|
    Fiber.yield("format predicate input")
    return value
  }.where { |value| value == 1 }
  System.print(filters.isEmpty)
  var mapped = [10].map { |value|
    Fiber.yield("explicit map")
    return value + 1
  }
  var token = mapped.iterate(null)
  Fiber.yield("token ready")
  System.print(mapped.iteratorValue(token))
  var limited = mapped.take(1)
  var limitedToken = limited.iterate(null)
  Fiber.yield("limited token ready")
  System.print(limited.iteratorValue(limitedToken))
  System.print(limited.iterate(limitedToken))
  System.print(Label.new())
  System.print([Label.new(), {"first": [Label.new()]}])
  System.print("nested %([Label.new()])")
  System.print([Label.new(), Label.new()].join(","))
  System.printAll([Label.new()])
  System.print([1, 2, 3].contains(Search.new()))
  System.print(Custom.new().each { |value| value })
  Custom.new().each { |value| System.print(value + 1) }
  var sorted = [3, 1, 2]
  sorted.sort { |left, right|
    Fiber.yield("compare %(left) %(right)")
    return left < right
  }
  System.print(sorted)
  var ranks = [Rank.new(3), Rank.new(1), Rank.new(2)]
  ranks.sort()
  System.print(ranks.map { |rank| rank.value }.toList)
  System.printAll([1, 2].map { |value|
    Fiber.yield("map %(value)")
    return "value"
  })
  return "done"
}
var events = []
while (!worker.isDone) events.add(worker.call())
System.print(events.join("|"))

var seen = []
var skipped = [1, 2, 3].map { |value|
  seen.add(value)
  return value
}.skip(1)
System.print(skipped.isEmpty)
System.print(seen)
System.printAll([1, 2].map { |value|
  System.print("printAll element %(value)")
  return value
})

var ordered = [3, 1, 2]
ordered.sort { |left, right|
  System.print("compare at module scope %(left) %(right)")
  return left < right
}
System.print(ordered)
System.print(skipped.toList)
System.print(seen)
