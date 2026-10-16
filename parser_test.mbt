///|
test "parser applies multiplication before addition" {
  match @moonwren.parse_expression("1 + 2 * 3") {
    @moonwren.ExpressionParsed(expression) =>
      match expression {
        @moonwren.Binary(_, @moonwren.Add, right, _) =>
          match right {
            @moonwren.Binary(_, @moonwren.Multiply, _, _) => ()
            _ => fail("expected multiplication on the right")
          }
        _ => fail("expected addition at the root")
      }
    @moonwren.ExpressionParseFailed(_) => fail("expression should parse")
  }
}

///|
test "parser handles primitive literals" {
  match @moonwren.parse_expression("true ? \"yes\" : null") {
    @moonwren.ExpressionParsed(expression) =>
      match expression {
        @moonwren.Conditional(
          @moonwren.Literal(@moonwren.BoolValue(true), _),
          @moonwren.Literal(@moonwren.StringValue("yes"), _),
          @moonwren.Literal(@moonwren.NullValue, _),
          _
        ) => ()
        _ => fail("expected conditional literals")
      }
    @moonwren.ExpressionParseFailed(_) => fail("expression should parse")
  }
}

///|
test "parser supports hexadecimal and exponent numbers" {
  match @moonwren.parse_expression("0x10 + 2.5e2") {
    @moonwren.ExpressionParsed(expression) =>
      match expression {
        @moonwren.Binary(
          @moonwren.Literal(@moonwren.NumberValue(left), _),
          @moonwren.Add,
          @moonwren.Literal(@moonwren.NumberValue(right), _),
          _
        ) => {
          assert_eq(left, 16.0)
          assert_eq(right, 250.0)
        }
        _ => fail("expected two number literals")
      }
    @moonwren.ExpressionParseFailed(_) => fail("expression should parse")
  }
}

///|
test "parser reports a missing operand" {
  match @moonwren.parse_expression("1 +") {
    @moonwren.ExpressionParsed(_) => fail("expression should fail")
    @moonwren.ExpressionParseFailed(diagnostics) => {
      assert_eq(diagnostics.length(), 1)
      assert_eq(diagnostics[0].code, @moonwren.ExpectedExpression)
    }
  }
}

///|
test "parser accepts multiline grouped expressions" {
  match @moonwren.parse_expression("(\n  1 + 2\n)") {
    @moonwren.ExpressionParsed(@moonwren.Grouping(_, span)) => {
      assert_eq(span.start.line, 1)
      assert_eq(span.end.line, 3)
    }
    _ => fail("grouped expression should parse")
  }
}

///|
test "parser recognizes method calls and arguments" {
  match @moonwren.parse_expression("System.print(1 + 2)") {
    @moonwren.ExpressionParsed(
      @moonwren.MethodCall(
        @moonwren.Variable("System", _),
        "print",
        [@moonwren.Binary(_, @moonwren.Add, _, _)],
        span
      )
    ) => {
      assert_eq(span.start.offset, 0)
      assert_eq(span.end.offset, 19)
    }
    _ => fail("expected a method call")
  }
}

///|
test "parser supports chained and multiline method calls" {
  match @moonwren.parse_expression("value.first().second(\n  1,\n  2\n)") {
    @moonwren.ExpressionParsed(
      @moonwren.MethodCall(
        @moonwren.MethodCall(_, "first", [], _),
        "second",
        [_, _],
        _
      )
    ) => ()
    _ => fail("expected chained method calls")
  }
}

///|
test "parser recognizes getter calls" {
  match @moonwren.parse_expression("value.toString") {
    @moonwren.ExpressionParsed(
      @moonwren.PropertyGet(@moonwren.Variable("value", _), "toString", span)
    ) => assert_eq(span.end.offset, 14)
    _ => fail("expected a getter call")
  }
}

///|
test "parser chains getters after grouped expressions" {
  match @moonwren.parse_expression("(1..3).max.toString") {
    @moonwren.ExpressionParsed(
      @moonwren.PropertyGet(
        @moonwren.PropertyGet(@moonwren.Grouping(_, _), "max", _),
        "toString",
        _
      )
    ) => ()
    _ => fail("expected chained getter calls")
  }
}

///|
test "parser recognizes expression-bodied function literals" {
  match @moonwren.parse_expression("Fn.new { |left, right| left + right }") {
    @moonwren.ExpressionParsed(
      @moonwren.FunctionLiteral(
        ["left", "right"],
        @moonwren.Binary(_, @moonwren.Add, _, _),
        span
      )
    ) => {
      assert_eq(span.start.offset, 0)
      assert_eq(span.end.offset, 37)
    }
    _ => fail("expected a function literal")
  }
}

///|
test "parser supports empty function bodies" {
  match @moonwren.parse_expression("Fn.new {}") {
    @moonwren.ExpressionParsed(
      @moonwren.FunctionLiteral(
        [],
        @moonwren.Literal(@moonwren.NullValue, _),
        _
      )
    ) => ()
    _ => fail("expected an empty function literal")
  }
}
