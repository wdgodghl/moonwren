///|
fn no_foreign_modules(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
test "context-aware foreign bindings materialize nested values" {
  let binding = @moonwren.ForeignMethodBinding::new_context(
    "main",
    "Host",
    true,
    "payload()",
    fn(call) {
      if call.argument_count() != 0 {
        return @moonwren.ForeignContextAborted("unexpected arguments")
      }
      @moonwren.ForeignContextReturned(
        @moonwren.ForeignMap([
          @moonwren.ForeignOwnedMapEntry::new(
            @moonwren.ForeignString("items"),
            @moonwren.ForeignList([
              @moonwren.ForeignNumber(20.0),
              @moonwren.ForeignNumber(22.0),
            ]),
          ),
          @moonwren.ForeignOwnedMapEntry::new(
            @moonwren.ForeignString("bytes"),
            @moonwren.ForeignBytes([0xff, 0x00]),
          ),
        ]),
      )
    },
  )
  let source =
    #|class Host { foreign static payload() }
    #|var value = Host.payload()
    #|System.print(value["items"][0] + value["items"][1])
    #|System.print(value["bytes"].bytes.count)
  match
    @moonwren.run_with_foreign_methods(
      "main",
      source,
      100000,
      no_foreign_modules,
      [binding],
    ) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["42", "2"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "parser accepts foreign instance static and getter declarations" {
  let source = "class Host {\n" +
    "  foreign static add(a, b)\n" +
    "  foreign render(value)\n" +
    "  foreign version\n" +
    "}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParseFailed(issues) => fail(issues[0].message)
    @moonwren.ProgramParsed([@moonwren.ClassStatement(_, _, methods, _, _, _)]) => {
      assert_eq(methods.length(), 3)
      assert_true(methods[0].is_foreign)
      assert_true(methods[0].is_static)
      assert_true(methods[2].is_getter)
    }
    _ => fail("expected one class declaration")
  }
}

///|
test "parser marks foreign class declarations" {
  let source = "foreign class Counter {\n" +
    "  construct new(value) {}\n" +
    "  foreign increment(amount)\n" +
    "}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [@moonwren.ClassStatement("Counter", None, methods, [], true, _)]
    ) => {
      assert_eq(methods.length(), 2)
      assert_true(methods[0].is_constructor)
      assert_true(methods[1].is_foreign)
    }
    @moonwren.ProgramParseFailed(issues) => fail(issues[0].message)
    _ => fail("expected one foreign class declaration")
  }
}

