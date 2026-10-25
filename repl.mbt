///|
pub(all) enum ReplResult {
  ReplAccepted(Value, Array[String])
  ReplRejected(Array[Diagnostic])
}

///|
/// A deterministic incremental console. Accepted submissions are replayed as
/// one program, so declarations and assignments remain visible while failed
/// submissions leave the session unchanged.
pub struct ReplSession {
  mut history : String
  mut prior_output_lines : Int
  max_steps : Int
}

///|
pub fn ReplSession::new(max_steps : Int) -> ReplSession {
  { history: "", prior_output_lines: 0, max_steps, }
}

///|
pub fn ReplSession::submit(self : ReplSession, source : String) -> ReplResult {
  let candidate = if self.history.length() == 0 {
    source + "\n"
  } else {
    self.history + source + "\n"
  }
  match run_with_limit(candidate, self.max_steps) {
    ProgramFailed(issues, _) => ReplRejected(issues)
    ProgramCompleted(value, output) => {
      let fresh : Array[String] = []
      for index = self.prior_output_lines
          index < output.length()
          index = index + 1 {
        fresh.push(output[index])
      }
      self.history = candidate
      self.prior_output_lines = output.length()
      ReplAccepted(value, fresh)
    }
  }
}

///|
pub fn ReplSession::reset(self : ReplSession) -> Unit {
  self.history = ""
  self.prior_output_lines = 0
}

///|
pub fn ReplSession::source(self : ReplSession) -> String {
  self.history
}
