///|
pub(all) enum EvaluationResult {
  EvaluationSucceeded(Value)
  EvaluationFailed(Diagnostic)
}

///|
priv struct Closure {
  parameters : Array[String]
  body : Array[Stmt]
  environment : Environment
}

///|
priv struct RuntimeContext {
  output : Array[String]
  closures : Array[Closure]
  mut steps : Int
  max_steps : Int
  mut call_depth : Int
  max_call_depth : Int
}

///|
fn RuntimeContext::new(max_steps : Int) -> RuntimeContext {
  {
    output: [],
    closures: [],
    steps: 0,
    max_steps,
    call_depth: 0,
    max_call_depth: 256,
  }
}

///|
priv enum StatementResult {
  StatementCompleted(Value)
  StatementReturned(Value, SourceSpan)
  StatementFailed(Diagnostic)
}

///|
fn RuntimeContext::step(
  self : RuntimeContext,
  span : SourceSpan,
) -> Diagnostic? {
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
fn evaluation_error(
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
) -> EvaluationResult {
  EvaluationFailed(Diagnostic::new(Runtime, code, message, span))
}

///|
fn invalid_unary(
  operator : String,
  value : Value,
  span : SourceSpan,
) -> EvaluationResult {
  evaluation_error(
    InvalidOperand,
    "operator '\{operator}' does not accept \{value.type_name()}",
    span,
  )
}

///|
fn invalid_binary(
  operator : String,
  left : Value,
  right : Value,
  span : SourceSpan,
) -> EvaluationResult {
  evaluation_error(
    InvalidOperand,
    "operator '\{operator}' does not accept \{left.type_name()} and \{right.type_name()}",
    span,
  )
}

///|
fn evaluate_unary(
  operator : UnaryOperator,
  value : Value,
  span : SourceSpan,
) -> EvaluationResult {
  match (operator, value) {
    (LogicalNot, value) => EvaluationSucceeded(Value::bool(!value.is_truthy()))
    (Negate, NumberValue(number)) => EvaluationSucceeded(Value::number(-number))
    (BitwiseNot, NumberValue(number)) =>
      EvaluationSucceeded(
        Value::number(Double::from_int(number.to_int().lnot())),
      )
    (Negate, value) => invalid_unary("-", value, span)
    (BitwiseNot, value) => invalid_unary("~", value, span)
  }
}

///|
fn number_binary(
  operator : BinaryOperator,
  left : Double,
  right : Double,
  span : SourceSpan,
) -> EvaluationResult {
  match operator {
    Add => EvaluationSucceeded(Value::number(left + right))
    Subtract => EvaluationSucceeded(Value::number(left - right))
    Multiply => EvaluationSucceeded(Value::number(left * right))
    Divide =>
      if right == 0.0 {
        evaluation_error(DivisionByZero, "division by zero", span)
      } else {
        EvaluationSucceeded(Value::number(left / right))
      }
    Remainder =>
      if right == 0.0 {
        evaluation_error(DivisionByZero, "remainder by zero", span)
      } else {
        EvaluationSucceeded(Value::number(left % right))
      }
    LessThan => EvaluationSucceeded(Value::bool(left < right))
    LessThanOrEqual => EvaluationSucceeded(Value::bool(left <= right))
    GreaterThan => EvaluationSucceeded(Value::bool(left > right))
    GreaterThanOrEqual => EvaluationSucceeded(Value::bool(left >= right))
    BitwiseAnd =>
      EvaluationSucceeded(
        Value::number(Double::from_int(left.to_int().land(right.to_int()))),
      )
    BitwiseOr =>
      EvaluationSucceeded(
        Value::number(Double::from_int(left.to_int().lor(right.to_int()))),
      )
    BitwiseXor =>
      EvaluationSucceeded(
        Value::number(Double::from_int(left.to_int().lxor(right.to_int()))),
      )
    ShiftLeft =>
      EvaluationSucceeded(
        Value::number(Double::from_int(left.to_int() << right.to_int())),
      )
    ShiftRight =>
      EvaluationSucceeded(
        Value::number(Double::from_int(left.to_int() >> right.to_int())),
      )
    _ => invalid_binary("binary", NumberValue(left), NumberValue(right), span)
  }
}

///|
fn evaluate_binary_values(
  operator : BinaryOperator,
  left : Value,
  right : Value,
  span : SourceSpan,
) -> EvaluationResult {
  match operator {
    EqualTo => EvaluationSucceeded(Value::bool(left == right))
    NotEqualTo => EvaluationSucceeded(Value::bool(left != right))
    Add =>
      match (left, right) {
        (NumberValue(left), NumberValue(right)) =>
          number_binary(Add, left, right, span)
        (StringValue(left), StringValue(right)) =>
          EvaluationSucceeded(Value::string(left + right))
        _ => invalid_binary("+", left, right, span)
      }
    InclusiveRange | ExclusiveRange =>
      match (left, right) {
        (NumberValue(from), NumberValue(to)) =>
          EvaluationSucceeded(
            Value::range(from, to, operator == InclusiveRange),
          )
        _ => invalid_binary("range", left, right, span)
      }
    IsType =>
      evaluation_error(
        UnsupportedFeature,
        "runtime type expressions are not implemented yet",
        span,
      )
    _ =>
      match (left, right) {
        (NumberValue(left), NumberValue(right)) =>
          number_binary(operator, left, right, span)
        _ => invalid_binary("binary", left, right, span)
      }
  }
}

///|
fn invoke_function(
  identifier : Int,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier < 0 || identifier >= context.closures.length() {
    return evaluation_error(
      UndefinedMethod,
      "function is not available in this runtime",
      span,
    )
  }
  let closure = context.closures[identifier]
  if arguments.length() < closure.parameters.length() {
    return evaluation_error(
      InvalidArity,
      "function expects at least \{closure.parameters.length()} arguments, received \{arguments.length()}",
      span,
    )
  }
  if context.call_depth >= context.max_call_depth {
    return evaluation_error(
      CallStackLimit,
      "function call depth limit exceeded",
      span,
    )
  }
  let environment = closure.environment.capture()
  environment.push_scope()
  for index = 0; index < closure.parameters.length(); index = index + 1 {
    ignore(environment.bind(closure.parameters[index], arguments[index]))
  }
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(closure.body, environment, context)
  context.call_depth = context.call_depth - 1
  ignore(environment.pop_scope())
  match result {
    StatementCompleted(value) | StatementReturned(value, _) =>
      EvaluationSucceeded(value)
    StatementFailed(issue) => EvaluationFailed(issue)
  }
}

///|
fn invoke_method(
  receiver : Value,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match receiver {
    SystemValue =>
      if name == "print" {
        if arguments.length() == 0 {
          context.output.push("")
          EvaluationSucceeded(Value::null())
        } else if arguments.length() == 1 {
          let value = arguments[0]
          context.output.push(value.to_text())
          EvaluationSucceeded(value)
        } else {
          evaluation_error(
            InvalidArity,
            "System.print expects zero or one argument, received \{arguments.length()}",
            span,
          )
        }
      } else {
        evaluation_error(
          UndefinedMethod,
          "System does not implement method '\{name}'",
          span,
        )
      }
    FunctionValue(identifier) =>
      if name == "call" {
        invoke_function(identifier, arguments, span, context)
      } else {
        evaluation_error(
          UndefinedMethod,
          "Fn does not implement method '\{name}'",
          span,
        )
      }
    value =>
      evaluation_error(
        UndefinedMethod,
        "\{value.type_name()} does not implement method '\{name}'",
        span,
      )
  }
}

///|
fn read_property(
  receiver : Value,
  name : String,
  span : SourceSpan,
) -> EvaluationResult {
  if name == "toString" {
    return EvaluationSucceeded(Value::string(receiver.to_text()))
  }
  match receiver {
    RangeValue(from, to, inclusive) =>
      match name {
        "from" => EvaluationSucceeded(Value::number(from))
        "to" => EvaluationSucceeded(Value::number(to))
        "min" =>
          EvaluationSucceeded(Value::number(if from < to { from } else { to }))
        "max" =>
          EvaluationSucceeded(Value::number(if from > to { from } else { to }))
        "isInclusive" => EvaluationSucceeded(Value::bool(inclusive))
        _ =>
          evaluation_error(
            UndefinedMethod,
            "Range does not implement getter '\{name}'",
            span,
          )
      }
    value =>
      evaluation_error(
        UndefinedMethod,
        "\{value.type_name()} does not implement getter '\{name}'",
        span,
      )
  }
}

///|
fn evaluate_expression_in(
  expression : Expr,
  environment : Environment,
  context : RuntimeContext,
) -> EvaluationResult {
  match expression {
    Literal(value, _) => EvaluationSucceeded(value)
    Variable(name, span) =>
      match environment.get(name) {
        Some(value) => EvaluationSucceeded(value)
        None =>
          evaluation_error(
            UndefinedVariable,
            "undefined variable '\{name}'",
            span,
          )
      }
    Assign(name, value, span) =>
      match evaluate_expression_in(value, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          if environment.assign(name, value) {
            EvaluationSucceeded(value)
          } else {
            evaluation_error(
              UndefinedVariable,
              "undefined variable '\{name}'",
              span,
            )
          }
      }
    PropertyGet(receiver, name, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) => read_property(receiver, name, span)
      }
    MethodCall(receiver, name, arguments, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) => {
          let values : Array[Value] = []
          for argument in arguments {
            match evaluate_expression_in(argument, environment, context) {
              EvaluationFailed(issue) => return EvaluationFailed(issue)
              EvaluationSucceeded(value) => values.push(value)
            }
          }
          invoke_method(receiver, name, values, span, context)
        }
      }
    FunctionLiteral(parameters, body, _) => {
      let identifier = context.closures.length()
      context.closures.push({
        parameters,
        body,
        environment: environment.capture(),
      })
      EvaluationSucceeded(Value::function(identifier))
    }
    Grouping(inner, _) => evaluate_expression_in(inner, environment, context)
    Unary(operator, right, span) =>
      match evaluate_expression_in(right, environment, context) {
        EvaluationSucceeded(value) => evaluate_unary(operator, value, span)
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, LogicalAnd, right, _) =>
      match evaluate_expression_in(left, environment, context) {
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            evaluate_expression_in(right, environment, context)
          } else {
            EvaluationSucceeded(value)
          }
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, LogicalOr, right, _) =>
      match evaluate_expression_in(left, environment, context) {
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            EvaluationSucceeded(value)
          } else {
            evaluate_expression_in(right, environment, context)
          }
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, operator, right, span) =>
      match evaluate_expression_in(left, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(left_value) =>
          match evaluate_expression_in(right, environment, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(right_value) =>
              evaluate_binary_values(operator, left_value, right_value, span)
          }
      }
    Conditional(condition, then_branch, else_branch, _) =>
      match evaluate_expression_in(condition, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            evaluate_expression_in(then_branch, environment, context)
          } else {
            evaluate_expression_in(else_branch, environment, context)
          }
      }
  }
}

