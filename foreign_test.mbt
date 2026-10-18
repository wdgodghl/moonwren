///|
fn no_foreign_modules(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
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
    @moonwren.ProgramParsed([@moonwren.ClassStatement(_, _, methods, _)]) => {
      assert_eq(methods.length(), 3)
      assert_true(methods[0].is_foreign)
      assert_true(methods[0].is_static)
      assert_true(methods[2].is_getter)
    }
    _ => fail("expected one class declaration")
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
