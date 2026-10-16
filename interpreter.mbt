///|
pub(all) enum ProgramRunResult {
  ProgramCompleted(Value, Array[String])
  ProgramFailed(Array[Diagnostic], Array[String])
}

///|
priv struct Interpreter {
  environment : Environment
  context : RuntimeContext
  mut steps : Int
  max_steps : Int
}

///|
fn Interpreter::new(max_steps : Int) -> Interpreter {
  let environment = Environment::new()
  ignore(environment.bind("System", Value::system()))
  { environment, context: RuntimeContext::new(), steps: 0, max_steps, }
}

///|
fn Interpreter::step(self : Interpreter, span : SourceSpan) -> Diagnostic? {
  self.steps = self.steps + 1
  if self.steps > self.max_steps {
    Some(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "execution step limit exceeded",
        span,
      ),
    )
  } else {
    None
  }
}

///|
fn Interpreter::execute_block(
  self : Interpreter,
  statements : Array[Stmt],
) -> EvaluationResult {
  self.environment.push_scope()
  let mut result = EvaluationSucceeded(Value::null())
  for statement in statements {
    result = self.execute_statement(statement)
    match result {
      EvaluationFailed(_) => break
      EvaluationSucceeded(_) => ()
    }
  }
  ignore(self.environment.pop_scope())
  result
}

///|
fn Interpreter::execute_range_for(
  self : Interpreter,
  name : String,
  from : Double,
  to : Double,
  inclusive : Bool,
  body : Stmt,
) -> EvaluationResult {
  self.environment.push_scope()
  ignore(self.environment.bind(name, Value::number(from)))
  let step = if from <= to { 1.0 } else { -1.0 }
  let mut current = from
  let mut result = EvaluationSucceeded(Value::null())
  while (if step > 0.0 {
          if inclusive {
            current <= to
          } else {
            current < to
          }
        } else if inclusive {
          current >= to
        } else {
          current > to
        }) {
    ignore(self.environment.assign(name, Value::number(current)))
    result = self.execute_statement(body)
    match result {
      EvaluationFailed(_) => break
      EvaluationSucceeded(_) => ()
    }
    current = current + step
  }
  ignore(self.environment.pop_scope())
  result
}

///|
fn Interpreter::execute_statement(
  self : Interpreter,
  statement : Stmt,
) -> EvaluationResult {
  match self.step(statement.span()) {
    Some(issue) => return EvaluationFailed(issue)
    None => ()
  }
  match statement {
    ExpressionStatement(expression, _) =>
      evaluate_expression_in(expression, self.environment, self.context)
    VariableStatement(name, initializer, span) => {
      if !self.environment.bind(name, Value::null()) {
        return EvaluationFailed(
          Diagnostic::new(
            Runtime,
            DuplicateVariable,
            "variable '\{name}' is already declared in this scope",
            span,
          ),
        )
      }
      let value = match initializer {
        None => Value::null()
        Some(expression) =>
          match
            evaluate_expression_in(expression, self.environment, self.context) {
            EvaluationFailed(issue) => return EvaluationFailed(issue)
            EvaluationSucceeded(value) => value
          }
      }
      ignore(self.environment.assign(name, value))
      EvaluationSucceeded(value)
    }
    BlockStatement(statements, _) => self.execute_block(statements)
    IfStatement(condition, then_branch, else_branch, _) =>
      match evaluate_expression_in(condition, self.environment, self.context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            self.execute_statement(then_branch)
          } else {
            match else_branch {
              Some(branch) => self.execute_statement(branch)
              None => EvaluationSucceeded(Value::null())
            }
          }
      }
    WhileStatement(condition, body, _) => {
      let mut last = Value::null()
      while true {
        match
          evaluate_expression_in(condition, self.environment, self.context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => if !value.is_truthy() { break }
        }
        match self.execute_statement(body) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => last = value
        }
      }
      EvaluationSucceeded(last)
    }
    ForStatement(name, sequence, body, span) =>
      match evaluate_expression_in(sequence, self.environment, self.context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(RangeValue(from, to, inclusive)) =>
          self.execute_range_for(name, from, to, inclusive, body)
        EvaluationSucceeded(value) =>
          EvaluationFailed(
            Diagnostic::new(
              Runtime,
              InvalidOperand,
              "for loop expects a Range, received \{value.type_name()}",
              span,
            ),
          )
      }
  }
}

///|
fn Interpreter::execute(
  self : Interpreter,
  statements : Array[Stmt],
) -> ProgramRunResult {
  let mut last = Value::null()
  for statement in statements {
    match self.execute_statement(statement) {
      EvaluationSucceeded(value) => last = value
      EvaluationFailed(issue) =>
        return ProgramFailed([issue], self.context.output)
    }
  }
  ProgramCompleted(last, self.context.output)
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
    ProgramParsed(statements) => Interpreter::new(max_steps).execute(statements)
  }
}

///|
/// Run a source file using a conservative default step budget.
pub fn run(source : String) -> ProgramRunResult {
  run_with_limit(source, 100000)
}
