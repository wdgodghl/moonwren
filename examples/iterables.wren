class Countdown {
  construct new(start) {
    _start = start
  }

  iterate(iterator) {
    if (iterator == null) return _start
    return iterator > 0 ? iterator - 1 : false
  }

  iteratorValue(iterator) {
    return iterator
  }
}

var total = 0
for (number in Countdown.new(4)) {
  total = total + number
}

var label = ""
for (character in "月亮🤣") {
  label = label + character
}

var scores = {"Ada": 40, "Lin": 42}
var names = ""
for (name in scores.keys) {
  names = names + name + " "
}

System.print(total)
System.print(label)
System.print(names)
System.print("A🤣中文"[1..2])
