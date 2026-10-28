///|
test "built-in optional module sources parse" {
  match parse_program(optional_random_source) {
    ProgramParsed(_) => ()
    ProgramParseFailed(issues) => fail(issues[0].render(optional_random_source))
  }
  match parse_program(optional_meta_source) {
    ProgramParsed(_) => ()
    ProgramParseFailed(issues) => fail(issues[0].render(optional_meta_source))
  }
}
