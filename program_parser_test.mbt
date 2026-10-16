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
