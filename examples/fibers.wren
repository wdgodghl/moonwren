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

var guarded = Fiber.new {
  Fiber.abort("host operation failed")
}

System.print(guarded.try())
System.print(guarded.error)
