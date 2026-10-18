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
  InvalidMapKey
  ModuleNotFound
  CircularImport
  UndefinedExport
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
  source_name : String
  frames : Array[CallFrame]
}

///|
/// One caller location retained while an error unwinds through the runtime.
pub(all) struct CallFrame {
  callable : String
  source_name : String
  span : SourceSpan
} derive(Eq, Debug)

///|
pub extend CallFrame with Eq::{equal, not_equal}

///|
pub extend CallFrame with Debug::{to_repr}

///|
pub fn CallFrame::new(
  callable : String,
  source_name : String,
  span : SourceSpan,
) -> CallFrame {
  { callable, source_name, span, }
}

///|
pub fn Diagnostic::new(
  phase : DiagnosticPhase,
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
) -> Diagnostic {
  { phase, code, message, span, source_name: "", frames: [], }
}

///|
pub fn Diagnostic::with_source(
  self : Diagnostic,
  source_name : String,
) -> Diagnostic {
  {
    phase: self.phase,
    code: self.code,
    message: self.message,
    span: self.span,
    source_name: if self.source_name == "" {
      source_name
    } else {
      self.source_name
    },
    frames: self.frames,
  }
}

///|
pub fn Diagnostic::with_frame(
  self : Diagnostic,
  frame : CallFrame,
) -> Diagnostic {
  self.frames.push(frame)
  self
}

///|
pub fn Diagnostic::render(self : Diagnostic, source_name : String) -> String {
  let origin = if self.source_name == "" {
    source_name
  } else {
    self.source_name
  }
  let mut rendered = "\{origin}:\{self.span.line()}:\{self.span.column()}: \{self.message}"
  for frame in self.frames {
    let frame_source = if frame.source_name == "" {
      source_name
    } else {
      frame.source_name
    }
    rendered = rendered +
      "\n  at \{frame.callable} (\{frame_source}:\{frame.span.line()}:\{frame.span.column()})"
  }
  rendered
}
