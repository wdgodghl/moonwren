var main = Fiber.current

var worker = Fiber.new { |job|
  System.print("working on " + job)
  var answer = main.transfer("paused")
  System.print("resumed with " + answer)
  return "complete"
}

System.print(worker.transfer("index"))
System.print(worker.isDone)
System.print(worker.transfer("approval"))
System.print(worker.isDone)

var left = null
var right = null

left = Fiber.new {
  var reply = right.transfer("left to right")
  System.print(reply)
  return main.transfer("left to main")
}

right = Fiber.new { |message|
  System.print(message)
  return left.transfer("right to left")
}

System.print(left.transfer())
System.print(left.transfer("finish"))

var guarded = Fiber.new {
  Fiber.abort("host operation failed")
}

System.print(guarded.try())
System.print(guarded.error)
