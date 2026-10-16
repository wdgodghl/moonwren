var count = 0
var next = Fn.new { count = count + 1 }

System.print(next.call())
System.print(next.call())

var add = Fn.new { |left, right| left + right }
System.print(add.call(20, 22))

var makeCounter = Fn.new {
  var local = 0
  return Fn.new {
    local = local + 1
    return local
  }
}

var counter = makeCounter.call()
System.print(counter.call())
System.print(counter.call())