///|
fn execute_statements_in(
  statements : Array[Stmt],
  environment : Environment,
  context : RuntimeContext,
) -> StatementResult {
  let mut last = Value::null()
  for statement in statements {
    match execute_statement_in(statement, environment, context) {
      StatementCompleted(value) => last = value
      StatementReturned(value, span) => return StatementReturned(value, span)
      StatementFailed(issue) => return StatementFailed(issue)
    }
  }
  StatementCompleted(last)
}

///|
fn execute_block_in(
  statements : Array[Stmt],
  environment : Environment,
  context : RuntimeContext,
) -> StatementResult {
  environment.push_scope()
  let result = execute_statements_in(statements, environment, context)
  ignore(environment.pop_scope())
  result
}

///|
fn execute_range_for_in(
  name : String,
  from : Double,
  to : Double,
  inclusive : Bool,
  body : Stmt,
  environment : Environment,
  context : RuntimeContext,
) -> StatementResult {
  environment.push_scope()
  ignore(environment.bind(name, Value::number(from)))
  let step = if from <= to { 1.0 } else { -1.0 }
  let mut current = from
  let mut last = Value::null()
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
    ignore(environment.assign(name, Value::number(current)))
    match execute_statement_in(body, environment, context) {
      StatementCompleted(value) => last = value
      StatementReturned(value, span) => {
        ignore(environment.pop_scope())
        return StatementReturned(value, span)
      }
      StatementFailed(issue) => {
        ignore(environment.pop_scope())
        return StatementFailed(issue)
      }
    }
    current = current + step
  }
  ignore(environment.pop_scope())
  StatementCompleted(last)
}

