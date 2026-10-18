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
priv struct ClassDefinition {
  name : String
  superclass : Int?
  methods : Array[MethodDecl]
  environment : Environment
  static_fields : Array[InstanceField]
}

///|
priv struct ResolvedMethod {
  declaration : MethodDecl
  owner_identifier : Int
}

///|
priv struct InstanceField {
  name : String
  mut value : Value
}

///|
priv struct Instance {
  class_identifier : Int
  fields : Array[InstanceField]
}

///|
priv struct RuntimeList {
  items : Array[Value]
}

///|
priv struct RuntimeMapEntry {
  key : Value
  mut value : Value
}

///|
priv struct RuntimeMap {
  entries : Array[RuntimeMapEntry]
}

///|
/// Immutable snapshot used by Map key/value views and built-in iteration.
priv struct RuntimeSequence {
  items : Array[Value]
}

///|
priv struct RuntimeContext {
  output : Array[String]
  closures : Array[Closure]
  classes : Array[ClassDefinition]
  instances : Array[Instance]
  lists : Array[RuntimeList]
  maps : Array[RuntimeMap]
  sequences : Array[RuntimeSequence]
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
    classes: [],
    instances: [],
    lists: [],
    maps: [],
    sequences: [],
    steps: 0,
    max_steps,
    call_depth: 0,
    max_call_depth: 64,
  }
}

///|
fn RuntimeContext::new_list(
  self : RuntimeContext,
  items : Array[Value],
) -> Value {
  let identifier = self.lists.length()
  self.lists.push({ items, })
  Value::list(identifier)
}

///|
fn RuntimeContext::new_map(self : RuntimeContext) -> Value {
  let identifier = self.maps.length()
  self.maps.push({ entries: [], })
  Value::map(identifier)
}

///|
fn RuntimeContext::new_sequence(
  self : RuntimeContext,
  items : Array[Value],
) -> Value {
  let identifier = self.sequences.length()
  self.sequences.push({ items, })
  Value::sequence(identifier)
}

///|
fn find_map_key(entries : Array[RuntimeMapEntry], key : Value) -> Int? {
  for index = 0; index < entries.length(); index = index + 1 {
    if entries[index].key == key {
      return Some(index)
    }
  }
  None
}

///|
fn is_valid_map_key(value : Value) -> Bool {
  match value {
    NullValue
    | BoolValue(_)
    | NumberValue(_)
    | StringValue(_)
    | RangeValue(_, _, _)
    | ClassValue(_) => true
    _ => false
  }
}

///|
fn invalid_map_key(value : Value, span : SourceSpan) -> EvaluationResult {
  evaluation_error(
    InvalidMapKey,
    "Map keys must be immutable values, received \{value.type_name()}",
    span,
  )
}

///|
fn RuntimeContext::set_map_entry(
  self : RuntimeContext,
  identifier : Int,
  key : Value,
  value : Value,
) -> Bool {
  if identifier < 0 || identifier >= self.maps.length() {
    return false
  }
  let entries = self.maps[identifier].entries
  match find_map_key(entries, key) {
    Some(index) => entries[index].value = value
    None => entries.push({ key, value, })
  }
  true
}

///|
fn runtime_value_to_text(
  value : Value,
  context : RuntimeContext,
  depth : Int,
) -> String {
  if depth >= 8 {
    return match value {
      ListValue(_) => "[...]"
      MapValue(_) => "{...}"
      SequenceValue(_) => "(...)"
      _ => value.to_text()
    }
  }
  match value {
    ListValue(identifier) =>
      if identifier < 0 || identifier >= context.lists.length() {
        "<list>"
      } else {
        let items = context.lists[identifier].items
        let mut text = "["
        for index = 0; index < items.length(); index = index + 1 {
          if index > 0 {
            text = text + ", "
          }
          text = text + runtime_value_to_text(items[index], context, depth + 1)
        }
        text + "]"
      }
    MapValue(identifier) =>
      if identifier < 0 || identifier >= context.maps.length() {
        "<map>"
      } else {
        let entries = context.maps[identifier].entries
        let mut text = "{"
        for index = 0; index < entries.length(); index = index + 1 {
          if index > 0 {
            text = text + ", "
          }
          text = text +
            runtime_value_to_text(entries[index].key, context, depth + 1) +
            ": " +
            runtime_value_to_text(entries[index].value, context, depth + 1)
        }
        text + "}"
      }
    SequenceValue(identifier) =>
      if identifier < 0 || identifier >= context.sequences.length() {
        "<sequence>"
      } else {
        let items = context.sequences[identifier].items
        let mut text = "("
        for index = 0; index < items.length(); index = index + 1 {
          if index > 0 {
            text = text + ", "
          }
          text = text + runtime_value_to_text(items[index], context, depth + 1)
        }
        text + ")"
      }
    _ => value.to_text()
  }
}

///|
fn RuntimeContext::get_instance_field(
  self : RuntimeContext,
  identifier : Int,
  name : String,
) -> Value? {
  if identifier < 0 || identifier >= self.instances.length() {
    return None
  }
  for field in self.instances[identifier].fields {
    if field.name == name {
      return Some(field.value)
    }
  }
  Some(Value::null())
}

///|
fn RuntimeContext::set_instance_field(
  self : RuntimeContext,
  identifier : Int,
  name : String,
  value : Value,
) -> Bool {
  if identifier < 0 || identifier >= self.instances.length() {
    return false
  }
  let fields = self.instances[identifier].fields
  for field in fields {
    if field.name == name {
      field.value = value
      return true
    }
  }
  fields.push({ name, value, })
  true
}

