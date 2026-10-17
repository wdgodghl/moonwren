///|
/// Phase that reported a diagnostic.
pub(all) enum DiagnosticPhase {
  Scan
  Parse
  Resolve
  Runtime
} derive(Eq, Debug)

///|
pub extend DiagnosticPhase with Eq::{equal, not_equal}

///|
pub extend DiagnosticPhase with Debug::{to_repr}

///|
/// Stable category for programmatic handling of failures.
pub(all) enum DiagnosticCode {
  UnexpectedCharacter
  UnterminatedString
  UnterminatedComment
  InvalidEscape
  InvalidNumber
  UnexpectedToken
  ExpectedExpression
  ExpectedToken
  DuplicateVariable
  DuplicateMethod
  InvalidSuperclass
  UndefinedVariable
  UndefinedMethod
  InvalidArity
  InvalidOperand
  InvalidIndex
  IndexOutOfBounds
  DivisionByZero
  ExecutionLimit
  CallStackLimit
  ReturnOutsideFunction
  BreakOutsideLoop
  ContinueOutsideLoop
  UnsupportedFeature
} derive(Eq, Debug)

///|
pub extend DiagnosticCode with Eq::{equal, not_equal}

///|
pub extend DiagnosticCode with Debug::{to_repr}

///|
/// Structured interpreter diagnostic carrying an actionable source span.
pub(all) struct Diagnostic {
  phase : DiagnosticPhase
  code : DiagnosticCode
  message : String
  span : SourceSpan
}

///|
pub fn Diagnostic::new(
  phase : DiagnosticPhase,
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
) -> Diagnostic {
  { phase, code, message, span, }
}

///|
pub fn Diagnostic::render(self : Diagnostic, source_name : String) -> String {
  "\{source_name}:\{self.span.line()}:\{self.span.column()}: \{self.message}"
}
