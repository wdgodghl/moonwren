///|
test "expression nodes retain complete source ranges" {
  let left_span : @moonwren.SourceSpan = {
    start: { offset: 0, line: 1, column: 1, },
    end: { offset: 1, line: 1, column: 2, },
  }
  let right_span : @moonwren.SourceSpan = {
    start: { offset: 4, line: 1, column: 5, },
    end: { offset: 5, line: 1, column: 6, },
  }
  let expression = @moonwren.Binary(
    @moonwren.Literal(@moonwren.Value::number(1.0), left_span),
    @moonwren.Add,
    @moonwren.Literal(@moonwren.Value::number(2.0), right_span),
    @moonwren.SourceSpan::merge(left_span, right_span),
  )
  assert_eq(expression.span().start.offset, 0)
  assert_eq(expression.span().end.offset, 5)
}