///|
fn RuntimeContext::get_static_field(
  self : RuntimeContext,
  class_identifier : Int,
  name : String,
) -> Value? {
  if class_identifier < 0 || class_identifier >= self.classes.length() {
    return None
  }
  for field in self.classes[class_identifier].static_fields {
    if field.name == name {
      return Some(field.value)
    }
  }
  Some(Value::null())
}

///|
fn RuntimeContext::set_static_field(
  self : RuntimeContext,
  class_identifier : Int,
  name : String,
  value : Value,
) -> Bool {
  if class_identifier < 0 || class_identifier >= self.classes.length() {
    return false
  }
  let fields = self.classes[class_identifier].static_fields
  for field in fields {
    if field.name == name {
      field.value = value
      return true
    }
  }
  fields.push({ name, value, })
  true
}

///|
priv enum StatementResult {
  StatementCompleted(Value)
  StatementReturned(Value, SourceSpan)
  StatementBroken(SourceSpan)
  StatementContinued(SourceSpan)
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
fn class_is_subclass(
  context : RuntimeContext,
  candidate : Int,
  target : Int,
) -> Bool {
  let mut current = Some(candidate)
  while true {
    match current {
      None => return false
      Some(identifier) => {
        if identifier == target {
          return true
        }
        if identifier < 0 || identifier >= context.classes.length() {
          return false
        }
        current = context.classes[identifier].superclass
      }
    }
  }
  false
}

///|
fn evaluate_is_type(
  value : Value,
  type_value : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match type_value {
    ClassValue(target) =>
      match value {
        InstanceValue(identifier) =>
          if identifier < 0 || identifier >= context.instances.length() {
            EvaluationSucceeded(Value::bool(false))
          } else {
            EvaluationSucceeded(
              Value::bool(
                class_is_subclass(
                  context,
                  context.instances[identifier].class_identifier,
                  target,
                ),
              ),
            )
          }
        ClassValue(candidate) =>
          EvaluationSucceeded(
            Value::bool(class_is_subclass(context, candidate, target)),
          )
        _ => EvaluationSucceeded(Value::bool(false))
      }
    value =>
      evaluation_error(
        InvalidOperand,
        "right operand of 'is' must be a Class, received \{value.type_name()}",
        span,
      )
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
    StatementBroken(span) =>
      evaluation_error(
        BreakOutsideLoop,
        "break cannot cross a function boundary",
        span,
      )
    StatementContinued(span) =>
      evaluation_error(
        ContinueOutsideLoop,
        "continue cannot cross a function boundary",
        span,
      )
    StatementFailed(issue) => EvaluationFailed(issue)
  }
}

///|
fn find_method_in_class(
  context : RuntimeContext,
  class_identifier : Int,
  name : String,
  arity : Int,
  is_constructor : Bool,
  is_getter : Bool,
  is_static : Bool,
) -> ResolvedMethod? {
  if class_identifier < 0 || class_identifier >= context.classes.length() {
    return None
  }
  let class_definition = context.classes[class_identifier]
  for declaration in class_definition.methods {
    if declaration.name == name &&
      declaration.parameters.length() == arity &&
      declaration.is_constructor == is_constructor &&
      declaration.is_getter == is_getter &&
      declaration.is_static == is_static {
      return Some({ declaration, owner_identifier: class_identifier, })
    }
  }
  if !is_constructor {
    match class_definition.superclass {
      Some(superclass) =>
        return find_method_in_class(
          context, superclass, name, arity, false, is_getter, is_static,
        )
      None => ()
    }
  }
  None
}

///|
fn invoke_user_method(
  instance_identifier : Int,
  resolved : ResolvedMethod,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if instance_identifier < 0 ||
    instance_identifier >= context.instances.length() {
    return evaluation_error(
      UndefinedMethod,
      "instance is not available in this runtime",
      span,
    )
  }
  if context.call_depth >= context.max_call_depth {
    return evaluation_error(
      CallStackLimit,
      "method call depth limit exceeded",
      span,
    )
  }
  if resolved.owner_identifier < 0 ||
    resolved.owner_identifier >= context.classes.length() {
    return evaluation_error(
      UndefinedMethod,
      "instance class is not available in this runtime",
      span,
    )
  }
  let declaration = resolved.declaration
  let owner = context.classes[resolved.owner_identifier]
  let environment = owner.environment.capture()
  environment.push_scope()
  ignore(environment.bind("this", Value::instance(instance_identifier)))
  match owner.superclass {
    Some(superclass) =>
      ignore(
        environment.bind(
          "$super",
          SuperValue(
            superclass,
            instance_identifier,
            if declaration.is_constructor {
              declaration.name
            } else {
              ""
            },
          ),
        ),
      )
    None => ()
  }
  for index = 0; index < declaration.parameters.length(); index = index + 1 {
    ignore(environment.bind(declaration.parameters[index], arguments[index]))
  }
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(declaration.body, environment, context)
  context.call_depth = context.call_depth - 1
  ignore(environment.pop_scope())
  match result {
    StatementCompleted(value) | StatementReturned(value, _) =>
      EvaluationSucceeded(value)
    StatementBroken(span) =>
      evaluation_error(
        BreakOutsideLoop,
        "break cannot cross a method boundary",
        span,
      )
    StatementContinued(span) =>
      evaluation_error(
        ContinueOutsideLoop,
        "continue cannot cross a method boundary",
        span,
      )
    StatementFailed(issue) => EvaluationFailed(issue)
  }
}

///|
fn invoke_static_method(
  receiver_class : Int,
  resolved : ResolvedMethod,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if receiver_class < 0 ||
    receiver_class >= context.classes.length() ||
    resolved.owner_identifier < 0 ||
    resolved.owner_identifier >= context.classes.length() {
    return evaluation_error(
      UndefinedMethod,
      "class is not available in this runtime",
      span,
    )
  }
  if context.call_depth >= context.max_call_depth {
    return evaluation_error(
      CallStackLimit,
      "static method call depth limit exceeded",
      span,
    )
  }
  let declaration = resolved.declaration
  let owner = context.classes[resolved.owner_identifier]
  let environment = owner.environment.capture()
  environment.push_scope()
  ignore(environment.bind("this", Value::class_value(receiver_class)))
  ignore(
    environment.bind("$class", Value::class_value(resolved.owner_identifier)),
  )
  match owner.superclass {
    Some(superclass) =>
      ignore(
        environment.bind("$super", SuperClassValue(superclass, receiver_class)),
      )
    None => ()
  }
  for index = 0; index < declaration.parameters.length(); index = index + 1 {
    ignore(environment.bind(declaration.parameters[index], arguments[index]))
  }
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(declaration.body, environment, context)
  context.call_depth = context.call_depth - 1
  ignore(environment.pop_scope())
  match result {
    StatementCompleted(value) | StatementReturned(value, _) =>
      EvaluationSucceeded(value)
    StatementBroken(span) =>
      evaluation_error(
        BreakOutsideLoop,
        "break cannot cross a method boundary",
        span,
      )
    StatementContinued(span) =>
      evaluation_error(
        ContinueOutsideLoop,
        "continue cannot cross a method boundary",
        span,
      )
    StatementFailed(issue) => EvaluationFailed(issue)
  }
}

///|
fn construct_instance(
  class_identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if class_identifier < 0 || class_identifier >= context.classes.length() {
    return evaluation_error(
      UndefinedMethod,
      "class is not available in this runtime",
      span,
    )
  }
  let class_definition = context.classes[class_identifier]
  match
    find_method_in_class(
      context,
      class_identifier,
      name,
      arguments.length(),
      true,
      false,
      false,
    ) {
    None =>
      evaluation_error(
        UndefinedMethod,
        "class '\{class_definition.name}' does not implement constructor '\{name}' with \{arguments.length()} arguments",
        span,
      )
    Some(resolved) => {
      let instance_identifier = context.instances.length()
      context.instances.push({ class_identifier, fields: [], })
      match
        invoke_user_method(
          instance_identifier, resolved, arguments, span, context,
        ) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(_) =>
          EvaluationSucceeded(Value::instance(instance_identifier))
      }
    }
  }
}