///|
fn execute_statement_in(
  statement : Stmt,
  environment : Environment,
  context : RuntimeContext,
) -> StatementResult {
  match context.step(statement.span()) {
    Some(issue) => return StatementFailed(issue)
    None => ()
  }
  match statement {
    ExpressionStatement(expression, _) =>
      match evaluate_expression_in(expression, environment, context) {
        EvaluationSucceeded(value) => StatementCompleted(value)
        EvaluationFailed(issue) => StatementFailed(issue)
      }
    VariableStatement(name, initializer, span) => {
      if !environment.bind(name, Value::null()) {
        return StatementFailed(
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
          match evaluate_expression_in(expression, environment, context) {
            EvaluationSucceeded(value) => value
            EvaluationFailed(issue) => return StatementFailed(issue)
          }
      }
      ignore(environment.assign(name, value))
      StatementCompleted(value)
    }
    BlockStatement(statements, _) =>
      execute_block_in(statements, environment, context)
    IfStatement(condition, then_branch, else_branch, _) =>
      match evaluate_expression_in(condition, environment, context) {
        EvaluationFailed(issue) => StatementFailed(issue)
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            execute_statement_in(then_branch, environment, context)
          } else {
            match else_branch {
              Some(branch) => execute_statement_in(branch, environment, context)
              None => StatementCompleted(Value::null())
            }
          }
      }
    WhileStatement(condition, body, _) => {
      let mut last = Value::null()
      while true {
        match evaluate_expression_in(condition, environment, context) {
          EvaluationFailed(issue) => return StatementFailed(issue)
          EvaluationSucceeded(value) => if !value.is_truthy() { break }
        }
        match execute_statement_in(body, environment, context) {
          StatementCompleted(value) => last = value
          StatementReturned(value, span) =>
            return StatementReturned(value, span)
          StatementFailed(issue) => return StatementFailed(issue)
        }
      }
      StatementCompleted(last)
    }
    ForStatement(name, sequence, body, span) =>
      match evaluate_expression_in(sequence, environment, context) {
        EvaluationFailed(issue) => StatementFailed(issue)
        EvaluationSucceeded(RangeValue(from, to, inclusive)) =>
          execute_range_for_in(
            name, from, to, inclusive, body, environment, context,
          )
        EvaluationSucceeded(value) =>
          StatementFailed(
            Diagnostic::new(
              Runtime,
              InvalidOperand,
              "for loop expects a Range, received \{value.type_name()}",
              span,
            ),
          )
      }
    ReturnStatement(value, span) =>
      match value {
        None => StatementReturned(Value::null(), span)
        Some(expression) =>
          match evaluate_expression_in(expression, environment, context) {
            EvaluationSucceeded(value) => StatementReturned(value, span)
            EvaluationFailed(issue) => StatementFailed(issue)
          }
      }
  }
}

///|
/// Parse and evaluate one standalone expression.
pub fn evaluate(source : String) -> EvaluationResult {
  match parse_expression(source) {
    ExpressionParsed(expression) => {
      let environment = Environment::new()
      ignore(environment.bind("System", Value::system()))
      evaluate_expression_in(
        expression,
        environment,
        RuntimeContext::new(100000),
      )
    }
    ExpressionParseFailed(diagnostics) => EvaluationFailed(diagnostics[0])
  }
}
