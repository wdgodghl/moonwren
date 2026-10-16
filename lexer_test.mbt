///|
fn kinds(result : @moonwren.ScanResult) -> Array[@moonwren.TokenKind] {
  result.tokens.map(fn(token) { token.kind })
}

///|
test "scanner recognizes declarations and operators" {
  let result = @moonwren.scan("var total = price * 2 + 1\n")
  assert_true(result.is_success())
  assert_eq(kinds(result), [
    @moonwren.VarKeyword,
    @moonwren.Identifier,
    @moonwren.Equal,
    @moonwren.Identifier,
    @moonwren.Star,
    @moonwren.Number,
    @moonwren.Plus,
    @moonwren.Number,
    @moonwren.Newline,
    @moonwren.Eof,
  ])
}

///|
test "scanner distinguishes fields and static fields" {
  let result = @moonwren.scan("_value __count ordinary")
  assert_eq(kinds(result), [
    @moonwren.Field,
    @moonwren.StaticField,
    @moonwren.Identifier,
    @moonwren.Eof,
  ])
}

///|
test "scanner handles ranges shifts and logical operators" {
  let result = @moonwren.scan("1..3 1...3 << >> && ||")
  assert_eq(kinds(result), [
    @moonwren.Number,
    @moonwren.DotDot,
    @moonwren.Number,
    @moonwren.Number,
    @moonwren.DotDotDot,
    @moonwren.Number,
    @moonwren.LessLess,
    @moonwren.GreaterGreater,
    @moonwren.AmpersandAmpersand,
    @moonwren.PipePipe,
    @moonwren.Eof,
  ])
}

///|
test "scanner tracks multiline source positions" {
  let result = @moonwren.scan("var first = 1\n  var second = 2")
  let second = result.tokens[5]
  assert_eq(second.kind, @moonwren.VarKeyword)
  assert_eq(second.span.start.line, 2)
  assert_eq(second.span.start.column, 3)
}

///|
test "scanner skips nested block comments" {
  let result = @moonwren.scan("1 /* outer /* inner */ done */ + 2")
  assert_true(result.is_success())
  assert_eq(kinds(result), [
    @moonwren.Number,
    @moonwren.Plus,
    @moonwren.Number,
    @moonwren.Eof,
  ])
}

///|
test "scanner reports unterminated strings" {
  let result = @moonwren.scan("\"missing")
  assert_false(result.is_success())
  assert_eq(result.diagnostics.length(), 1)
  assert_eq(result.diagnostics[0].code, @moonwren.UnterminatedString)
}

///|
test "scanner accepts decimal hexadecimal and exponent forms" {
  let result = @moonwren.scan("12 3.5 6e2 7.1e-3 0xff")
  assert_true(result.is_success())
  assert_eq(kinds(result), [
    @moonwren.Number,
    @moonwren.Number,
    @moonwren.Number,
    @moonwren.Number,
    @moonwren.Number,
    @moonwren.Eof,
  ])
}