///|
fn invoke_super_constructor(
  superclass : Int,
  instance_identifier : Int,
  constructor_name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if constructor_name == "" {
    return evaluation_error(
      UndefinedMethod,
      "superclass constructors can only be called from a constructor",
      span,
    )
  }
  match
    find_method_in_class(
      context,
      superclass,
      constructor_name,
      arguments.length(),
      true,
      false,
      false,
    ) {
    Some(resolved) =>
      match
        invoke_user_method(
          instance_identifier, resolved, arguments, span, context,
        ) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(_) =>
          EvaluationSucceeded(Value::instance(instance_identifier))
      }
    None =>
      evaluation_error(
        UndefinedMethod,
        "superclass does not implement constructor '\{constructor_name}' with \{arguments.length()} arguments",
        span,
      )
  }
}

///|
fn invoke_instance_method(
  instance_identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if instance_identifier < 0 ||
    instance_identifier >= context.instances.length() {
    return evaluation_error(
      UndefinedMethod,
      "instance is not available in this runtime",
      span,
    )
  }
  let class_identifier = context.instances[instance_identifier].class_identifier
  let class_definition = context.classes[class_identifier]
  match
    find_method_in_class(
      context,
      class_identifier,
      name,
      arguments.length(),
      false,
      false,
      false,
    ) {
    Some(resolved) =>
      invoke_user_method(
        instance_identifier, resolved, arguments, span, context,
      )
    None =>
      evaluation_error(
        UndefinedMethod,
        "\{class_definition.name} does not implement method '\{name}' with \{arguments.length()} arguments",
        span,
      )
  }
}

///|
priv enum CollectionIndexResult {
  CollectionIndexSucceeded(Int)
  CollectionIndexFailed(Diagnostic)
}

///|
fn collection_index(
  value : Value,
  length : Int,
  allow_end : Bool,
  span : SourceSpan,
) -> CollectionIndexResult {
  match value {
    NumberValue(number) => {
      let raw_index = number.to_int()
      let index = if raw_index < 0 { raw_index + length } else { raw_index }
      if Double::from_int(raw_index) != number {
        CollectionIndexFailed(
          Diagnostic::new(
            Runtime,
            InvalidIndex,
            "list index must be an integer",
            span,
          ),
        )
      } else if index < 0 ||
        (if allow_end { index > length } else { index >= length }) {
        CollectionIndexFailed(
          Diagnostic::new(
            Runtime,
            IndexOutOfBounds,
            "list index \{raw_index} is outside the valid range",
            span,
          ),
        )
      } else {
        CollectionIndexSucceeded(index)
      }
    }
    other =>
      CollectionIndexFailed(
        Diagnostic::new(
          Runtime,
          InvalidIndex,
          "list index must be a Num, received \{other.type_name()}",
          span,
        ),
      )
  }
}

