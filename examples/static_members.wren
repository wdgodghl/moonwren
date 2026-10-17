class Registry {
  static record(value) {
    __count = __count == null ? 1 : __count + 1
    __last = value
  }

  static count { return __count }
  static last { return __last }
}

class OffsetRegistry is Registry {
  static record(value) {
    super.record(value + 2)
  }
}

OffsetRegistry.record(40)
System.print(OffsetRegistry.last)
System.print(Registry.count)