///|
test "host bindings receive receiver and arguments and return values" {
  let source = "class HostMath {\n" +
    "  construct new() {}\n" +
    "  foreign static add(a, b)\n" +
    "  foreign scale(value)\n" +
    "}\n" +
    "System.print(HostMath.add(20, 22))\n" +
    "System.print(HostMath.new().scale(7))\n"
  let add = @moonwren.ForeignMethodBinding::new(
    "main",
    "HostMath",
    true,
    "add(_,_)",
    fn(_receiver, arguments) {
      match (arguments[0], arguments[1]) {
        (@moonwren.NumberValue(left), @moonwren.NumberValue(right)) =>
          @moonwren.ForeignCallSucceeded(@moonwren.Value::number(left + right))
        _ => @moonwren.ForeignCallFailed("expected two numbers")
      }
    },
  )
  let scale = @moonwren.ForeignMethodBinding::new(
    "main",
    "HostMath",
    false,
    "scale(_)",
    fn(receiver, arguments) {
      match (receiver, arguments[0]) {
        (@moonwren.InstanceValue(_), @moonwren.NumberValue(value)) =>
          @moonwren.ForeignCallSucceeded(@moonwren.Value::number(value * 3.0))
        _ => @moonwren.ForeignCallFailed("invalid receiver or argument")
      }
    },
  )
  match
    @moonwren.run_with_foreign_methods(
      "main",
      source,
      100000,
      no_foreign_modules,
      [add, scale],
    ) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["42", "21"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "foreign callback failures become structured diagnostics" {
  let source = "class Host { foreign static fail() }\nHost.fail()\n"
  let binding = @moonwren.ForeignMethodBinding::new(
    "main",
    "Host",
    true,
    "fail()",
    fn(_, _) { @moonwren.ForeignCallFailed("host rejected the call") },
  )
  match
    @moonwren.run_with_foreign_methods(
      "main",
      source,
      100000,
      no_foreign_modules,
      [binding],
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("foreign call should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ForeignCallFailed)
      assert_true(issues[0].message.contains("host rejected the call"))
    }
  }
}

///|
test "missing foreign bindings identify the full Wren signature" {
  let source = "class Host { foreign static missing(value) }\nHost.missing(1)\n"
  match
    @moonwren.run_with_foreign_methods(
      "main",
      source,
      100000,
      no_foreign_modules,
      [],
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("missing binding should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ForeignBindingMissing)
      assert_true(issues[0].message.contains("main:Host.missing(_)"))
    }
  }
}

///|
test "foreign bindings use the canonical imported module name" {
  let source = "import \"host\" for Host\nSystem.print(Host.version)\n"
  let binding = @moonwren.ForeignMethodBinding::new(
    "host.wren",
    "Host",
    true,
    "version",
    fn(_, _) { @moonwren.ForeignCallSucceeded(@moonwren.Value::string("1.0")) },
  )
  let loader = fn(_importer : String, name : String) {
    if name == "host" {
      @moonwren.ModuleLoaded(
        "host.wren", "class Host { foreign static version }\n",
      )
    } else {
      @moonwren.ModuleLoadFailed("missing module")
    }
  }
  match
    @moonwren.run_with_foreign_methods("main.wren", source, 100000, loader, [
      binding,
    ]) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["1.0"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "foreign classes allocate host handles and expose them to methods" {
  let values : Array[Double] = []
  let finalized : Array[Int] = []
  let class_binding = @moonwren.ForeignClassBinding::new(
    "main",
    "Counter",
    fn(arguments) {
      match arguments[0] {
        @moonwren.NumberValue(value) => {
          let handle = values.length()
          values.push(value)
          @moonwren.ForeignAllocationSucceeded(handle)
        }
        _ => @moonwren.ForeignAllocationFailed("start must be a number")
      }
    },
    fn(handle) { finalized.push(handle) },
  )
  let increment = @moonwren.ForeignMethodBinding::new_for_foreign_class(
    "main",
    "Counter",
    "increment(_)",
    fn(handle, arguments) {
      match arguments[0] {
        @moonwren.NumberValue(amount) => {
          values[handle] = values[handle] + amount
          @moonwren.ForeignCallSucceeded(
            @moonwren.Value::number(values[handle]),
          )
        }
        _ => @moonwren.ForeignCallFailed("amount must be a number")
      }
    },
  )
  let value = @moonwren.ForeignMethodBinding::new_for_foreign_class(
    "main",
    "Counter",
    "value",
    fn(handle, _) {
      @moonwren.ForeignCallSucceeded(@moonwren.Value::number(values[handle]))
    },
  )
  let source = "foreign class Counter {\n" +
    "  construct new(start) {}\n" +
    "  foreign increment(amount)\n" +
    "  foreign value\n" +
    "  doubled { return this.value * 2 }\n" +
    "}\n" +
    "var counter = Counter.new(20)\n" +
    "System.print(counter.increment(1))\n" +
    "System.print(counter.value)\n" +
    "System.print(counter.doubled)\n"
  match
    @moonwren.run_with_foreign_bindings(
      "main",
      source,
      100000,
      no_foreign_modules,
      [increment, value],
      [class_binding],
    ) {
    @moonwren.ProgramCompleted(_, output) => {
      assert_eq(output, ["21", "21", "42"])
      assert_eq(finalized, [0])
    }
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "foreign class binding and allocation failures are structured" {
  let source = "foreign class Resource { construct open() {} }\n"
  match
    @moonwren.run_with_foreign_bindings(
      "main",
      source,
      100000,
      no_foreign_modules,
      [],
      [],
    ) {
    @moonwren.ProgramCompleted(_, _) =>
      fail("missing class binding should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.ForeignClassBindingMissing)
  }
  let binding = @moonwren.ForeignClassBinding::new(
    "main",
    "Resource",
    fn(_) { @moonwren.ForeignAllocationFailed("resource unavailable") },
    fn(_) { () },
  )
  match
    @moonwren.run_with_foreign_bindings(
      "main",
      source + "Resource.open()\n",
      100000,
      no_foreign_modules,
      [],
      [binding],
    ) {
    @moonwren.ProgramCompleted(_, _) => fail("allocation should fail")
    @moonwren.ProgramFailed(issues, _) => {
      assert_eq(issues[0].code, @moonwren.ForeignObjectAllocationFailed)
      assert_true(issues[0].message.contains("resource unavailable"))
    }
  }
}
