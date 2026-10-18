///|
test "program parser handles variables and assignment" {
  match @moonwren.parse_program("var count = 1\ncount = count + 1\n") {
    @moonwren.ProgramParsed(statements) => {
      assert_eq(statements.length(), 2)
      match statements[1] {
        @moonwren.ExpressionStatement(@moonwren.Assign("count", _, _), _) => ()
        _ => fail("expected assignment statement")
      }
    }
    @moonwren.ProgramParseFailed(_) => fail("program should parse")
  }
}

///|
test "program parser handles blocks and conditionals" {
  let source = "if (true) {\n  var answer = 42\n} else {\n  var answer = 0\n}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [@moonwren.IfStatement(_, then_branch, Some(else_branch), _)]
    ) =>
      match (then_branch, else_branch) {
        (
          @moonwren.BlockStatement(then_items, _),
          @moonwren.BlockStatement(else_items, _),
        ) => {
          assert_eq(then_items.length(), 1)
          assert_eq(else_items.length(), 1)
        }
        _ => fail("expected block branches")
      }
    _ => fail("conditional program should parse")
  }
}

///|
test "program parser handles while statements" {
  match @moonwren.parse_program("while (false) {\n  1 + 2\n}\n") {
    @moonwren.ProgramParsed([@moonwren.WhileStatement(_, _, _)]) => ()
    _ => fail("while program should parse")
  }
}

///|
test "program parser handles for statements" {
  match @moonwren.parse_program("for (item in 1..3) {\n  item\n}\n") {
    @moonwren.ProgramParsed(
      [@moonwren.ForStatement("item", _, @moonwren.BlockStatement(_, _), _)]
    ) => ()
    _ => fail("for program should parse")
  }
}

///|
test "program parser requires in after a for variable" {
  match @moonwren.parse_program("for (item 1..3) item\n") {
    @moonwren.ProgramParsed(_) => fail("for program should fail")
    @moonwren.ProgramParseFailed(diagnostics) =>
      assert_eq(diagnostics[0].code, @moonwren.ExpectedToken)
  }
}

///|
test "program parser requires statement boundaries" {
  match @moonwren.parse_program("var first = 1 var second = 2") {
    @moonwren.ProgramParsed(_) => fail("program should fail")
    @moonwren.ProgramParseFailed(diagnostics) =>
      assert_eq(diagnostics[0].code, @moonwren.ExpectedToken)
  }
}

///|
test "program parser recognizes classes constructors methods and getters" {
  let source = "class Point {\n" +
    "  construct new(x, y) {\n" +
    "    _x = x\n" +
    "    _y = y\n" +
    "  }\n" +
    "  sum { return _x + _y }\n" +
    "  move(dx, dy) {\n" +
    "    _x = _x + dx\n" +
    "    _y = _y + dy\n" +
    "  }\n" +
    "}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [@moonwren.ClassStatement("Point", None, declarations, false, _)]
    ) => {
      assert_eq(declarations.length(), 3)
      assert_true(declarations[0].is_constructor)
      assert_true(declarations[1].is_getter)
      assert_eq(declarations[2].parameters, ["dx", "dy"])
    }
    _ => fail("expected a class declaration")
  }
}

///|
test "program parser records superclass names and super constructor calls" {
  let source = "class Child is Parent {\n" +
    "  construct new(value) { super(value) }\n" +
    "  value { return super.value }\n" +
    "}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [
        @moonwren.ClassStatement(
          "Child",
          Some("Parent"),
          [initializer, getter],
          false,
          _
        ),
      ]
    ) => {
      match initializer.body {
        [
          @moonwren.ExpressionStatement(
            @moonwren.SuperConstructorCall([_], _),
            _
          ),
        ] => ()
        _ => fail("expected a super constructor call")
      }
      assert_true(getter.is_getter)
    }
    _ => fail("expected an inherited class declaration")
  }
}

///|
test "parser distinguishes field access and assignment" {
  match @moonwren.parse_expression("_value = _value + 1") {
    @moonwren.ExpressionParsed(
      @moonwren.FieldAssign(
        "_value",
        @moonwren.Binary(@moonwren.FieldGet("_value", _), _, _, _),
        _
      )
    ) => ()
    _ => fail("expected field assignment")
  }
}

///|
test "parser records static methods getters and fields" {
  let source = "class Registry {\n" +
    "  static put(value) { __value = value }\n" +
    "  static value { return __value }\n" +
    "}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [@moonwren.ClassStatement("Registry", None, [put, value], false, _)]
    ) => {
      assert_true(put.is_static)
      assert_true(value.is_static)
      assert_true(value.is_getter)
      match put.body {
        [
          @moonwren.ExpressionStatement(
            @moonwren.StaticFieldAssign("__value", _, _),
            _
          ),
        ] => ()
        _ => fail("expected static field assignment")
      }
    }
    _ => fail("expected static declarations")
  }
}

///|
test "program parser recognizes break and continue statements" {
  let source = "while (true) {\n  if (false) continue\n  break\n}\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [
        @moonwren.WhileStatement(
          _,
          @moonwren.BlockStatement(
            [
              @moonwren.IfStatement(_, @moonwren.ContinueStatement(_), None, _),
              @moonwren.BreakStatement(_),
            ],
            _
          ),
          _
        ),
      ]
    ) => ()
    _ => fail("expected loop control statements")
  }
}

///|
test "program parser recognizes imports and aliases" {
  let source = "import \"math\" for Calculator as Calc, pi\n"
  match @moonwren.parse_program(source) {
    @moonwren.ProgramParsed(
      [
        @moonwren.ImportStatement(
          "math",
          [
            { name: "Calculator", local_name: "Calc", },
            { name: "pi", local_name: "pi", },
          ],
          _
        ),
      ]
    ) => ()
    _ => fail("expected import declaration")
  }
}

///|
test "program parser recognizes side-effect-only imports" {
  match @moonwren.parse_program("import \"bootstrap\"\n") {
    @moonwren.ProgramParsed([@moonwren.ImportStatement("bootstrap", [], _)]) =>
      ()
    _ => fail("expected side-effect import")
  }
}

///|
test "program parser rejects malformed imports" {
  match @moonwren.parse_program("import module\n") {
    @moonwren.ProgramParsed(_) => fail("module name must be a string")
    @moonwren.ProgramParseFailed(issues) =>
      assert_eq(issues[0].code, @moonwren.ExpectedToken)
  }
  match @moonwren.parse_program("import \"math\" for value as\n") {
    @moonwren.ProgramParsed(_) => fail("alias must have a name")
    @moonwren.ProgramParseFailed(issues) =>
      assert_eq(issues[0].code, @moonwren.ExpectedToken)
  }
}
