var worker = Fiber.new {
  var result = (1..2).map { |number|
    System.print("before %(number)")
    var resumed = Fiber.yield(number * 10)
    System.print("after %(resumed)")
    return resumed
  }.toList
  return result.join(",")
}

System.print(worker.call())
System.print(worker.call(100))
System.print(worker.call(200))
