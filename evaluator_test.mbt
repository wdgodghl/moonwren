///|
fn expect_value(source : String, expected : @moonwren.Value) -> Unit raise {
  match @moonwren.evaluate(source) {
    @moonwren.EvaluationSucceeded(value) => assert_eq(value, expected)
    @moonwren.EvaluationFailed(issue) => fail(issue.message)
  }
}

///|
test "evaluator computes arithmetic precedence" {
  expect_value("1 + 2 * 3 - 4 / 2", @moonwren.Value::number(5.0))
}

///|
test "evaluator concatenates strings" {
  expect_value("\"moon\" + \"wren\"", @moonwren.Value::string("moonwren"))
}

///|
test "evaluator short circuits logical operators" {
  expect_value("false && missing", @moonwren.Value::bool(false))
  expect_value("true || missing", @moonwren.Value::bool(true))
}

///|
test "evaluator selects conditional branch" {
  expect_value("2 > 1 ? \"yes\" : missing", @moonwren.Value::string("yes"))
}

///|
test "evaluator applies numeric bit operations" {
  expect_value("6 & 3", @moonwren.Value::number(2.0))
  expect_value("1 << 4", @moonwren.Value::number(16.0))
}

///|
test "evaluator constructs inclusive and exclusive ranges" {
  expect_value("1..3", @moonwren.Value::range(1.0, 3.0, true))
  expect_value("3...1", @moonwren.Value::range(3.0, 1.0, false))
}

///|
test "range operands must be numbers" {
  match @moonwren.evaluate("1..\"end\"") {
    @moonwren.EvaluationSucceeded(_) => fail("range should fail")
    @moonwren.EvaluationFailed(issue) =>
      assert_eq(issue.code, @moonwren.InvalidOperand)
  }
}

///|
test "evaluator reports invalid operands" {
  match @moonwren.evaluate("\"one\" - 1") {
    @moonwren.EvaluationSucceeded(_) => fail("operation should fail")
    @moonwren.EvaluationFailed(issue) => {
      assert_eq(issue.phase, @moonwren.Runtime)
      assert_eq(issue.code, @moonwren.InvalidOperand)
    }
  }
}
