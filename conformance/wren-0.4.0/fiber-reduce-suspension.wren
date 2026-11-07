var worker = Fiber.new {
  var result = (1..3).reduce { |acc, number|
    System.print("before %(acc),%(number)")
    var resumed = Fiber.yield(acc + number)
    System.print("after %(resumed)")
    return resumed
  }
  return result
}

System.print(worker.call())
System.print(worker.call(30))
System.print(worker.call(300))
