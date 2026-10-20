var worker = Fiber.new {
  (1..3).each(Fn.new { |number| Fiber.yield(number * 2) })
  return "done"
}
System.print(worker.call())
System.print(worker.call())
System.print(worker.call())
System.print(worker.call())