///|
fn read_list_range(
  items : Array[Value],
  from : Double,
  to : Double,
  inclusive : Bool,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  let endpoint_allows_end = !inclusive
  let start = match
    collection_index(
      Value::number(from),
      items.length(),
      endpoint_allows_end,
      span,
    ) {
    CollectionIndexFailed(issue) => return EvaluationFailed(issue)
    CollectionIndexSucceeded(index) => index
  }
  let end = match
    collection_index(
      Value::number(to),
      items.length(),
      endpoint_allows_end,
      span,
    ) {
    CollectionIndexFailed(issue) => return EvaluationFailed(issue)
    CollectionIndexSucceeded(index) => index
  }
  if start == items.length() && start != end {
    return evaluation_error(
      IndexOutOfBounds,
      "list slice starts outside the valid range",
      span,
    )
  }
  let result : Array[Value] = []
  let step = if start <= end { 1 } else { -1 }
  let mut index = start
  while (if step > 0 {
          if inclusive {
            index <= end
          } else {
            index < end
          }
        } else if inclusive {
          index >= end
        } else {
          index > end
        }) {
    if index < 0 || index >= items.length() {
      return evaluation_error(
        IndexOutOfBounds,
        "list slice crosses outside the valid range",
        span,
      )
    }
    result.push(items[index])
    index = index + step
  }
  EvaluationSucceeded(context.new_list(result))
}

///|
fn read_subscript(
  receiver : Value,
  index : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match receiver {
    ListValue(identifier) =>
      if identifier < 0 || identifier >= context.lists.length() {
        evaluation_error(InvalidOperand, "list is not available", span)
      } else {
        let items = context.lists[identifier].items
        match index {
          RangeValue(from, to, inclusive) =>
            read_list_range(items, from, to, inclusive, span, context)
          value =>
            match collection_index(value, items.length(), false, span) {
              CollectionIndexSucceeded(index) =>
                EvaluationSucceeded(items[index])
              CollectionIndexFailed(issue) => EvaluationFailed(issue)
            }
        }
      }
    MapValue(identifier) =>
      if identifier < 0 || identifier >= context.maps.length() {
        evaluation_error(InvalidOperand, "map is not available", span)
      } else if !is_valid_map_key(index) {
        invalid_map_key(index, span)
      } else {
        let entries = context.maps[identifier].entries
        match find_map_key(entries, index) {
          Some(position) => EvaluationSucceeded(entries[position].value)
          None => EvaluationSucceeded(Value::null())
        }
      }
    other =>
      evaluation_error(
        InvalidOperand,
        "subscript receiver must be a List or Map, received \{other.type_name()}",
        span,
      )
  }
}

///|
fn write_subscript(
  receiver : Value,
  index : Value,
  value : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match receiver {
    ListValue(identifier) =>
      if identifier < 0 || identifier >= context.lists.length() {
        evaluation_error(InvalidOperand, "list is not available", span)
      } else {
        let items = context.lists[identifier].items
        match collection_index(index, items.length(), false, span) {
          CollectionIndexSucceeded(index) => {
            items[index] = value
            EvaluationSucceeded(value)
          }
          CollectionIndexFailed(issue) => EvaluationFailed(issue)
        }
      }
    MapValue(identifier) =>
      if !is_valid_map_key(index) {
        invalid_map_key(index, span)
      } else if context.set_map_entry(identifier, index, value) {
        EvaluationSucceeded(value)
      } else {
        evaluation_error(InvalidOperand, "map is not available", span)
      }
    other =>
      evaluation_error(
        InvalidOperand,
        "subscript receiver must be a List or Map, received \{other.type_name()}",
        span,
      )
  }
}

///|
fn invalid_collection_arity(
  owner : String,
  name : String,
  expected : Int,
  received : Int,
  span : SourceSpan,
) -> EvaluationResult {
  evaluation_error(
    InvalidArity,
    "\{owner}.\{name} expects \{expected} arguments, received \{received}",
    span,
  )
}

///|
fn indexed_iterator(
  owner : String,
  items : Array[Value],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if arguments.length() != 1 {
    return invalid_collection_arity(owner, name, 1, arguments.length(), span)
  }
  if name == "iterate" {
    match arguments[0] {
      NullValue =>
        if items.length() == 0 {
          EvaluationSucceeded(Value::bool(false))
        } else {
          EvaluationSucceeded(Value::number(0.0))
        }
      NumberValue(number) => {
        let index = number.to_int()
        if Double::from_int(index) != number || index < 0 {
          evaluation_error(
            InvalidOperand,
            "\{owner} iterator must be a non-negative integer",
            span,
          )
        } else if index + 1 < items.length() {
          EvaluationSucceeded(Value::number(Double::from_int(index + 1)))
        } else {
          EvaluationSucceeded(Value::bool(false))
        }
      }
      value =>
        evaluation_error(
          InvalidOperand,
          "\{owner} iterator must be null or Num, received \{value.type_name()}",
          span,
        )
    }
  } else if name == "iteratorValue" {
    match arguments[0] {
      NumberValue(number) => {
        let index = number.to_int()
        if Double::from_int(index) != number ||
          index < 0 ||
          index >= items.length() {
          evaluation_error(
            InvalidOperand,
            "\{owner} iterator is outside the valid range",
            span,
          )
        } else {
          EvaluationSucceeded(items[index])
        }
      }
      value =>
        evaluation_error(
          InvalidOperand,
          "\{owner} iterator must be a Num, received \{value.type_name()}",
          span,
        )
    }
  } else {
    evaluation_error(
      UndefinedMethod,
      "\{owner} does not implement method '\{name}'",
      span,
    )
  }
}

