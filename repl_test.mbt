///|
test "REPL keeps accepted declarations and rolls back failed input" {
  let session = @moonwren.ReplSession::new(10000)
  match session.submit("var answer = 40") {
    @moonwren.ReplAccepted(_, _) => ()
    @moonwren.ReplRejected(issues) => fail(issues[0].message)
  }
  match session.submit("answer = answer + 2\nSystem.print(answer)") {
    @moonwren.ReplAccepted(value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["42"])
    }
    @moonwren.ReplRejected(issues) => fail(issues[0].message)
  }
  let accepted_source = session.source()
  match session.submit("missing + 1") {
    @moonwren.ReplAccepted(_, _) => fail("invalid input must fail")
    @moonwren.ReplRejected(_) => ()
  }
  assert_eq(session.source(), accepted_source)
  session.reset()
  assert_eq(session.source(), "")
}
