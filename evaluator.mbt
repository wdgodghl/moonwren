///|
pub(all) enum EvaluationResult {
  EvaluationSucceeded(Value)
  EvaluationFailed(Diagnostic)
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
      evaluation_error(
        UnsupportedFeature,
        "range values are not implemented yet",
        span,
      )
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
fn invoke_method(
  receiver : Value,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  output : Array[String],
) -> EvaluationResult {
  match receiver {
    SystemValue =>
      if name == "print" {
        if arguments.length() == 0 {
          output.push("")
          EvaluationSucceeded(Value::null())
        } else if arguments.length() == 1 {
          let value = arguments[0]
          output.push(value.to_text())
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
    value =>
      evaluation_error(
        UndefinedMethod,
        "\{value.type_name()} does not implement method '\{name}'",
        span,
      )
  }
}

///|
fn evaluate_expression_in(
  expression : Expr,
  environment : Environment,
  output : Array[String],
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
      match evaluate_expression_in(value, environment, output) {
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
    MethodCall(receiver, name, arguments, span) =>
      match evaluate_expression_in(receiver, environment, output) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) => {
          let values : Array[Value] = []
          for argument in arguments {
            match evaluate_expression_in(argument, environment, output) {
              EvaluationFailed(issue) => return EvaluationFailed(issue)
              EvaluationSucceeded(value) => values.push(value)
            }
          }
          invoke_method(receiver, name, values, span, output)
        }
      }
    Grouping(inner, _) => evaluate_expression_in(inner, environment, output)
    Unary(operator, right, span) =>
      match evaluate_expression_in(right, environment, output) {
        EvaluationSucceeded(value) => evaluate_unary(operator, value, span)
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, LogicalAnd, right, _) =>
      match evaluate_expression_in(left, environment, output) {
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            evaluate_expression_in(right, environment, output)
          } else {
            EvaluationSucceeded(value)
          }
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, LogicalOr, right, _) =>
      match evaluate_expression_in(left, environment, output) {
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            EvaluationSucceeded(value)
          } else {
            evaluate_expression_in(right, environment, output)
          }
        EvaluationFailed(issue) => EvaluationFailed(issue)
      }
    Binary(left, operator, right, span) =>
      match evaluate_expression_in(left, environment, output) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(left_value) =>
          match evaluate_expression_in(right, environment, output) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(right_value) =>
              evaluate_binary_values(operator, left_value, right_value, span)
          }
      }
    Conditional(condition, then_branch, else_branch, _) =>
      match evaluate_expression_in(condition, environment, output) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          if value.is_truthy() {
            evaluate_expression_in(then_branch, environment, output)
          } else {
            evaluate_expression_in(else_branch, environment, output)
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
      evaluate_expression_in(expression, environment, [])
    }
    ExpressionParseFailed(diagnostics) => EvaluationFailed(diagnostics[0])
  }
}
