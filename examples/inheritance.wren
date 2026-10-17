class BaseCounter {
  construct new(value) {
    _value = value
  }

  value { return _value }
  increment() { _value = _value + 1 }
}

class DoubleCounter is BaseCounter {
  construct new(value) {
    super(value)
  }

  increment() {
    super.increment()
    super.increment()
  }
}

class OffsetCounter is DoubleCounter {
  construct new(value) {
    super(value)
  }

  value { return super.value + 2 }
}

var counter = OffsetCounter.new(38)
counter.increment()

System.print(counter.value)
System.print(counter is BaseCounter)
