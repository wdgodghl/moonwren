var payload = ["failure"]
var guarded = null
var sender = Fiber.new {
  var reply = guarded.transferError(payload)
  System.print(reply)
  return "sender done"
}
guarded = Fiber.new {
  sender.transfer()
  System.print("unreachable guarded")
}
System.print(Object.same(guarded.try(), payload))
System.print(Object.same(guarded.error, payload))
System.print(guarded.isDone)
System.print(sender.isDone)
System.print(sender.call("resumed sender"))

var root = Fiber.current
var target = Fiber.new { |input|
  System.print(input)
  root.transfer("back")
}
System.print(target.transferError(null))