///|
fn invoke_range_method(
  from : Double,
  to : Double,
  inclusive : Bool,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if name != "iterate" && name != "iteratorValue" {
    return evaluation_error(
      UndefinedMethod,
      "Range does not implement method '\{name}'",
      span,
    )
  }
  if arguments.length() != 1 {
    return invalid_collection_arity("Range", name, 1, arguments.length(), span)
  }
  if name == "iteratorValue" {
    return match arguments[0] {
      NumberValue(_) => EvaluationSucceeded(arguments[0])
      value =>
        evaluation_error(
          InvalidOperand,
          "Range iterator must be a Num, received \{value.type_name()}",
          span,
        )
    }
  }
  let step = if from <= to { 1.0 } else { -1.0 }
  let next = match arguments[0] {
    NullValue => from
    NumberValue(current) => current + step
    value =>
      return evaluation_error(
        InvalidOperand,
        "Range iterator must be null or Num, received \{value.type_name()}",
        span,
      )
  }
  let has_next = if step > 0.0 {
    if inclusive {
      next <= to
    } else {
      next < to
    }
  } else if inclusive {
    next >= to
  } else {
    next > to
  }
  if has_next {
    EvaluationSucceeded(Value::number(next))
  } else {
    EvaluationSucceeded(Value::bool(false))
  }
}

///|
fn invoke_sequence_method(
  identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier < 0 || identifier >= context.sequences.length() {
    return evaluation_error(InvalidOperand, "sequence is not available", span)
  }
  indexed_iterator(
    "Sequence",
    context.sequences[identifier].items,
    name,
    arguments,
    span,
  )
}

///|
fn invoke_list_method(
  identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier < 0 || identifier >= context.lists.length() {
    return evaluation_error(InvalidOperand, "list is not available", span)
  }
  let items = context.lists[identifier].items
  if name == "iterate" || name == "iteratorValue" {
    return indexed_iterator("List", items, name, arguments, span)
  }
  match name {
    "add" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        items.push(arguments[0])
        EvaluationSucceeded(arguments[0])
      }
    "insert" =>
      if arguments.length() != 2 {
        invalid_collection_arity("List", name, 2, arguments.length(), span)
      } else {
        match collection_index(arguments[0], items.length(), true, span) {
          CollectionIndexFailed(issue) => EvaluationFailed(issue)
          CollectionIndexSucceeded(index) => {
            items.push(arguments[1])
            for position = items.length() - 1
                position > index
                position = position - 1 {
              items[position] = items[position - 1]
            }
            items[index] = arguments[1]
            EvaluationSucceeded(arguments[1])
          }
        }
      }
    "removeAt" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        match collection_index(arguments[0], items.length(), false, span) {
          CollectionIndexFailed(issue) => EvaluationFailed(issue)
          CollectionIndexSucceeded(index) => {
            let removed = items[index]
            for position = index
                position + 1 < items.length()
                position = position + 1 {
              items[position] = items[position + 1]
            }
            ignore(items.pop())
            EvaluationSucceeded(removed)
          }
        }
      }
    "contains" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        let mut found = false
        for item in items {
          if item == arguments[0] {
            found = true
          }
        }
        EvaluationSucceeded(Value::bool(found))
      }
    "indexOf" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        let mut found = -1
        for index = 0; index < items.length(); index = index + 1 {
          if found == -1 && items[index] == arguments[0] {
            found = index
          }
        }
        EvaluationSucceeded(Value::number(Double::from_int(found)))
      }
    "remove" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        let mut found = -1
        for index = 0; index < items.length(); index = index + 1 {
          if found == -1 && items[index] == arguments[0] {
            found = index
          }
        }
        if found == -1 {
          EvaluationSucceeded(Value::null())
        } else {
          let removed = items[found]
          for position = found
              position + 1 < items.length()
              position = position + 1 {
            items[position] = items[position + 1]
          }
          ignore(items.pop())
          EvaluationSucceeded(removed)
        }
      }
    "swap" =>
      if arguments.length() != 2 {
        invalid_collection_arity("List", name, 2, arguments.length(), span)
      } else {
        let left = match
          collection_index(arguments[0], items.length(), false, span) {
          CollectionIndexFailed(issue) => return EvaluationFailed(issue)
          CollectionIndexSucceeded(index) => index
        }
        let right = match
          collection_index(arguments[1], items.length(), false, span) {
          CollectionIndexFailed(issue) => return EvaluationFailed(issue)
          CollectionIndexSucceeded(index) => index
        }
        let temporary = items[left]
        items[left] = items[right]
        items[right] = temporary
        EvaluationSucceeded(Value::null())
      }
    "clear" =>
      if arguments.length() != 0 {
        invalid_collection_arity("List", name, 0, arguments.length(), span)
      } else {
        while items.length() > 0 {
          ignore(items.pop())
        }
        EvaluationSucceeded(Value::null())
      }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "List does not implement method '\{name}'",
        span,
      )
  }
}

