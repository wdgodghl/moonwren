var effects = 0
var worker = Fiber.new {
  var values = (1..4).map { |number|
    effects = effects + 1
    Fiber.yield("map%(number)")
    return number * 2
  }.where { |number|
    Fiber.yield("where%(number)")
    return number > 4
  }.skip(0).take(2)
  var result = []
  for (value in values) result.add(value)
  return "%(result.join(","))|%(effects)"
}

while (!worker.isDone) System.print(worker.call())
