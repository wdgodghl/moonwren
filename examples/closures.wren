var count = 0
var next = Fn.new { count = count + 1 }

System.print(next.call())
System.print(next.call())

var add = Fn.new { |left, right| left + right }
System.print(add.call(20, 22))
