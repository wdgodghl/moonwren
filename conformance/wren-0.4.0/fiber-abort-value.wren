class Marker {
  construct new() {}
  toString {
    System.print("unexpected formatting")
    return "marker"
  }
}

var payload = [Marker.new()]
var worker = Fiber.new {
  var helper = Fn.new { Fiber.abort(payload) }
  helper.call()
}
System.print(Object.same(worker.try(), payload))
System.print(Object.same(worker.error, payload))

var marker = Marker.new()
var marked = Fiber.new { Fiber.abort(marker) }
System.print(Object.same(marked.try(), marker))
System.print(Object.same(marked.error, marker))
