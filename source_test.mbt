///|
test "source spans merge and retain half-open length" {
  let first : @moonwren.SourceSpan = {
    start: { offset: 2, line: 1, column: 3, },
    end: { offset: 4, line: 1, column: 5, },
  }
  let second : @moonwren.SourceSpan = {
    start: { offset: 5, line: 2, column: 1, },
    end: { offset: 9, line: 2, column: 5, },
  }
  let merged = @moonwren.SourceSpan::merge(first, second)
  assert_eq(merged.start.offset, 2)
  assert_eq(merged.end.offset, 9)
  assert_eq(merged.length(), 7)
  assert_eq(merged.line(), 1)
  assert_eq(merged.column(), 3)
}

///|
test "diagnostics render file and location" {
  let span : @moonwren.SourceSpan = {
    start: { offset: 8, line: 3, column: 4, },
    end: { offset: 9, line: 3, column: 5, },
  }
  let issue = @moonwren.Diagnostic::new(
    @moonwren.Scan,
    @moonwren.UnexpectedCharacter,
    "unexpected character",
    span,
  )
  assert_eq(
    issue.render("sample.wren"),
    "sample.wren:3:4: unexpected character",
  )
}
