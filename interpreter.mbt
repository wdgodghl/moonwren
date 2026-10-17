///|
pub(all) enum ProgramRunResult {
  ProgramCompleted(Value, Array[String])
  ProgramFailed(Array[Diagnostic], Array[String])
}

///|
/// Run a source file with a configurable guard against unbounded loops.
pub fn run_with_limit(source : String, max_steps : Int) -> ProgramRunResult {
  if max_steps <= 0 {
    return ProgramFailed(
      [
        Diagnostic::new(
          Runtime,
          ExecutionLimit,
          "execution step limit must be positive",
          SourceSpan::empty(),
        ),
      ],
      [],
    )
  }
  match parse_program(source) {
    ProgramParseFailed(diagnostics) => ProgramFailed(diagnostics, [])
    ProgramParsed(statements) => {
      let environment = Environment::new()
      ignore(environment.bind("System", Value::system()))
      let context = RuntimeContext::new(max_steps)
      match execute_statements_in(statements, environment, context) {
        StatementCompleted(value) => ProgramCompleted(value, context.output)
        StatementFailed(issue) => ProgramFailed([issue], context.output)
        StatementReturned(_, span) =>
          ProgramFailed(
            [
              Diagnostic::new(
                Runtime,
                ReturnOutsideFunction,
                "return can only be used inside a function",
                span,
              ),
            ],
            context.output,
          )
        StatementBroken(span) =>
          ProgramFailed(
            [
              Diagnostic::new(
                Runtime,
                BreakOutsideLoop,
                "break can only be used inside a loop",
                span,
              ),
            ],
            context.output,
          )
        StatementContinued(span) =>
          ProgramFailed(
            [
              Diagnostic::new(
                Runtime,
                ContinueOutsideLoop,
                "continue can only be used inside a loop",
                span,
              ),
            ],
            context.output,
          )
      }
    }
  }
}

///|
/// Run a source file using a conservative default step budget.
pub fn run(source : String) -> ProgramRunResult {
  run_with_limit(source, 100000)
}