///|
fn invoke_map_method(
  identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier < 0 || identifier >= context.maps.length() {
    return evaluation_error(InvalidOperand, "map is not available", span)
  }
  let entries = context.maps[identifier].entries
  match name {
    "containsKey" =>
      if arguments.length() != 1 {
        invalid_collection_arity("Map", name, 1, arguments.length(), span)
      } else if !is_valid_map_key(arguments[0]) {
        invalid_map_key(arguments[0], span)
      } else {
        let found = match find_map_key(entries, arguments[0]) {
          Some(_) => true
          None => false
        }
        EvaluationSucceeded(Value::bool(found))
      }
    "remove" =>
      if arguments.length() != 1 {
        invalid_collection_arity("Map", name, 1, arguments.length(), span)
      } else if !is_valid_map_key(arguments[0]) {
        invalid_map_key(arguments[0], span)
      } else {
        match find_map_key(entries, arguments[0]) {
          None => EvaluationSucceeded(Value::null())
          Some(index) => {
            let removed = entries[index].value
            for position = index
                position + 1 < entries.length()
                position = position + 1 {
              entries[position] = entries[position + 1]
            }
            ignore(entries.pop())
            EvaluationSucceeded(removed)
          }
        }
      }
    "clear" =>
      if arguments.length() != 0 {
        invalid_collection_arity("Map", name, 0, arguments.length(), span)
      } else {
        while entries.length() > 0 {
          ignore(entries.pop())
        }
        EvaluationSucceeded(Value::null())
      }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "Map does not implement method '\{name}'",
        span,
      )
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
          context.output.push(runtime_value_to_text(value, context, 0))
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
    ListValue(identifier) =>
      invoke_list_method(identifier, name, arguments, span, context)
    MapValue(identifier) =>
      invoke_map_method(identifier, name, arguments, span, context)
    SequenceValue(identifier) =>
      invoke_sequence_method(identifier, name, arguments, span, context)
    RangeValue(from, to, inclusive) =>
      invoke_range_method(from, to, inclusive, name, arguments, span)
    ClassValue(identifier) =>
      match
        find_method_in_class(
          context,
          identifier,
          name,
          arguments.length(),
          false,
          false,
          true,
        ) {
        Some(resolved) =>
          invoke_static_method(identifier, resolved, arguments, span, context)
        None => construct_instance(identifier, name, arguments, span, context)
      }
    InstanceValue(identifier) =>
      invoke_instance_method(identifier, name, arguments, span, context)
    SuperValue(superclass, instance_identifier, _) =>
      match
        find_method_in_class(
          context,
          superclass,
          name,
          arguments.length(),
          false,
          false,
          false,
        ) {
        Some(resolved) =>
          invoke_user_method(
            instance_identifier, resolved, arguments, span, context,
          )
        None =>
          evaluation_error(
            UndefinedMethod,
            "superclass does not implement method '\{name}' with \{arguments.length()} arguments",
            span,
          )
      }
    SuperClassValue(superclass, receiver_class) =>
      match
        find_method_in_class(
          context,
          superclass,
          name,
          arguments.length(),
          false,
          false,
          true,
        ) {
        Some(resolved) =>
          invoke_static_method(
            receiver_class, resolved, arguments, span, context,
          )
        None =>
          evaluation_error(
            UndefinedMethod,
            "superclass does not implement static method '\{name}' with \{arguments.length()} arguments",
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
  context : RuntimeContext,
) -> EvaluationResult {
  match receiver {
    InstanceValue(identifier) => {
      if identifier < 0 || identifier >= context.instances.length() {
        return evaluation_error(
          UndefinedMethod,
          "instance is not available in this runtime",
          span,
        )
      }
      let class_identifier = context.instances[identifier].class_identifier
      let class_definition = context.classes[class_identifier]
      match
        find_method_in_class(
          context, class_identifier, name, 0, false, true, false,
        ) {
        Some(resolved) =>
          invoke_user_method(identifier, resolved, [], span, context)
        None =>
          if name == "toString" {
            EvaluationSucceeded(
              Value::string("\{class_definition.name} instance"),
            )
          } else {
            evaluation_error(
              UndefinedMethod,
              "\{class_definition.name} does not implement getter '\{name}'",
              span,
            )
          }
      }
    }
    SuperValue(superclass, instance_identifier, _) =>
      match
        find_method_in_class(context, superclass, name, 0, false, true, false) {
        Some(resolved) =>
          invoke_user_method(instance_identifier, resolved, [], span, context)
        None =>
          evaluation_error(
            UndefinedMethod,
            "superclass does not implement getter '\{name}'",
            span,
          )
      }
    ClassValue(identifier) =>
      match
        find_method_in_class(context, identifier, name, 0, false, true, true) {
        Some(resolved) =>
          invoke_static_method(identifier, resolved, [], span, context)
        None =>
          if name == "toString" {
            EvaluationSucceeded(Value::string(context.classes[identifier].name))
          } else {
            evaluation_error(
              UndefinedMethod,
              "\{context.classes[identifier].name} does not implement static getter '\{name}'",
              span,
            )
          }
      }
    SuperClassValue(superclass, receiver_class) =>
      match
        find_method_in_class(context, superclass, name, 0, false, true, true) {
        Some(resolved) =>
          invoke_static_method(receiver_class, resolved, [], span, context)
        None =>
          evaluation_error(
            UndefinedMethod,
            "superclass does not implement static getter '\{name}'",
            span,
          )
      }
    RangeValue(from, to, inclusive) =>
      match name {
        "toString" => EvaluationSucceeded(Value::string(receiver.to_text()))
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
    ListValue(identifier) =>
      if identifier < 0 || identifier >= context.lists.length() {
        evaluation_error(InvalidOperand, "list is not available", span)
      } else {
        match name {
          "count" =>
            EvaluationSucceeded(
              Value::number(
                Double::from_int(context.lists[identifier].items.length()),
              ),
            )
          "toString" =>
            EvaluationSucceeded(
              Value::string(runtime_value_to_text(receiver, context, 0)),
            )
          _ =>
            evaluation_error(
              UndefinedMethod,
              "List does not implement getter '\{name}'",
              span,
            )
        }
      }
    MapValue(identifier) =>
      if identifier < 0 || identifier >= context.maps.length() {
        evaluation_error(InvalidOperand, "map is not available", span)
      } else {
        match name {
          "count" =>
            EvaluationSucceeded(
              Value::number(
                Double::from_int(context.maps[identifier].entries.length()),
              ),
            )
          "toString" =>
            EvaluationSucceeded(
              Value::string(runtime_value_to_text(receiver, context, 0)),
            )
          "keys" => {
            let values : Array[Value] = []
            for entry in context.maps[identifier].entries {
              values.push(entry.key)
            }
            EvaluationSucceeded(context.new_sequence(values))
          }
          "values" => {
            let values : Array[Value] = []
            for entry in context.maps[identifier].entries {
              values.push(entry.value)
            }
            EvaluationSucceeded(context.new_sequence(values))
          }
          _ =>
            evaluation_error(
              UndefinedMethod,
              "Map does not implement getter '\{name}'",
              span,
            )
        }
      }
    SequenceValue(identifier) =>
      if identifier < 0 || identifier >= context.sequences.length() {
        evaluation_error(InvalidOperand, "sequence is not available", span)
      } else {
        match name {
          "count" =>
            EvaluationSucceeded(
              Value::number(
                Double::from_int(context.sequences[identifier].items.length()),
              ),
            )
          "toString" =>
            EvaluationSucceeded(
              Value::string(runtime_value_to_text(receiver, context, 0)),
            )
          _ =>
            evaluation_error(
              UndefinedMethod,
              "Sequence does not implement getter '\{name}'",
              span,
            )
        }
      }
    value =>
      if name == "toString" {
        EvaluationSucceeded(Value::string(value.to_text()))
      } else {
        evaluation_error(
          UndefinedMethod,
          "\{value.type_name()} does not implement getter '\{name}'",
          span,
        )
      }
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
    ListLiteral(expressions, _) => {
      let items : Array[Value] = []
      for expression in expressions {
        match evaluate_expression_in(expression, environment, context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => items.push(value)
        }
      }
      EvaluationSucceeded(context.new_list(items))
    }
    MapLiteral(expressions, _) => {
      let map = context.new_map()
      let identifier = match map {
        MapValue(identifier) => identifier
        _ => -1
      }
      for entry in expressions {
        let key = match
          evaluate_expression_in(entry.key, environment, context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => value
        }
        if !is_valid_map_key(key) {
          return invalid_map_key(key, entry.key.span())
        }
        let value = match
          evaluate_expression_in(entry.value, environment, context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => value
        }
        ignore(context.set_map_entry(identifier, key, value))
      }
      EvaluationSucceeded(map)
    }
    SubscriptGet(receiver, index, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) =>
          match evaluate_expression_in(index, environment, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(index) =>
              read_subscript(receiver, index, span, context)
          }
      }
    SubscriptSet(receiver, index, expression, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) =>
          match evaluate_expression_in(index, environment, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(index) =>
              match evaluate_expression_in(expression, environment, context) {
                EvaluationFailed(issue) => EvaluationFailed(issue)
                EvaluationSucceeded(value) =>
                  write_subscript(receiver, index, value, span, context)
              }
          }
      }
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
    FieldGet(name, span) =>
      match environment.get("this") {
        Some(InstanceValue(identifier)) =>
          match context.get_instance_field(identifier, name) {
            Some(value) => EvaluationSucceeded(value)
            None =>
              evaluation_error(
                UndefinedVariable,
                "instance field '\{name}' is not available",
                span,
              )
          }
        _ =>
          evaluation_error(
            UndefinedVariable,
            "instance field '\{name}' can only be used inside a method",
            span,
          )
      }
    FieldAssign(name, expression, span) =>
      match evaluate_expression_in(expression, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          match environment.get("this") {
            Some(InstanceValue(identifier)) =>
              if context.set_instance_field(identifier, name, value) {
                EvaluationSucceeded(value)
              } else {
                evaluation_error(
                  UndefinedVariable,
                  "instance field '\{name}' is not available",
                  span,
                )
              }
            _ =>
              evaluation_error(
                UndefinedVariable,
                "instance field '\{name}' can only be assigned inside a method",
                span,
              )
          }
      }
    StaticFieldGet(name, span) =>
      match environment.get("$class") {
        Some(ClassValue(identifier)) =>
          match context.get_static_field(identifier, name) {
            Some(value) => EvaluationSucceeded(value)
            None =>
              evaluation_error(
                UndefinedVariable,
                "static field '\{name}' is not available",
                span,
              )
          }
        _ =>
          evaluation_error(
            UndefinedVariable,
            "static field '\{name}' can only be used inside a static method",
            span,
          )
      }
    StaticFieldAssign(name, expression, span) =>
      match evaluate_expression_in(expression, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) =>
          match environment.get("$class") {
            Some(ClassValue(identifier)) =>
              if context.set_static_field(identifier, name, value) {
                EvaluationSucceeded(value)
              } else {
                evaluation_error(
                  UndefinedVariable,
                  "static field '\{name}' is not available",
                  span,
                )
              }
            _ =>
              evaluation_error(
                UndefinedVariable,
                "static field '\{name}' can only be assigned inside a static method",
                span,
              )
          }
      }
    PropertyGet(receiver, name, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) =>
          read_property(receiver, name, span, context)
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
    SuperConstructorCall(arguments, span) => {
      let values : Array[Value] = []
      for argument in arguments {
        match evaluate_expression_in(argument, environment, context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => values.push(value)
        }
      }
      match environment.get("$super") {
        Some(SuperValue(superclass, instance_identifier, constructor_name)) =>
          invoke_super_constructor(
            superclass, instance_identifier, constructor_name, values, span, context,
          )
        _ =>
          evaluation_error(
            UndefinedMethod,
            "super can only be used in a subclass method",
            span,
          )
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
    Binary(left, IsType, right, span) =>
      match evaluate_expression_in(left, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(left_value) =>
          match evaluate_expression_in(right, environment, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(right_value) =>
              evaluate_is_type(left_value, right_value, span, context)
          }
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
      StatementBroken(span) => return StatementBroken(span)
      StatementContinued(span) => return StatementContinued(span)
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
fn execute_iterable_for_in(
  name : String,
  sequence : Value,
  body : Stmt,
  span : SourceSpan,
  environment : Environment,
  context : RuntimeContext,
) -> StatementResult {
  let iterable = match sequence {
    ListValue(identifier) => {
      if identifier < 0 || identifier >= context.lists.length() {
        return StatementFailed(
          Diagnostic::new(
            Runtime,
            InvalidOperand,
            "list is not available",
            span,
          ),
        )
      }
      let items : Array[Value] = []
      for item in context.lists[identifier].items {
        items.push(item)
      }
      context.new_sequence(items)
    }
    value => value
  }
  match iterable {
    RangeValue(_, _, _)
    | ListValue(_)
    | StringValue(_)
    | SequenceValue(_)
    | InstanceValue(_) => ()
    value =>
      return StatementFailed(
        Diagnostic::new(
          Runtime,
          InvalidOperand,
          "for loop expects an iterable value, received \{value.type_name()}",
          span,
        ),
      )
  }
  environment.push_scope()
  ignore(environment.bind(name, Value::null()))
  let mut last = Value::null()
  let mut iterator = Value::null()
  while true {
    match invoke_method(iterable, "iterate", [iterator], span, context) {
      EvaluationFailed(issue) => {
        ignore(environment.pop_scope())
        return StatementFailed(issue)
      }
      EvaluationSucceeded(BoolValue(false)) => break
      EvaluationSucceeded(next) => iterator = next
    }
    let item = match
      invoke_method(iterable, "iteratorValue", [iterator], span, context) {
      EvaluationFailed(issue) => {
        ignore(environment.pop_scope())
        return StatementFailed(issue)
      }
      EvaluationSucceeded(value) => value
    }
    ignore(environment.assign(name, item))
    match execute_statement_in(body, environment, context) {
      StatementCompleted(value) => last = value
      StatementReturned(value, span) => {
        ignore(environment.pop_scope())
        return StatementReturned(value, span)
      }
      StatementBroken(_) => {
        ignore(environment.pop_scope())
        return StatementCompleted(last)
      }
      StatementContinued(_) => ()
      StatementFailed(issue) => {
        ignore(environment.pop_scope())
        return StatementFailed(issue)
      }
    }
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
          StatementBroken(_) => break
          StatementContinued(_) => continue
          StatementFailed(issue) => return StatementFailed(issue)
        }
      }
      StatementCompleted(last)
    }
    ForStatement(name, sequence, body, span) =>
      match evaluate_expression_in(sequence, environment, context) {
        EvaluationFailed(issue) => StatementFailed(issue)
        EvaluationSucceeded(value) =>
          execute_iterable_for_in(name, value, body, span, environment, context)
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
    BreakStatement(span) => StatementBroken(span)
    ContinueStatement(span) => StatementContinued(span)
    ClassStatement(name, superclass_name, methods, span) => {
      for index = 0; index < methods.length(); index = index + 1 {
        for other = index + 1; other < methods.length(); other = other + 1 {
          let left = methods[index]
          let right = methods[other]
          if left.name == right.name &&
            left.parameters.length() == right.parameters.length() &&
            left.is_constructor == right.is_constructor &&
            left.is_getter == right.is_getter &&
            left.is_static == right.is_static {
            return StatementFailed(
              Diagnostic::new(
                Runtime,
                DuplicateMethod,
                "duplicate method '\{left.name}' with \{left.parameters.length()} parameters",
                right.span,
              ),
            )
          }
        }
      }
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
      let superclass = match superclass_name {
        None => None
        Some(superclass_name) =>
          match environment.get(superclass_name) {
            Some(ClassValue(identifier)) => Some(identifier)
            Some(value) =>
              return StatementFailed(
                Diagnostic::new(
                  Runtime,
                  InvalidSuperclass,
                  "superclass '\{superclass_name}' must be a Class, received \{value.type_name()}",
                  span,
                ),
              )
            None =>
              return StatementFailed(
                Diagnostic::new(
                  Runtime,
                  InvalidSuperclass,
                  "undefined superclass '\{superclass_name}'",
                  span,
                ),
              )
          }
      }
      let identifier = context.classes.length()
      context.classes.push({
        name,
        superclass,
        methods,
        environment: environment.capture(),
        static_fields: [],
      })
      let value = Value::class_value(identifier)
      ignore(environment.assign(name, value))
      StatementCompleted(value)
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
