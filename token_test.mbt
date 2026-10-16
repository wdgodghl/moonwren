///|
test "token identifies reserved words" {
  let span = @moonwren.SourceSpan::empty()
  let keyword = @moonwren.Token::new(@moonwren.VarKeyword, "var", span)
  let identifier = @moonwren.Token::new(@moonwren.Identifier, "variable", span)
  assert_true(keyword.is_keyword())
  assert_false(identifier.is_keyword())
}

///|
test "token kind equality distinguishes operator widths" {
  assert_true(@moonwren.Dot != @moonwren.DotDot)
  assert_true(@moonwren.DotDot != @moonwren.DotDotDot)
  assert_true(@moonwren.Equal != @moonwren.EqualEqual)
}
