foreign class Counter {
  construct new(start) {}

  foreign increment(amount)
  foreign value

  doubled { return this.value * 2 }
}

var counter = Counter.new(20)
System.print(counter.increment(1))
System.print(counter.value)
System.print(counter.doubled)
