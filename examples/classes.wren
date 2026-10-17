class Point {
  construct new(x, y) {
    _x = x
    _y = y
  }

  move(dx, dy) {
    _x = _x + dx
    _y = _y + dy
  }

  sum { return _x + _y }
  self { return this }
}

var point = Point.new(10, 20)
point.move(5, 7)

System.print(point.sum)
System.print(point.self == point)
