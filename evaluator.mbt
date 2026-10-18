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
  source_name : String
}

///|
priv struct ClassDefinition {
  name : String
  superclass : Int?
  methods : Array[MethodDecl]
  is_foreign : Bool
  foreign_binding : Int?
  environment : Environment
  static_fields : Array[InstanceField]
  source_name : String
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
  foreign_handle : Int?
  mut finalized : Bool
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
priv struct RuntimeMapEntryValue {
  key : Value
  value : Value
}

///|
priv enum RuntimeSequenceKind {
  SequenceSnapshot(Array[Value])
  SequenceMap(Value, Int)
  SequenceWhere(Value, Int)
  SequenceSkip(Value, Int)
  SequenceTake(Value, Int)
}

///|
priv enum IteratorAdvanceResult {
  IteratorAdvanced(Value, Value)
  IteratorComplete
  IteratorAdvanceFailed(Diagnostic)
}

///|
priv enum CollectedValuesResult {
  ValuesCollected(Array[Value])
  ValueCollectionFailed(Diagnostic)
}

///|
priv struct RuntimeSequence {
  kind : RuntimeSequenceKind
}

///|
priv struct RuntimeIterator {
  sequence_identifier : Int
  mut source_iterator : Value
  mut current : Value
  mut yielded : Int
  mut started : Bool
  mut completed : Bool
}

///|
priv struct RuntimeFiber {
  function_identifier : Int
  arguments : Array[Value]
  identity : Int
  is_call_frame : Bool
  mut environment : Environment
  mut initialized : Bool
  mut state : Int
  mut next_statement : Int
  mut pending : ((Value) -> FiberStatementStep)?
  mut last : Value
  mut error : Value
}

///|
priv struct RuntimeModule {
  name : String
  environment : Environment
  mut state : Int
}

///|
priv struct RuntimeContext {
  output : Array[String]
  mut output_line_open : Bool
  closures : Array[Closure]
  classes : Array[ClassDefinition]
  instances : Array[Instance]
  lists : Array[RuntimeList]
  maps : Array[RuntimeMap]
  map_entries : Array[RuntimeMapEntryValue]
  sequences : Array[RuntimeSequence]
  iterators : Array[RuntimeIterator]
  fibers : Array[RuntimeFiber]
  modules : Array[RuntimeModule]
  foreign_methods : Array[ForeignMethodBinding]
  foreign_classes : Array[ForeignClassBinding]
  loader : (String, String) -> ModuleLoadResult
  mut current_source : String
  mut steps : Int
  max_steps : Int
  mut call_depth : Int
  max_call_depth : Int
  mut current_fiber : Int
}

///|
fn RuntimeContext::new_with_loader(
  max_steps : Int,
  source_name : String,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
) -> RuntimeContext {
  {
    output: [],
    output_line_open: false,
    closures: [],
    classes: [],
    instances: [],
    lists: [],
    maps: [],
    map_entries: [],
    sequences: [],
    iterators: [],
    fibers: [
      {
        function_identifier: -1,
        arguments: [],
        identity: 0,
        is_call_frame: false,
        environment: Environment::new(),
        initialized: true,
        state: 1,
        next_statement: 0,
        pending: None,
        last: Value::null(),
        error: Value::null(),
      },
    ],
    modules: [],
    foreign_methods,
    foreign_classes,
    loader,
    current_source: source_name,
    steps: 0,
    max_steps,
    call_depth: 0,
    max_call_depth: 64,
    current_fiber: 0,
  }
}

///|
fn RuntimeContext::new(max_steps : Int) -> RuntimeContext {
  RuntimeContext::new_with_loader(
    max_steps,
    "<source>",
    fn(_, name) { ModuleLoadFailed("module '\{name}' is not available") },
    [],
    [],
  )
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
fn RuntimeContext::new_fiber(
  self : RuntimeContext,
  function_identifier : Int,
) -> Value {
  let identifier = self.fibers.length()
  self.fibers.push({
    function_identifier,
    arguments: [],
    identity: identifier,
    is_call_frame: false,
    environment: Environment::new(),
    initialized: false,
    state: 0,
    next_statement: 0,
    pending: None,
    last: Value::null(),
    error: Value::null(),
  })
  Value::fiber(identifier)
}

///|
fn RuntimeContext::new_function_fiber(
  self : RuntimeContext,
  function_identifier : Int,
  arguments : Array[Value],
  identity : Int,
) -> Int {
  let identifier = self.fibers.length()
  self.fibers.push({
    function_identifier,
    arguments,
    identity,
    is_call_frame: true,
    environment: Environment::new(),
    initialized: false,
    state: 0,
    next_statement: 0,
    pending: None,
    last: Value::null(),
    error: Value::null(),
  })
  identifier
}

///|
fn RuntimeContext::new_sequence(
  self : RuntimeContext,
  items : Array[Value],
) -> Value {
  self.new_sequence_kind(SequenceSnapshot(items))
}

///|
fn RuntimeContext::new_sequence_kind(
  self : RuntimeContext,
  kind : RuntimeSequenceKind,
) -> Value {
  let identifier = self.sequences.length()
  self.sequences.push({ kind, })
  Value::sequence(identifier)
}

///|
fn RuntimeContext::new_map_entry(
  self : RuntimeContext,
  key : Value,
  value : Value,
) -> Value {
  let identifier = self.map_entries.length()
  self.map_entries.push({ key, value, })
  Value::map_entry(identifier)
}

///|
fn bind_core_globals(environment : Environment) -> Unit {
  ignore(environment.bind("System", Value::system()))
  ignore(environment.bind("Object", Value::core_class(ObjectClass)))
  ignore(environment.bind("Bool", Value::core_class(BoolClass)))
  ignore(environment.bind("Class", Value::core_class(ClassClass)))
  ignore(environment.bind("Fiber", Value::core_class(FiberClass)))
  ignore(environment.bind("Fn", Value::core_class(FnClass)))
  ignore(environment.bind("List", Value::core_class(ListClass)))
  ignore(environment.bind("Map", Value::core_class(MapClass)))
  ignore(environment.bind("Null", Value::core_class(NullClass)))
  ignore(environment.bind("Num", Value::core_class(NumClass)))
  ignore(environment.bind("Range", Value::core_class(RangeClass)))
  ignore(environment.bind("Sequence", Value::core_class(SequenceClass)))
  ignore(environment.bind("String", Value::core_class(StringClass)))
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
    | ClassValue(_)
    | CoreClassValue(_) => true
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
        match context.sequences[identifier].kind {
          SequenceSnapshot(items) => {
            let mut text = "("
            for index = 0; index < items.length(); index = index + 1 {
              if index > 0 {
                text = text + ", "
              }
              text = text +
                runtime_value_to_text(items[index], context, depth + 1)
            }
            text + ")"
          }
          _ => "<sequence>"
        }
      }
    MapEntryValue(identifier) =>
      if identifier < 0 || identifier >= context.map_entries.length() {
        "<map entry>"
      } else {
        let entry = context.map_entries[identifier]
        runtime_value_to_text(entry.key, context, depth + 1) +
        ":" +
        runtime_value_to_text(entry.value, context, depth + 1)
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
  context : RuntimeContext,
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
        (ListValue(identifier), iterable) => {
          if identifier < 0 || identifier >= context.lists.length() {
            return evaluation_error(
              InvalidOperand,
              "list is not available",
              span,
            )
          }
          let values : Array[Value] = []
          for value in context.lists[identifier].items {
            values.push(value)
          }
          match collect_iterable_values(iterable, span, context) {
            ValueCollectionFailed(issue) => EvaluationFailed(issue)
            ValuesCollected(other) => {
              for value in other {
                values.push(value)
              }
              EvaluationSucceeded(context.new_list(values))
            }
          }
        }
        _ => invalid_binary("+", left, right, span)
      }
    Multiply =>
      match (left, right) {
        (NumberValue(left), NumberValue(right)) =>
          number_binary(Multiply, left, right, span)
        (StringValue(text), count_value) =>
          match non_negative_count(count_value) {
            None =>
              evaluation_error(
                InvalidOperand,
                "String repetition count must be a non-negative integer",
                span,
              )
            Some(count) => {
              let mut result = ""
              for index = 0; index < count; index = index + 1 {
                result = result + text
              }
              EvaluationSucceeded(Value::string(result))
            }
          }
        (ListValue(identifier), count_value) =>
          if identifier < 0 || identifier >= context.lists.length() {
            evaluation_error(InvalidOperand, "list is not available", span)
          } else {
            match non_negative_count(count_value) {
              None =>
                evaluation_error(
                  InvalidOperand,
                  "List repetition count must be a non-negative integer",
                  span,
                )
              Some(count) => {
                let values : Array[Value] = []
                for repeat_index = 0
                    repeat_index < count
                    repeat_index = repeat_index + 1 {
                  for value in context.lists[identifier].items {
                    values.push(value)
                  }
                }
                EvaluationSucceeded(context.new_list(values))
              }
            }
          }
        _ => invalid_binary("*", left, right, span)
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
fn core_class_for_value(value : Value, context : RuntimeContext) -> Value {
  match value {
    NullValue => Value::core_class(NullClass)
    BoolValue(_) => Value::core_class(BoolClass)
    NumberValue(_) => Value::core_class(NumClass)
    StringValue(_) => Value::core_class(StringClass)
    RangeValue(_, _, _) => Value::core_class(RangeClass)
    ListValue(_) => Value::core_class(ListClass)
    MapValue(_) => Value::core_class(MapClass)
    SequenceValue(_) => Value::core_class(SequenceClass)
    FunctionValue(_) => Value::core_class(FnClass)
    FiberValue(_) => Value::core_class(FiberClass)
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        Value::class_value(context.instances[identifier].class_identifier)
      } else {
        Value::core_class(ObjectClass)
      }
    ClassValue(_) | CoreClassValue(_) | SystemValue =>
      Value::core_class(ClassClass)
    MapEntryValue(_) | IteratorValue(_) => Value::core_class(ObjectClass)
    SuperValue(_, instance_identifier, _) =>
      if instance_identifier >= 0 &&
        instance_identifier < context.instances.length() {
        Value::class_value(
          context.instances[instance_identifier].class_identifier,
        )
      } else {
        Value::core_class(ObjectClass)
      }
    SuperClassValue(_, _) => Value::core_class(ClassClass)
  }
}

///|
fn value_is_core_class(value : Value, target : CoreClass) -> Bool {
  if target == ObjectClass {
    return true
  }
  match value {
    NullValue => target == NullClass
    BoolValue(_) => target == BoolClass
    NumberValue(_) => target == NumClass
    StringValue(_) => target == StringClass || target == SequenceClass
    RangeValue(_, _, _) => target == RangeClass || target == SequenceClass
    ListValue(_) => target == ListClass || target == SequenceClass
    MapValue(_) => target == MapClass || target == SequenceClass
    SequenceValue(_) => target == SequenceClass
    FunctionValue(_) => target == FnClass
    FiberValue(_) => target == FiberClass
    ClassValue(_) | CoreClassValue(_) | SystemValue => target == ClassClass
    InstanceValue(_) | MapEntryValue(_) | IteratorValue(_) => false
    SuperValue(_, _, _) => false
    SuperClassValue(_, _) => target == ClassClass
  }
}

///|
fn evaluate_is_type(
  value : Value,
  type_value : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match type_value {
    CoreClassValue(target) =>
      EvaluationSucceeded(Value::bool(value_is_core_class(value, target)))
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
fn trace_call_failure(
  result : EvaluationResult,
  definition_source : String,
  callable : String,
  caller_source : String,
  span : SourceSpan,
) -> EvaluationResult {
  match result {
    EvaluationSucceeded(value) => EvaluationSucceeded(value)
    EvaluationFailed(issue) =>
      EvaluationFailed(
        issue
        .with_source(definition_source)
        .with_frame(CallFrame::new(callable, caller_source, span)),
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
  let caller_source = context.current_source
  context.current_source = closure.source_name
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(closure.body, environment, context)
  context.call_depth = context.call_depth - 1
  context.current_source = caller_source
  ignore(environment.pop_scope())
  let evaluation = match result {
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
  trace_call_failure(
    evaluation,
    closure.source_name,
    "Fn.call",
    caller_source,
    span,
  )
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
fn method_signature(declaration : MethodDecl) -> String {
  if declaration.is_getter {
    return declaration.name
  }
  let mut signature = declaration.name + "("
  for index = 0; index < declaration.parameters.length(); index = index + 1 {
    if index > 0 {
      signature = signature + ","
    }
    signature = signature + "_"
  }
  signature + ")"
}

///|
fn find_foreign_class_binding(
  context : RuntimeContext,
  module_name : String,
  class_name : String,
) -> Int? {
  for index = 0; index < context.foreign_classes.length(); index = index + 1 {
    if context.foreign_classes[index].matches(module_name, class_name) {
      return Some(index)
    }
  }
  None
}

///|
fn invoke_foreign_method(
  receiver : Value,
  owner : ClassDefinition,
  declaration : MethodDecl,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  let signature = method_signature(declaration)
  for binding in context.foreign_methods {
    if binding.matches(
        owner.source_name,
        owner.name,
        declaration.is_static,
        signature,
      ) {
      let call_result = match receiver {
        InstanceValue(identifier) =>
          if identifier >= 0 &&
            identifier < context.instances.length() &&
            binding.accepts_handle() {
            match context.instances[identifier].foreign_handle {
              Some(handle) => binding.call_handle(handle, arguments)
              None =>
                ForeignCallFailed("receiver does not contain foreign data")
            }
          } else {
            binding.call(receiver, arguments)
          }
        _ => binding.call(receiver, arguments)
      }
      return match call_result {
        ForeignCallSucceeded(value) => EvaluationSucceeded(value)
        ForeignCallFailed(message) =>
          evaluation_error(
            ForeignCallFailed,
            "foreign method \{owner.name}.\{signature} failed: \{message}",
            span,
          )
      }
    }
  }
  evaluation_error(
    ForeignBindingMissing,
    "no foreign binding for \{owner.source_name}:\{owner.name}.\{signature}",
    span,
  )
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
  if declaration.is_foreign {
    return trace_call_failure(
      invoke_foreign_method(
        Value::instance(instance_identifier),
        owner,
        declaration,
        arguments,
        span,
        context,
      ),
      owner.source_name,
      "\{owner.name}.\{declaration.name}",
      context.current_source,
      span,
    )
  }
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
  let caller_source = context.current_source
  context.current_source = owner.source_name
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(declaration.body, environment, context)
  context.call_depth = context.call_depth - 1
  context.current_source = caller_source
  ignore(environment.pop_scope())
  let evaluation = match result {
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
  trace_call_failure(
    evaluation,
    owner.source_name,
    "\{owner.name}.\{declaration.name}",
    caller_source,
    span,
  )
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
  if declaration.is_foreign {
    return trace_call_failure(
      invoke_foreign_method(
        Value::class_value(receiver_class),
        owner,
        declaration,
        arguments,
        span,
        context,
      ),
      owner.source_name,
      "\{owner.name}.\{declaration.name}",
      context.current_source,
      span,
    )
  }
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
  let caller_source = context.current_source
  context.current_source = owner.source_name
  context.call_depth = context.call_depth + 1
  let result = execute_statements_in(declaration.body, environment, context)
  context.call_depth = context.call_depth - 1
  context.current_source = caller_source
  ignore(environment.pop_scope())
  let evaluation = match result {
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
  trace_call_failure(
    evaluation,
    owner.source_name,
    "\{owner.name}.\{declaration.name}",
    caller_source,
    span,
  )
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
      let foreign_handle = if class_definition.is_foreign {
        match class_definition.foreign_binding {
          None =>
            return evaluation_error(
              ForeignClassBindingMissing,
              "no foreign class binding for \{class_definition.source_name}:\{class_definition.name}",
              span,
            )
          Some(binding_identifier) =>
            match
              context.foreign_classes[binding_identifier].allocate(arguments) {
              ForeignAllocationSucceeded(handle) => Some(handle)
              ForeignAllocationFailed(message) =>
                return evaluation_error(
                  ForeignObjectAllocationFailed,
                  "foreign class \{class_definition.name} allocation failed: \{message}",
                  span,
                )
            }
        }
      } else {
        None
      }
      context.instances.push({
        class_identifier,
        fields: [],
        foreign_handle,
        finalized: false,
      })
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
fn read_string_range(
  text : String,
  from : Double,
  to : Double,
  inclusive : Bool,
  span : SourceSpan,
) -> EvaluationResult {
  let characters = text.to_array()
  let endpoint_allows_end = !inclusive
  let start = match
    collection_index(
      Value::number(from),
      characters.length(),
      endpoint_allows_end,
      span,
    ) {
    CollectionIndexFailed(issue) => return EvaluationFailed(issue)
    CollectionIndexSucceeded(index) => index
  }
  let end = match
    collection_index(
      Value::number(to),
      characters.length(),
      endpoint_allows_end,
      span,
    ) {
    CollectionIndexFailed(issue) => return EvaluationFailed(issue)
    CollectionIndexSucceeded(index) => index
  }
  if start == characters.length() && start != end {
    return evaluation_error(
      IndexOutOfBounds,
      "string slice starts outside the valid range",
      span,
    )
  }
  let step = if start <= end { 1 } else { -1 }
  let mut index = start
  let mut result = ""
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
    if index < 0 || index >= characters.length() {
      return evaluation_error(
        IndexOutOfBounds,
        "string slice crosses outside the valid range",
        span,
      )
    }
    result = result + characters[index].to_string()
    index = index + step
  }
  EvaluationSucceeded(Value::string(result))
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
    StringValue(text) => {
      let characters = text.to_array()
      match index {
        RangeValue(from, to, inclusive) =>
          read_string_range(text, from, to, inclusive, span)
        value =>
          match collection_index(value, characters.length(), false, span) {
            CollectionIndexSucceeded(index) =>
              EvaluationSucceeded(Value::string(characters[index].to_string()))
            CollectionIndexFailed(issue) => EvaluationFailed(issue)
          }
      }
    }
    other =>
      evaluation_error(
        InvalidOperand,
        "subscript receiver must be a List, Map, or String, received \{other.type_name()}",
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
    StringValue(_) =>
      evaluation_error(
        InvalidOperand,
        "String values are immutable and cannot be assigned by subscript",
        span,
      )
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
fn string_items(text : String) -> Array[Value] {
  let items : Array[Value] = []
  for character in text.to_array() {
    items.push(Value::string(character.to_string()))
  }
  items
}

///|
fn invalid_string_argument(
  name : String,
  position : Int,
  value : Value,
  span : SourceSpan,
) -> EvaluationResult {
  evaluation_error(
    InvalidOperand,
    "String.\{name} argument \{position} must be a String, received \{value.type_name()}",
    span,
  )
}

///|
fn string_index_of(text : String, needle : String, start : Int) -> Int {
  let source = text.to_array()
  let search = needle.to_array()
  if search.length() == 0 {
    return start
  }
  for index = start
      index + search.length() <= source.length()
      index = index + 1 {
    let mut matches = true
    for offset = 0; offset < search.length(); offset = offset + 1 {
      if source[index + offset] != search[offset] {
        matches = false
      }
    }
    if matches {
      return index
    }
  }
  -1
}

///|
fn invoke_string_method(
  text : String,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if name == "iterate" || name == "iteratorValue" {
    return indexed_iterator("String", string_items(text), name, arguments, span)
  }
  match name {
    "contains" | "startsWith" | "endsWith" | "split" =>
      if arguments.length() != 1 {
        invalid_collection_arity("String", name, 1, arguments.length(), span)
      } else {
        let needle = match arguments[0] {
          StringValue(value) => value
          value => return invalid_string_argument(name, 1, value, span)
        }
        match name {
          "contains" => EvaluationSucceeded(Value::bool(text.contains(needle)))
          "startsWith" =>
            EvaluationSucceeded(Value::bool(text.has_prefix(needle)))
          "endsWith" =>
            EvaluationSucceeded(Value::bool(text.has_suffix(needle)))
          "split" =>
            if needle == "" {
              evaluation_error(
                InvalidOperand,
                "String.split separator must not be empty",
                span,
              )
            } else {
              let parts : Array[Value] = []
              for part in text.split(needle) {
                parts.push(Value::string(part.to_owned()))
              }
              EvaluationSucceeded(context.new_list(parts))
            }
          _ =>
            evaluation_error(UndefinedMethod, "unreachable String method", span)
        }
      }
    "indexOf" => {
      if arguments.length() != 1 && arguments.length() != 2 {
        return evaluation_error(
          InvalidArity,
          "String.indexOf expects one or two arguments, received \{arguments.length()}",
          span,
        )
      }
      let needle = match arguments[0] {
        StringValue(value) => value
        value => return invalid_string_argument(name, 1, value, span)
      }
      let length = text.char_length()
      let start = if arguments.length() == 1 {
        0
      } else {
        match arguments[1] {
          NumberValue(number) => {
            let raw = number.to_int()
            if Double::from_int(raw) != number {
              return evaluation_error(
                InvalidOperand,
                "String.indexOf start must be an integer",
                span,
              )
            }
            let normalized = if raw < 0 { length + raw } else { raw }
            if normalized < 0 || normalized > length {
              return evaluation_error(
                IndexOutOfBounds,
                "String.indexOf start is outside the valid range",
                span,
              )
            }
            normalized
          }
          value =>
            return evaluation_error(
              InvalidOperand,
              "String.indexOf start must be a Num, received \{value.type_name()}",
              span,
            )
        }
      }
      EvaluationSucceeded(
        Value::number(Double::from_int(string_index_of(text, needle, start))),
      )
    }
    "trim" | "trimStart" | "trimEnd" => {
      if arguments.length() > 1 {
        return evaluation_error(
          InvalidArity,
          "String.\{name} expects zero or one argument, received \{arguments.length()}",
          span,
        )
      }
      let characters = if arguments.length() == 0 {
        "\t\n\r "
      } else {
        match arguments[0] {
          StringValue(value) => value
          value => return invalid_string_argument(name, 1, value, span)
        }
      }
      let result = if name == "trim" {
        text.trim(chars=characters).to_owned()
      } else if name == "trimStart" {
        text.trim_start(chars=characters).to_owned()
      } else {
        text.trim_end(chars=characters).to_owned()
      }
      EvaluationSucceeded(Value::string(result))
    }
    "replace" =>
      if arguments.length() != 2 {
        invalid_collection_arity("String", name, 2, arguments.length(), span)
      } else {
        let old = match arguments[0] {
          StringValue(value) => value
          value => return invalid_string_argument(name, 1, value, span)
        }
        let replacement = match arguments[1] {
          StringValue(value) => value
          value => return invalid_string_argument(name, 2, value, span)
        }
        if old == "" {
          evaluation_error(
            InvalidOperand,
            "String.replace search text must not be empty",
            span,
          )
        } else {
          EvaluationSucceeded(
            Value::string(text.replace_all(old~, new=replacement)),
          )
        }
      }
    _ =>
      invoke_sequence_operation(
        Value::string(text),
        name,
        arguments,
        span,
        context,
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
  context : RuntimeContext,
) -> EvaluationResult {
  if name != "iterate" && name != "iteratorValue" {
    return invoke_sequence_operation(
      Value::range(from, to, inclusive),
      name,
      arguments,
      span,
      context,
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
fn advance_iterable(
  iterable : Value,
  iterator : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> IteratorAdvanceResult {
  match invoke_method(iterable, "iterate", [iterator], span, context) {
    EvaluationFailed(issue) => IteratorAdvanceFailed(issue)
    EvaluationSucceeded(BoolValue(false)) => IteratorComplete
    EvaluationSucceeded(next) =>
      match invoke_method(iterable, "iteratorValue", [next], span, context) {
        EvaluationFailed(issue) => IteratorAdvanceFailed(issue)
        EvaluationSucceeded(value) => IteratorAdvanced(next, value)
      }
  }
}

///|
fn advance_sequence_iterator(
  iterator_identifier : Int,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if iterator_identifier < 0 ||
    iterator_identifier >= context.iterators.length() {
    return evaluation_error(
      InvalidOperand,
      "sequence iterator is not available",
      span,
    )
  }
  let iterator = context.iterators[iterator_identifier]
  if iterator.completed {
    return EvaluationSucceeded(Value::bool(false))
  }
  let sequence_identifier = iterator.sequence_identifier
  if sequence_identifier < 0 ||
    sequence_identifier >= context.sequences.length() {
    return evaluation_error(InvalidOperand, "sequence is not available", span)
  }
  let complete = fn() -> EvaluationResult {
    iterator.completed = true
    EvaluationSucceeded(Value::bool(false))
  }
  match context.sequences[sequence_identifier].kind {
    SequenceSnapshot(items) =>
      if iterator.yielded >= items.length() {
        complete()
      } else {
        iterator.current = items[iterator.yielded]
        iterator.yielded = iterator.yielded + 1
        EvaluationSucceeded(Value::iterator(iterator_identifier))
      }
    SequenceMap(source, function_identifier) =>
      match advance_iterable(source, iterator.source_iterator, span, context) {
        IteratorAdvanceFailed(issue) => EvaluationFailed(issue)
        IteratorComplete => complete()
        IteratorAdvanced(next, value) => {
          iterator.source_iterator = next
          match invoke_function(function_identifier, [value], span, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(mapped) => {
              iterator.current = mapped
              iterator.yielded = iterator.yielded + 1
              EvaluationSucceeded(Value::iterator(iterator_identifier))
            }
          }
        }
      }
    SequenceWhere(source, function_identifier) => {
      while true {
        match
          advance_iterable(source, iterator.source_iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete => return complete()
          IteratorAdvanced(next, value) => {
            iterator.source_iterator = next
            match invoke_function(function_identifier, [value], span, context) {
              EvaluationFailed(issue) => return EvaluationFailed(issue)
              EvaluationSucceeded(selected) =>
                if selected.is_truthy() {
                  iterator.current = value
                  iterator.yielded = iterator.yielded + 1
                  return EvaluationSucceeded(
                    Value::iterator(iterator_identifier),
                  )
                }
            }
          }
        }
      }
      complete()
    }
    SequenceSkip(source, count) => {
      if !iterator.started {
        iterator.started = true
        for skip_index = 0; skip_index < count; skip_index = skip_index + 1 {
          match
            advance_iterable(source, iterator.source_iterator, span, context) {
            IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
            IteratorComplete => return complete()
            IteratorAdvanced(next, _) => iterator.source_iterator = next
          }
        }
      }
      match advance_iterable(source, iterator.source_iterator, span, context) {
        IteratorAdvanceFailed(issue) => EvaluationFailed(issue)
        IteratorComplete => complete()
        IteratorAdvanced(next, value) => {
          iterator.source_iterator = next
          iterator.current = value
          iterator.yielded = iterator.yielded + 1
          EvaluationSucceeded(Value::iterator(iterator_identifier))
        }
      }
    }
    SequenceTake(source, count) =>
      if iterator.yielded >= count {
        complete()
      } else {
        match
          advance_iterable(source, iterator.source_iterator, span, context) {
          IteratorAdvanceFailed(issue) => EvaluationFailed(issue)
          IteratorComplete => complete()
          IteratorAdvanced(next, value) => {
            iterator.source_iterator = next
            iterator.current = value
            iterator.yielded = iterator.yielded + 1
            EvaluationSucceeded(Value::iterator(iterator_identifier))
          }
        }
      }
  }
}

///|
fn collect_iterable_values(
  iterable : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> CollectedValuesResult {
  let values : Array[Value] = []
  let mut iterator = Value::null()
  while true {
    match invoke_method(iterable, "iterate", [iterator], span, context) {
      EvaluationFailed(issue) => return ValueCollectionFailed(issue)
      EvaluationSucceeded(BoolValue(false)) => break
      EvaluationSucceeded(next) => iterator = next
    }
    match invoke_method(iterable, "iteratorValue", [iterator], span, context) {
      EvaluationFailed(issue) => return ValueCollectionFailed(issue)
      EvaluationSucceeded(value) => values.push(value)
    }
  }
  ValuesCollected(values)
}

///|
fn expect_function_identifier(value : Value) -> Int? {
  match value {
    FunctionValue(identifier) => Some(identifier)
    _ => None
  }
}

///|
fn non_negative_count(value : Value) -> Int? {
  match value {
    NumberValue(number) => {
      let count = number.to_int()
      if count >= 0 && Double::from_int(count) == number {
        Some(count)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn invalid_function_argument(
  owner : String,
  name : String,
  span : SourceSpan,
) -> EvaluationResult {
  evaluation_error(
    InvalidOperand,
    "\{owner}.\{name} expects a function argument",
    span,
  )
}

///|
priv enum FiberExpressionStep {
  FiberExpressionReady
  FiberExpressionYielded(Value, (Value) -> Expr)
  FiberExpressionFailed(Diagnostic)
}

///|
priv enum FiberStatementStep {
  FiberStatementReady
  FiberStatementCompleted(StatementResult)
  FiberStatementYielded(Value, (Value) -> FiberStatementStep)
  FiberStatementFailed(Diagnostic)
}

///|
fn fiber_yield_value(
  name : String,
  arguments : Array[Expr],
  span : SourceSpan,
  environment : Environment,
  context : RuntimeContext,
) -> FiberExpressionStep {
  let valid_arity = if name == "suspend" {
    arguments.length() == 0
  } else {
    arguments.length() <= 1
  }
  if !valid_arity {
    return FiberExpressionFailed(
      Diagnostic::new(
        Runtime,
        InvalidArity,
        "Fiber.\{name} expects \{if name == "suspend" { "zero" } else { "zero or one" }} argument",
        span,
      ),
    )
  }
  let yielded = if arguments.length() == 0 {
    Value::null()
  } else {
    match evaluate_expression_in(arguments[0], environment, context) {
      EvaluationSucceeded(value) => value
      EvaluationFailed(issue) => return FiberExpressionFailed(issue)
    }
  }
  FiberExpressionYielded(yielded, fn(resumed) { Literal(resumed, span) })
}

///|
fn prepare_fiber_expression(
  expression : Expr,
  environment : Environment,
  context : RuntimeContext,
) -> FiberExpressionStep {
  match expression {
    MethodCall(Variable("Fiber", _), name, arguments, span) => {
      if name == "yield" || name == "suspend" {
        return fiber_yield_value(name, arguments, span, environment, context)
      }
      FiberExpressionReady
    }
    MethodCall(receiver, name, arguments, span) => {
      match prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberExpressionYielded(yielded, fn(resumed) {
            MethodCall(continuation(resumed), name, arguments, span)
          })
        FiberExpressionReady => ()
      }
      for index = 0; index < arguments.length(); index = index + 1 {
        match prepare_fiber_expression(arguments[index], environment, context) {
          FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
          FiberExpressionYielded(yielded, continuation) => {
            let argument_index = index
            return FiberExpressionYielded(yielded, fn(resumed) {
              let rebuilt : Array[Expr] = []
              for position = 0
                  position < arguments.length()
                  position = position + 1 {
                rebuilt.push(
                  if position == argument_index {
                    continuation(resumed)
                  } else {
                    arguments[position]
                  },
                )
              }
              MethodCall(receiver, name, rebuilt, span)
            })
          }
          FiberExpressionReady => ()
        }
      }
      if name == "transfer" && context.current_fiber != 0 {
        match receiver {
          Variable(_, _) =>
            match evaluate_expression_in(receiver, environment, context) {
              EvaluationFailed(issue) => return FiberExpressionFailed(issue)
              EvaluationSucceeded(FiberValue(0)) =>
                return fiber_yield_value(
                  "transfer", arguments, span, environment, context,
                )
              EvaluationSucceeded(_) => ()
            }
          _ => ()
        }
      }
      FiberExpressionReady
    }
    PropertyGet(receiver, name, span) =>
      match prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            PropertyGet(continuation(resumed), name, span)
          })
      }
    Grouping(inner, span) =>
      match prepare_fiber_expression(inner, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Grouping(continuation(resumed), span)
          })
      }
    Unary(operator, right, span) =>
      match prepare_fiber_expression(right, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Unary(operator, continuation(resumed), span)
          })
      }
    Binary(left, operator, right, span) =>
      match prepare_fiber_expression(left, environment, context) {
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Binary(continuation(resumed), operator, right, span)
          })
        FiberExpressionReady =>
          match prepare_fiber_expression(right, environment, context) {
            FiberExpressionReady => FiberExpressionReady
            FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
            FiberExpressionYielded(yielded, continuation) =>
              FiberExpressionYielded(yielded, fn(resumed) {
                Binary(left, operator, continuation(resumed), span)
              })
          }
      }
    Assign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Assign(name, continuation(resumed), span)
          })
      }
    FieldAssign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            FieldAssign(name, continuation(resumed), span)
          })
      }
    StaticFieldAssign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady => FiberExpressionReady
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            StaticFieldAssign(name, continuation(resumed), span)
          })
      }
    SubscriptGet(receiver, index, span) =>
      match prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            SubscriptGet(continuation(resumed), index, span)
          })
        FiberExpressionReady =>
          match prepare_fiber_expression(index, environment, context) {
            FiberExpressionReady => FiberExpressionReady
            FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
            FiberExpressionYielded(yielded, continuation) =>
              FiberExpressionYielded(yielded, fn(resumed) {
                SubscriptGet(receiver, continuation(resumed), span)
              })
          }
      }
    _ => FiberExpressionReady
  }
}

///|
fn resume_fiber_function_call(
  identifier : Int,
  input : Value,
  span : SourceSpan,
  context : RuntimeContext,
  complete : (Value) -> StatementResult,
) -> FiberStatementStep {
  match resume_runtime_fiber(identifier, input, span, context) {
    EvaluationFailed(issue) => FiberStatementFailed(issue)
    EvaluationSucceeded(value) => {
      let fiber = context.fibers[identifier]
      if fiber.state == 2 {
        FiberStatementYielded(value, fn(resumed) {
          resume_fiber_function_call(
            identifier, resumed, span, context, complete,
          )
        })
      } else {
        FiberStatementCompleted(complete(value))
      }
    }
  }
}

///|
fn prepare_direct_fiber_function_call(
  receiver : Expr,
  arguments : Array[Expr],
  span : SourceSpan,
  environment : Environment,
  context : RuntimeContext,
  complete : (Value) -> StatementResult,
) -> FiberStatementStep? {
  let function_identifier = match receiver {
    Variable(name, _) =>
      match environment.get(name) {
        Some(FunctionValue(identifier)) => identifier
        _ => return None
      }
    Literal(FunctionValue(identifier), _) => identifier
    _ => return None
  }
  if function_identifier < 0 || function_identifier >= context.closures.length() {
    return Some(
      FiberStatementFailed(
        Diagnostic::new(
          Runtime,
          UndefinedMethod,
          "function is not available in this runtime",
          span,
        ),
      ),
    )
  }
  let closure = context.closures[function_identifier]
  if arguments.length() < closure.parameters.length() {
    return Some(
      FiberStatementFailed(
        Diagnostic::new(
          Runtime,
          InvalidArity,
          "function expects at least {closure.parameters.length()} arguments, received {arguments.length()}",
          span,
        ),
      ),
    )
  }
  let values : Array[Value] = []
  for argument in arguments {
    match evaluate_expression_in(argument, environment, context) {
      EvaluationFailed(issue) => return Some(FiberStatementFailed(issue))
      EvaluationSucceeded(value) => values.push(value)
    }
  }
  let identifier = context.new_function_fiber(
    function_identifier,
    values,
    context.current_fiber,
  )
  Some(
    resume_fiber_function_call(
      identifier,
      Value::null(),
      span,
      context,
      complete,
    ),
  )
}

///|
fn prepare_fiber_statement(
  statement : Stmt,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match statement {
    ExpressionStatement(MethodCall(receiver, "call", arguments, call_span), _) => {
      match
        prepare_fiber_expression(
          MethodCall(receiver, "call", arguments, call_span),
          environment,
          context,
        ) {
        FiberExpressionFailed(issue) => return FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              ExpressionStatement(continuation(resumed), statement.span()),
              environment,
              context,
            )
          })
        FiberExpressionReady => ()
      }
      match
        prepare_direct_fiber_function_call(
          receiver,
          arguments,
          call_span,
          environment,
          context,
          fn(value) { StatementCompleted(value) },
        ) {
        Some(step) => step
        None => FiberStatementReady
      }
    }
    VariableStatement(
      name,
      Some(MethodCall(receiver, "call", arguments, call_span)),
      declaration_span
    ) => {
      match
        prepare_fiber_expression(
          MethodCall(receiver, "call", arguments, call_span),
          environment,
          context,
        ) {
        FiberExpressionFailed(issue) => return FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              VariableStatement(
                name,
                Some(continuation(resumed)),
                declaration_span,
              ),
              environment,
              context,
            )
          })
        FiberExpressionReady => ()
      }
      match
        prepare_direct_fiber_function_call(
          receiver,
          arguments,
          call_span,
          environment,
          context,
          fn(value) {
            if environment.bind(name, value) {
              StatementCompleted(value)
            } else {
              StatementFailed(
                Diagnostic::new(
                  Runtime,
                  DuplicateVariable,
                  "variable '{name}' is already declared in this scope",
                  declaration_span,
                ),
              )
            }
          },
        ) {
        Some(step) => step
        None => FiberStatementReady
      }
    }
    ReturnStatement(
      Some(MethodCall(receiver, "call", arguments, call_span)),
      return_span
    ) => {
      match
        prepare_fiber_expression(
          MethodCall(receiver, "call", arguments, call_span),
          environment,
          context,
        ) {
        FiberExpressionFailed(issue) => return FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              ReturnStatement(Some(continuation(resumed)), return_span),
              environment,
              context,
            )
          })
        FiberExpressionReady => ()
      }
      match
        prepare_direct_fiber_function_call(
          receiver,
          arguments,
          call_span,
          environment,
          context,
          fn(value) { StatementReturned(value, return_span) },
        ) {
        Some(step) => step
        None => FiberStatementReady
      }
    }
    ExpressionStatement(expression, span) =>
      match prepare_fiber_expression(expression, environment, context) {
        FiberExpressionReady => FiberStatementReady
        FiberExpressionFailed(issue) => FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              ExpressionStatement(continuation(resumed), span),
              environment,
              context,
            )
          })
      }
    VariableStatement(name, Some(initializer), span) =>
      match prepare_fiber_expression(initializer, environment, context) {
        FiberExpressionReady => FiberStatementReady
        FiberExpressionFailed(issue) => FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              VariableStatement(name, Some(continuation(resumed)), span),
              environment,
              context,
            )
          })
      }
    ReturnStatement(Some(value), span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady => FiberStatementReady
        FiberExpressionFailed(issue) => FiberStatementFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberStatementYielded(yielded, fn(resumed) {
            execute_fiber_statement(
              ReturnStatement(Some(continuation(resumed)), span),
              environment,
              context,
            )
          })
      }
    _ => FiberStatementReady
  }
}

///|
fn continue_fiber_sequence(
  step : FiberStatementStep,
  statements : Array[Stmt],
  next : Int,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match step {
    FiberStatementReady => abort("fiber statement was not executed")
    FiberStatementFailed(issue) => FiberStatementFailed(issue)
    FiberStatementYielded(value, continuation) =>
      FiberStatementYielded(value, fn(resumed) {
        continue_fiber_sequence(
          continuation(resumed),
          statements,
          next,
          last,
          environment,
          context,
        )
      })
    FiberStatementCompleted(result) =>
      match result {
        StatementCompleted(value) =>
          execute_fiber_sequence(statements, next, value, environment, context)
        StatementReturned(_, _)
        | StatementBroken(_)
        | StatementContinued(_)
        | StatementFailed(_) => FiberStatementCompleted(result)
      }
  }
}

///|
fn execute_fiber_sequence(
  statements : Array[Stmt],
  next : Int,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  if next >= statements.length() {
    return FiberStatementCompleted(StatementCompleted(last))
  }
  continue_fiber_sequence(
    execute_fiber_statement(statements[next], environment, context),
    statements,
    next + 1,
    last,
    environment,
    context,
  )
}

///|
fn finish_fiber_scope(
  step : FiberStatementStep,
  environment : Environment,
) -> FiberStatementStep {
  match step {
    FiberStatementReady => abort("fiber statement was not executed")
    FiberStatementFailed(issue) => {
      ignore(environment.pop_scope())
      FiberStatementFailed(issue)
    }
    FiberStatementCompleted(result) => {
      ignore(environment.pop_scope())
      FiberStatementCompleted(result)
    }
    FiberStatementYielded(value, continuation) =>
      FiberStatementYielded(value, fn(resumed) {
        finish_fiber_scope(continuation(resumed), environment)
      })
  }
}

///|
fn continue_fiber_while(
  step : FiberStatementStep,
  condition : Expr,
  body : Stmt,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match step {
    FiberStatementReady => abort("fiber statement was not executed")
    FiberStatementFailed(issue) => FiberStatementFailed(issue)
    FiberStatementYielded(value, continuation) =>
      FiberStatementYielded(value, fn(resumed) {
        continue_fiber_while(
          continuation(resumed),
          condition,
          body,
          last,
          environment,
          context,
        )
      })
    FiberStatementCompleted(result) =>
      match result {
        StatementCompleted(value) =>
          execute_fiber_while(condition, body, value, environment, context)
        StatementContinued(_) =>
          execute_fiber_while(condition, body, last, environment, context)
        StatementBroken(_) => FiberStatementCompleted(StatementCompleted(last))
        StatementReturned(_, _) | StatementFailed(_) =>
          FiberStatementCompleted(result)
      }
  }
}

///|
fn execute_fiber_while(
  condition : Expr,
  body : Stmt,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match prepare_fiber_expression(condition, environment, context) {
    FiberExpressionFailed(issue) => FiberStatementFailed(issue)
    FiberExpressionYielded(value, continuation) =>
      FiberStatementYielded(value, fn(resumed) {
        execute_fiber_while(
          continuation(resumed),
          body,
          last,
          environment,
          context,
        )
      })
    FiberExpressionReady =>
      match evaluate_expression_in(condition, environment, context) {
        EvaluationFailed(issue) => FiberStatementFailed(issue)
        EvaluationSucceeded(value) =>
          if !value.is_truthy() {
            FiberStatementCompleted(StatementCompleted(last))
          } else {
            continue_fiber_while(
              execute_fiber_statement(body, environment, context),
              condition,
              body,
              last,
              environment,
              context,
            )
          }
      }
  }
}

///|
fn continue_fiber_for(
  step : FiberStatementStep,
  name : String,
  iterable : Value,
  iterator : Value,
  body : Stmt,
  span : SourceSpan,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match step {
    FiberStatementReady => abort("fiber statement was not executed")
    FiberStatementFailed(issue) => FiberStatementFailed(issue)
    FiberStatementYielded(value, continuation) =>
      FiberStatementYielded(value, fn(resumed) {
        continue_fiber_for(
          continuation(resumed),
          name,
          iterable,
          iterator,
          body,
          span,
          last,
          environment,
          context,
        )
      })
    FiberStatementCompleted(result) =>
      match result {
        StatementCompleted(value) =>
          execute_fiber_for_iteration(
            name, iterable, iterator, body, span, value, environment, context,
          )
        StatementContinued(_) =>
          execute_fiber_for_iteration(
            name, iterable, iterator, body, span, last, environment, context,
          )
        StatementBroken(_) => FiberStatementCompleted(StatementCompleted(last))
        StatementReturned(_, _) | StatementFailed(_) =>
          FiberStatementCompleted(result)
      }
  }
}

///|
fn execute_fiber_for_iteration(
  name : String,
  iterable : Value,
  iterator : Value,
  body : Stmt,
  span : SourceSpan,
  last : Value,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  let next = match
    invoke_method(iterable, "iterate", [iterator], span, context) {
    EvaluationFailed(issue) => return FiberStatementFailed(issue)
    EvaluationSucceeded(BoolValue(false)) =>
      return FiberStatementCompleted(StatementCompleted(last))
    EvaluationSucceeded(value) => value
  }
  let item = match
    invoke_method(iterable, "iteratorValue", [next], span, context) {
    EvaluationFailed(issue) => return FiberStatementFailed(issue)
    EvaluationSucceeded(value) => value
  }
  ignore(environment.assign(name, item))
  continue_fiber_for(
    execute_fiber_statement(body, environment, context),
    name,
    iterable,
    next,
    body,
    span,
    last,
    environment,
    context,
  )
}

///|
fn execute_fiber_statement(
  statement : Stmt,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match statement {
    BlockStatement(statements, span) => {
      match context.step(span) {
        Some(issue) => return FiberStatementFailed(issue)
        None => ()
      }
      environment.push_scope()
      finish_fiber_scope(
        execute_fiber_sequence(
          statements,
          0,
          Value::null(),
          environment,
          context,
        ),
        environment,
      )
    }
    IfStatement(condition, then_branch, else_branch, span) => {
      match context.step(span) {
        Some(issue) => return FiberStatementFailed(issue)
        None => ()
      }
      match prepare_fiber_expression(condition, environment, context) {
        FiberExpressionFailed(issue) => FiberStatementFailed(issue)
        FiberExpressionYielded(value, continuation) =>
          FiberStatementYielded(value, fn(resumed) {
            execute_fiber_statement(
              IfStatement(continuation(resumed), then_branch, else_branch, span),
              environment,
              context,
            )
          })
        FiberExpressionReady =>
          match evaluate_expression_in(condition, environment, context) {
            EvaluationFailed(issue) => FiberStatementFailed(issue)
            EvaluationSucceeded(value) =>
              if value.is_truthy() {
                execute_fiber_statement(then_branch, environment, context)
              } else {
                match else_branch {
                  Some(branch) =>
                    execute_fiber_statement(branch, environment, context)
                  None =>
                    FiberStatementCompleted(StatementCompleted(Value::null()))
                }
              }
          }
      }
    }
    WhileStatement(condition, body, span) => {
      match context.step(span) {
        Some(issue) => return FiberStatementFailed(issue)
        None => ()
      }
      execute_fiber_while(condition, body, Value::null(), environment, context)
    }
    ForStatement(name, sequence, body, span) => {
      match context.step(span) {
        Some(issue) => return FiberStatementFailed(issue)
        None => ()
      }
      match prepare_fiber_expression(sequence, environment, context) {
        FiberExpressionFailed(issue) => FiberStatementFailed(issue)
        FiberExpressionYielded(value, continuation) =>
          FiberStatementYielded(value, fn(resumed) {
            execute_fiber_statement(
              ForStatement(name, continuation(resumed), body, span),
              environment,
              context,
            )
          })
        FiberExpressionReady =>
          match evaluate_expression_in(sequence, environment, context) {
            EvaluationFailed(issue) => FiberStatementFailed(issue)
            EvaluationSucceeded(iterable) => {
              environment.push_scope()
              ignore(environment.bind(name, Value::null()))
              finish_fiber_scope(
                execute_fiber_for_iteration(
                  name,
                  iterable,
                  Value::null(),
                  body,
                  span,
                  Value::null(),
                  environment,
                  context,
                ),
                environment,
              )
            }
          }
      }
    }
    _ =>
      match prepare_fiber_statement(statement, environment, context) {
        FiberStatementFailed(issue) => FiberStatementFailed(issue)
        FiberStatementYielded(value, continuation) =>
          FiberStatementYielded(value, continuation)
        FiberStatementCompleted(result) => FiberStatementCompleted(result)
        FiberStatementReady =>
          FiberStatementCompleted(
            execute_statement_in(statement, environment, context),
          )
      }
  }
}

///|
fn restore_fiber_caller(
  context : RuntimeContext,
  previous_fiber : Int,
  previous_source : String,
) -> Unit {
  context.current_fiber = previous_fiber
  context.current_source = previous_source
  context.call_depth = context.call_depth - 1
}

///|
fn abort_runtime_fiber(
  identifier : Int,
  issue : Diagnostic,
  previous_fiber : Int,
  previous_source : String,
  context : RuntimeContext,
) -> EvaluationResult {
  let fiber = context.fibers[identifier]
  fiber.state = 4
  fiber.error = Value::string(issue.message)
  fiber.pending = None
  restore_fiber_caller(context, previous_fiber, previous_source)
  EvaluationFailed(issue)
}

///|
fn resume_runtime_fiber(
  identifier : Int,
  input : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier <= 0 || identifier >= context.fibers.length() {
    return evaluation_error(
      InvalidFiberState,
      "fiber is not available in this runtime",
      span,
    )
  }
  let fiber = context.fibers[identifier]
  if fiber.state == 1 {
    return evaluation_error(
      InvalidFiberState,
      "cannot resume a running fiber",
      span,
    )
  }
  if fiber.state == 3 {
    return evaluation_error(
      InvalidFiberState,
      "cannot resume a completed fiber",
      span,
    )
  }
  if fiber.state == 4 {
    return evaluation_error(
      InvalidFiberState,
      "cannot resume an aborted fiber",
      span,
    )
  }
  if fiber.function_identifier < 0 ||
    fiber.function_identifier >= context.closures.length() {
    return evaluation_error(
      InvalidFiberState,
      "fiber function is not available",
      span,
    )
  }
  if context.call_depth >= context.max_call_depth {
    return evaluation_error(
      CallStackLimit,
      "fiber call depth limit exceeded",
      span,
    )
  }
  let closure = context.closures[fiber.function_identifier]
  if !fiber.initialized {
    fiber.environment = closure.environment.capture()
    fiber.environment.push_scope()
    if fiber.is_call_frame {
      for index = 0; index < closure.parameters.length(); index = index + 1 {
        ignore(
          fiber.environment.bind(
            closure.parameters[index],
            fiber.arguments[index],
          ),
        )
      }
    } else if closure.parameters.length() == 1 {
      ignore(fiber.environment.bind(closure.parameters[0], input))
    }
    fiber.initialized = true
  }
  let previous_fiber = context.current_fiber
  let previous_source = context.current_source
  context.current_fiber = fiber.identity
  context.current_source = closure.source_name
  context.call_depth = context.call_depth + 1
  fiber.state = 1
  let mut pending_input = Some(input)
  while true {
    let step = match fiber.pending {
      Some(continuation) => {
        fiber.pending = None
        let resumed = match pending_input {
          Some(value) => value
          None => Value::null()
        }
        pending_input = None
        continuation(resumed)
      }
      None => {
        if fiber.next_statement >= closure.body.length() {
          fiber.state = 3
          let result = fiber.last
          restore_fiber_caller(context, previous_fiber, previous_source)
          return EvaluationSucceeded(result)
        }
        let current = closure.body[fiber.next_statement]
        fiber.next_statement = fiber.next_statement + 1
        execute_fiber_statement(current, fiber.environment, context)
      }
    }
    match step {
      FiberStatementFailed(issue) =>
        return abort_runtime_fiber(
          identifier, issue, previous_fiber, previous_source, context,
        )
      FiberStatementYielded(value, continuation) => {
        fiber.pending = Some(continuation)
        fiber.state = 2
        restore_fiber_caller(context, previous_fiber, previous_source)
        return EvaluationSucceeded(value)
      }
      FiberStatementReady => abort("fiber statement was not executed")
      FiberStatementCompleted(result) =>
        match result {
          StatementCompleted(value) => fiber.last = value
          StatementReturned(value, _) => {
            fiber.state = 3
            fiber.last = value
            restore_fiber_caller(context, previous_fiber, previous_source)
            return EvaluationSucceeded(value)
          }
          StatementBroken(break_span) =>
            return abort_runtime_fiber(
              identifier,
              Diagnostic::new(
                Runtime,
                BreakOutsideLoop,
                "break cannot cross a fiber boundary",
                break_span,
              ),
              previous_fiber,
              previous_source,
              context,
            )
          StatementContinued(continue_span) =>
            return abort_runtime_fiber(
              identifier,
              Diagnostic::new(
                Runtime,
                ContinueOutsideLoop,
                "continue cannot cross a fiber boundary",
                continue_span,
              ),
              previous_fiber,
              previous_source,
              context,
            )
          StatementFailed(issue) =>
            return abort_runtime_fiber(
              identifier, issue, previous_fiber, previous_source, context,
            )
        }
    }
  }
  EvaluationSucceeded(Value::null())
}

///|
fn invoke_fiber_method(
  identifier : Int,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if identifier < 0 || identifier >= context.fibers.length() {
    return evaluation_error(
      InvalidFiberState,
      "fiber is not available in this runtime",
      span,
    )
  }
  match name {
    "call" | "try" | "transfer" => {
      if arguments.length() > 1 {
        return evaluation_error(
          InvalidArity,
          "Fiber.\{name} expects zero or one argument, received \{arguments.length()}",
          span,
        )
      }
      if identifier == 0 {
        return evaluation_error(
          InvalidFiberState,
          "the main fiber can only be a transfer target from a running fiber",
          span,
        )
      }
      let input = if arguments.length() == 0 {
        Value::null()
      } else {
        arguments[0]
      }
      match resume_runtime_fiber(identifier, input, span, context) {
        EvaluationSucceeded(value) => EvaluationSucceeded(value)
        EvaluationFailed(issue) =>
          if name == "try" {
            EvaluationSucceeded(Value::string(issue.message))
          } else {
            EvaluationFailed(issue)
          }
      }
    }
    "transferError" => {
      if arguments.length() != 1 {
        return invalid_collection_arity(
          "Fiber",
          name,
          1,
          arguments.length(),
          span,
        )
      }
      if identifier == 0 {
        return evaluation_error(
          FiberAborted,
          runtime_value_to_text(arguments[0], context, 0),
          span,
        )
      }
      let fiber = context.fibers[identifier]
      fiber.state = 4
      fiber.error = arguments[0]
      fiber.pending = None
      EvaluationSucceeded(arguments[0])
    }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "Fiber does not implement method '\{name}'",
        span,
      )
  }
}

///|
fn invoke_sequence_operation(
  receiver : Value,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  let owner = receiver.type_name()
  match name {
    "all" | "any" | "count" | "each" | "map" | "where" => {
      if arguments.length() != 1 {
        return invalid_collection_arity(
          owner,
          name,
          1,
          arguments.length(),
          span,
        )
      }
      let function_identifier = match expect_function_identifier(arguments[0]) {
        Some(identifier) => identifier
        None => return invalid_function_argument(owner, name, span)
      }
      if name == "map" {
        return EvaluationSucceeded(
          context.new_sequence_kind(SequenceMap(receiver, function_identifier)),
        )
      }
      if name == "where" {
        return EvaluationSucceeded(
          context.new_sequence_kind(
            SequenceWhere(receiver, function_identifier),
          ),
        )
      }
      let mut iterator = Value::null()
      let mut count = 0
      while true {
        let value = match advance_iterable(receiver, iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete => break
          IteratorAdvanced(next, value) => {
            iterator = next
            value
          }
        }
        match invoke_function(function_identifier, [value], span, context) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(result) => {
            if name == "all" && !result.is_truthy() {
              return EvaluationSucceeded(Value::bool(false))
            }
            if name == "any" && result.is_truthy() {
              return EvaluationSucceeded(Value::bool(true))
            }
            if name == "count" && result.is_truthy() {
              count = count + 1
            }
          }
        }
      }
      if name == "all" {
        EvaluationSucceeded(Value::bool(true))
      } else if name == "any" {
        EvaluationSucceeded(Value::bool(false))
      } else if name == "count" {
        EvaluationSucceeded(Value::number(Double::from_int(count)))
      } else {
        EvaluationSucceeded(Value::null())
      }
    }
    "contains" => {
      if arguments.length() != 1 {
        return invalid_collection_arity(
          owner,
          name,
          1,
          arguments.length(),
          span,
        )
      }
      let mut iterator = Value::null()
      while true {
        match advance_iterable(receiver, iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete => break
          IteratorAdvanced(next, value) => {
            iterator = next
            if value == arguments[0] {
              return EvaluationSucceeded(Value::bool(true))
            }
          }
        }
      }
      EvaluationSucceeded(Value::bool(false))
    }
    "join" => {
      if arguments.length() > 1 {
        return evaluation_error(
          InvalidArity,
          "\{owner}.join expects zero or one argument, received \{arguments.length()}",
          span,
        )
      }
      let separator = if arguments.length() == 0 {
        ""
      } else {
        match arguments[0] {
          StringValue(value) => value
          value =>
            return evaluation_error(
              InvalidOperand,
              "\{owner}.join separator must be a String, received \{value.type_name()}",
              span,
            )
        }
      }
      let mut iterator = Value::null()
      let mut text = ""
      let mut first = true
      while true {
        match advance_iterable(receiver, iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete => break
          IteratorAdvanced(next, value) => {
            iterator = next
            if first {
              first = false
            } else {
              text = text + separator
            }
            text = text + runtime_value_to_text(value, context, 0)
          }
        }
      }
      EvaluationSucceeded(Value::string(text))
    }
    "reduce" => {
      if arguments.length() != 1 && arguments.length() != 2 {
        return evaluation_error(
          InvalidArity,
          "\{owner}.reduce expects one or two arguments, received \{arguments.length()}",
          span,
        )
      }
      let function_position = arguments.length() - 1
      let function_identifier = match
        expect_function_identifier(arguments[function_position]) {
        Some(identifier) => identifier
        None => return invalid_function_argument(owner, name, span)
      }
      let mut iterator = Value::null()
      let mut accumulator = arguments[0]
      if arguments.length() == 1 {
        match advance_iterable(receiver, iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete =>
            return evaluation_error(
              InvalidOperand,
              "\{owner}.reduce cannot reduce an empty sequence without a seed",
              span,
            )
          IteratorAdvanced(next, value) => {
            iterator = next
            accumulator = value
          }
        }
      }
      while true {
        let value = match advance_iterable(receiver, iterator, span, context) {
          IteratorAdvanceFailed(issue) => return EvaluationFailed(issue)
          IteratorComplete => break
          IteratorAdvanced(next, value) => {
            iterator = next
            value
          }
        }
        match
          invoke_function(
            function_identifier,
            [accumulator, value],
            span,
            context,
          ) {
          EvaluationFailed(issue) => return EvaluationFailed(issue)
          EvaluationSucceeded(value) => accumulator = value
        }
      }
      EvaluationSucceeded(accumulator)
    }
    "skip" | "take" => {
      if arguments.length() != 1 {
        return invalid_collection_arity(
          owner,
          name,
          1,
          arguments.length(),
          span,
        )
      }
      let count = match non_negative_count(arguments[0]) {
        Some(value) => value
        None =>
          return evaluation_error(
            InvalidOperand,
            "\{owner}.\{name} count must be a non-negative integer",
            span,
          )
      }
      let kind = if name == "skip" {
        SequenceSkip(receiver, count)
      } else {
        SequenceTake(receiver, count)
      }
      EvaluationSucceeded(context.new_sequence_kind(kind))
    }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "\{owner} does not implement method '\{name}'",
        span,
      )
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
  if name != "iterate" && name != "iteratorValue" {
    return invoke_sequence_operation(
      Value::sequence(identifier),
      name,
      arguments,
      span,
      context,
    )
  }
  if arguments.length() != 1 {
    return invalid_collection_arity(
      "Sequence",
      name,
      1,
      arguments.length(),
      span,
    )
  }
  if name == "iteratorValue" {
    return match arguments[0] {
      IteratorValue(iterator_identifier) =>
        if iterator_identifier < 0 ||
          iterator_identifier >= context.iterators.length() ||
          context.iterators[iterator_identifier].sequence_identifier !=
          identifier ||
          context.iterators[iterator_identifier].completed {
          evaluation_error(
            InvalidOperand,
            "Sequence iterator is outside the valid range",
            span,
          )
        } else {
          EvaluationSucceeded(context.iterators[iterator_identifier].current)
        }
      value =>
        evaluation_error(
          InvalidOperand,
          "Sequence iterator must be an Iterator, received \{value.type_name()}",
          span,
        )
    }
  }
  let iterator_identifier = match arguments[0] {
    NullValue => {
      let next = context.iterators.length()
      context.iterators.push({
        sequence_identifier: identifier,
        source_iterator: Value::null(),
        current: Value::null(),
        yielded: 0,
        started: false,
        completed: false,
      })
      next
    }
    IteratorValue(existing) =>
      if existing < 0 ||
        existing >= context.iterators.length() ||
        context.iterators[existing].sequence_identifier != identifier {
        return evaluation_error(
          InvalidOperand,
          "Sequence iterator does not belong to this sequence",
          span,
        )
      } else {
        existing
      }
    value =>
      return evaluation_error(
        InvalidOperand,
        "Sequence iterator must be null or Iterator, received \{value.type_name()}",
        span,
      )
  }
  advance_sequence_iterator(iterator_identifier, span, context)
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
    "addAll" =>
      if arguments.length() != 1 {
        invalid_collection_arity("List", name, 1, arguments.length(), span)
      } else {
        match collect_iterable_values(arguments[0], span, context) {
          ValueCollectionFailed(issue) => EvaluationFailed(issue)
          ValuesCollected(values) => {
            for value in values {
              items.push(value)
            }
            EvaluationSucceeded(arguments[0])
          }
        }
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
    "sort" => {
      if arguments.length() > 1 {
        return evaluation_error(
          InvalidArity,
          "List.sort expects zero or one argument, received \{arguments.length()}",
          span,
        )
      }
      let comparer = if arguments.length() == 0 {
        None
      } else {
        match arguments[0] {
          FunctionValue(identifier) => Some(identifier)
          _ => return invalid_function_argument("List", name, span)
        }
      }
      for index = 1; index < items.length(); index = index + 1 {
        let mut position = index
        while position > 0 {
          let before = match comparer {
            Some(identifier) =>
              match
                invoke_function(
                  identifier,
                  [items[position], items[position - 1]],
                  span,
                  context,
                ) {
                EvaluationFailed(issue) => return EvaluationFailed(issue)
                EvaluationSucceeded(value) => value.is_truthy()
              }
            None =>
              match (items[position], items[position - 1]) {
                (NumberValue(left), NumberValue(right)) => left < right
                (StringValue(left), StringValue(right)) => left < right
                (left, right) =>
                  return evaluation_error(
                    InvalidOperand,
                    "List.sort cannot compare \{left.type_name()} and \{right.type_name()}",
                    span,
                  )
              }
          }
          if !before {
            break
          }
          let temporary = items[position]
          items[position] = items[position - 1]
          items[position - 1] = temporary
          position = position - 1
        }
      }
      EvaluationSucceeded(Value::list(identifier))
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
      invoke_sequence_operation(
        Value::list(identifier),
        name,
        arguments,
        span,
        context,
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
  if name == "iterate" || name == "iteratorValue" {
    if arguments.length() != 1 {
      return invalid_collection_arity("Map", name, 1, arguments.length(), span)
    }
    let sequence_identifier = match arguments[0] {
      NullValue => {
        let values : Array[Value] = []
        for entry in entries {
          values.push(context.new_map_entry(entry.key, entry.value))
        }
        match context.new_sequence(values) {
          SequenceValue(sequence_identifier) => sequence_identifier
          _ => abort("new_sequence must return a Sequence")
        }
      }
      IteratorValue(iterator_identifier) =>
        if iterator_identifier < 0 ||
          iterator_identifier >= context.iterators.length() {
          return evaluation_error(
            InvalidOperand,
            "Map iterator is not available",
            span,
          )
        } else {
          context.iterators[iterator_identifier].sequence_identifier
        }
      value =>
        return evaluation_error(
          InvalidOperand,
          "Map iterator must be null or Iterator, received \{value.type_name()}",
          span,
        )
    }
    return invoke_sequence_method(
      sequence_identifier, name, arguments, span, context,
    )
  }
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
      invoke_sequence_operation(
        Value::map(identifier),
        name,
        arguments,
        span,
        context,
      )
  }
}

///|
fn parse_decimal_string(text : String) -> Double? {
  let characters = text.to_array()
  if characters.length() == 0 {
    return None
  }
  let mut index = 0
  let mut sign = 1.0
  if characters[index].to_int() == 45 || characters[index].to_int() == 43 {
    if characters[index].to_int() == 45 {
      sign = -1.0
    }
    index = index + 1
  }
  let mut value = 0.0
  let mut digits = 0
  while index < characters.length() && is_digit(characters[index].to_int()) {
    value = value * 10.0 + Double::from_int(characters[index].to_int() - 48)
    digits = digits + 1
    index = index + 1
  }
  if index < characters.length() && characters[index].to_int() == 46 {
    index = index + 1
    let mut place = 0.1
    while index < characters.length() && is_digit(characters[index].to_int()) {
      value = value + Double::from_int(characters[index].to_int() - 48) * place
      place = place * 0.1
      digits = digits + 1
      index = index + 1
    }
  }
  if digits == 0 {
    return None
  }
  if index < characters.length() &&
    (characters[index].to_int() == 69 || characters[index].to_int() == 101) {
    index = index + 1
    let mut exponent_sign = 1
    if index < characters.length() &&
      (characters[index].to_int() == 45 || characters[index].to_int() == 43) {
      if characters[index].to_int() == 45 {
        exponent_sign = -1
      }
      index = index + 1
    }
    let mut exponent = 0
    let mut exponent_digits = 0
    while index < characters.length() && is_digit(characters[index].to_int()) {
      if exponent <= 400 {
        exponent = exponent * 10 + characters[index].to_int() - 48
      }
      exponent_digits = exponent_digits + 1
      index = index + 1
    }
    if exponent_digits == 0 {
      return None
    }
    if exponent > 400 {
      value = if exponent_sign > 0 {
        if value == 0.0 {
          0.0
        } else {
          @double.infinity
        }
      } else {
        0.0
      }
    } else {
      let mut factor = 1.0
      for power_index = 0; power_index < exponent; power_index = power_index + 1 {
        if exponent_sign > 0 {
          factor = factor * 10.0
        } else {
          factor = factor * 0.1
        }
      }
      value = value * factor
    }
  }
  if index != characters.length() {
    None
  } else {
    Some(value * sign)
  }
}

///|
fn invoke_core_class_method(
  class_value : CoreClass,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match (class_value, name) {
    (ObjectClass, "same") =>
      if arguments.length() != 2 {
        invalid_collection_arity("Object", name, 2, arguments.length(), span)
      } else {
        EvaluationSucceeded(Value::bool(arguments[0] == arguments[1]))
      }
    (FiberClass, "new") =>
      if arguments.length() != 1 {
        invalid_collection_arity("Fiber", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          FunctionValue(identifier) =>
            if identifier < 0 || identifier >= context.closures.length() {
              evaluation_error(
                InvalidOperand,
                "Fiber.new function is not available",
                span,
              )
            } else if context.closures[identifier].parameters.length() > 1 {
              evaluation_error(
                InvalidArity,
                "Fiber.new function may take zero or one parameter",
                span,
              )
            } else {
              EvaluationSucceeded(context.new_fiber(identifier))
            }
          value =>
            evaluation_error(
              InvalidOperand,
              "Fiber.new expects a function, received \{value.type_name()}",
              span,
            )
        }
      }
    (FiberClass, "abort") =>
      if arguments.length() != 1 {
        invalid_collection_arity("Fiber", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          NullValue => EvaluationSucceeded(Value::null())
          value =>
            evaluation_error(
              FiberAborted,
              runtime_value_to_text(value, context, 0),
              span,
            )
        }
      }
    (FiberClass, "yield") | (FiberClass, "suspend") =>
      evaluation_error(
        InvalidFiberState,
        "Fiber.\{name} must appear in a resumable top-level fiber statement",
        span,
      )
    (FnClass, "new") =>
      if arguments.length() != 1 {
        invalid_collection_arity("Fn", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          FunctionValue(_) => EvaluationSucceeded(arguments[0])
          value =>
            evaluation_error(
              InvalidOperand,
              "Fn.new expects a function, received \{value.type_name()}",
              span,
            )
        }
      }
    (ListClass, "new") =>
      if arguments.length() != 0 {
        invalid_collection_arity("List", name, 0, arguments.length(), span)
      } else {
        EvaluationSucceeded(context.new_list([]))
      }
    (ListClass, "filled") =>
      if arguments.length() != 2 {
        invalid_collection_arity("List", name, 2, arguments.length(), span)
      } else {
        match non_negative_count(arguments[0]) {
          None =>
            evaluation_error(
              InvalidOperand,
              "List.filled size must be a non-negative integer",
              span,
            )
          Some(count) => {
            let values : Array[Value] = []
            for index = 0; index < count; index = index + 1 {
              values.push(arguments[1])
            }
            EvaluationSucceeded(context.new_list(values))
          }
        }
      }
    (MapClass, "new") =>
      if arguments.length() != 0 {
        invalid_collection_arity("Map", name, 0, arguments.length(), span)
      } else {
        EvaluationSucceeded(context.new_map())
      }
    (NumClass, "fromString") =>
      if arguments.length() != 1 {
        invalid_collection_arity("Num", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          StringValue(text) =>
            match parse_decimal_string(text) {
              Some(number) => EvaluationSucceeded(Value::number(number))
              None => EvaluationSucceeded(Value::null())
            }
          value =>
            evaluation_error(
              InvalidOperand,
              "Num.fromString expects a String, received \{value.type_name()}",
              span,
            )
        }
      }
    (StringClass, "fromCodePoint") =>
      if arguments.length() != 1 {
        invalid_collection_arity("String", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          NumberValue(number) => {
            let code_point = number.to_int()
            if Double::from_int(code_point) != number ||
              code_point < 0 ||
              code_point > 0x10ffff ||
              (code_point >= 0xd800 && code_point <= 0xdfff) {
              evaluation_error(
                InvalidOperand,
                "String.fromCodePoint expects a valid Unicode code point",
                span,
              )
            } else {
              EvaluationSucceeded(
                Value::string(code_point.unsafe_to_char().to_string()),
              )
            }
          }
          value =>
            evaluation_error(
              InvalidOperand,
              "String.fromCodePoint expects a Num, received \{value.type_name()}",
              span,
            )
        }
      }
    (StringClass, "fromByte") =>
      if arguments.length() != 1 {
        invalid_collection_arity("String", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          NumberValue(number) => {
            let byte = number.to_int()
            if Double::from_int(byte) != number || byte < 0 || byte > 255 {
              evaluation_error(
                InvalidOperand,
                "String.fromByte expects an integer from 0 through 255",
                span,
              )
            } else {
              EvaluationSucceeded(
                Value::string(byte.unsafe_to_char().to_string()),
              )
            }
          }
          value =>
            evaluation_error(
              InvalidOperand,
              "String.fromByte expects a Num, received \{value.type_name()}",
              span,
            )
        }
      }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "\{class_value.name()} does not implement static method '\{name}'",
        span,
      )
  }
}

///|
fn number_argument(value : Value) -> Double? {
  match value {
    NumberValue(number) => Some(number)
    _ => None
  }
}

///|
fn invoke_number_method(
  number : Double,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if name != "atan" &&
    name != "min" &&
    name != "max" &&
    name != "pow" &&
    name != "clamp" {
    return evaluation_error(
      UndefinedMethod,
      "Num does not implement method '\{name}'",
      span,
    )
  }
  let expected = if name == "clamp" { 2 } else { 1 }
  if arguments.length() != expected {
    return invalid_collection_arity(
      "Num",
      name,
      expected,
      arguments.length(),
      span,
    )
  }
  let first = match number_argument(arguments[0]) {
    Some(value) => value
    None =>
      return evaluation_error(
        InvalidOperand,
        "Num.\{name} expects Num arguments",
        span,
      )
  }
  match name {
    "atan" => EvaluationSucceeded(Value::number(@math.atan2(number, first)))
    "min" => EvaluationSucceeded(Value::number(number.min(first)))
    "max" => EvaluationSucceeded(Value::number(number.max(first)))
    "pow" => EvaluationSucceeded(Value::number(@math.pow(number, first)))
    "clamp" => {
      let maximum = match number_argument(arguments[1]) {
        Some(value) => value
        None =>
          return evaluation_error(
            InvalidOperand,
            "Num.clamp expects Num arguments",
            span,
          )
      }
      if first > maximum {
        evaluation_error(
          InvalidOperand,
          "Num.clamp minimum must not exceed maximum",
          span,
        )
      } else {
        EvaluationSucceeded(
          Value::number(
            if number < first {
              first
            } else if number > maximum {
              maximum
            } else {
              number
            },
          ),
        )
      }
    }
    _ =>
      evaluation_error(
        UndefinedMethod,
        "Num does not implement method '\{name}'",
        span,
      )
  }
}

///|
fn RuntimeContext::write_output(
  self : RuntimeContext,
  text : String,
  newline : Bool,
) -> Unit {
  if self.output_line_open {
    let index = self.output.length() - 1
    self.output[index] = self.output[index] + text
  } else {
    self.output.push(text)
  }
  self.output_line_open = !newline
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
      if name == "print" || name == "write" {
        if arguments.length() == 0 {
          if name == "write" {
            evaluation_error(
              InvalidArity,
              "System.write expects one argument, received zero",
              span,
            )
          } else {
            context.write_output("", true)
            EvaluationSucceeded(Value::null())
          }
        } else if arguments.length() == 1 {
          let value = arguments[0]
          context.write_output(
            runtime_value_to_text(value, context, 0),
            name == "print",
          )
          EvaluationSucceeded(value)
        } else {
          evaluation_error(
            InvalidArity,
            "System.\{name} expects \{if name == "print" { "zero or one" } else { "one" }} argument, received \{arguments.length()}",
            span,
          )
        }
      } else if name == "printAll" || name == "writeAll" {
        if arguments.length() != 1 {
          return invalid_collection_arity(
            "System",
            name,
            1,
            arguments.length(),
            span,
          )
        }
        match collect_iterable_values(arguments[0], span, context) {
          ValueCollectionFailed(issue) => EvaluationFailed(issue)
          ValuesCollected(values) => {
            let mut text = ""
            for value in values {
              text = text + runtime_value_to_text(value, context, 0)
            }
            context.write_output(text, name == "printAll")
            EvaluationSucceeded(Value::null())
          }
        }
      } else if name == "gc" {
        if arguments.length() != 0 {
          invalid_collection_arity("System", name, 0, arguments.length(), span)
        } else {
          EvaluationSucceeded(Value::null())
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
    FiberValue(identifier) =>
      invoke_fiber_method(identifier, name, arguments, span, context)
    NumberValue(number) => invoke_number_method(number, name, arguments, span)
    StringValue(text) =>
      invoke_string_method(text, name, arguments, span, context)
    ListValue(identifier) =>
      invoke_list_method(identifier, name, arguments, span, context)
    MapValue(identifier) =>
      invoke_map_method(identifier, name, arguments, span, context)
    SequenceValue(identifier) =>
      invoke_sequence_method(identifier, name, arguments, span, context)
    RangeValue(from, to, inclusive) =>
      invoke_range_method(from, to, inclusive, name, arguments, span, context)
    CoreClassValue(class_value) =>
      invoke_core_class_method(class_value, name, arguments, span, context)
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
fn read_sequence_property(
  receiver : Value,
  name : String,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if name == "toString" {
    return EvaluationSucceeded(
      Value::string(runtime_value_to_text(receiver, context, 0)),
    )
  }
  if name != "count" && name != "isEmpty" && name != "toList" {
    return evaluation_error(
      UndefinedMethod,
      "\{receiver.type_name()} does not implement getter '\{name}'",
      span,
    )
  }
  if name == "isEmpty" {
    return match advance_iterable(receiver, Value::null(), span, context) {
      IteratorAdvanceFailed(issue) => EvaluationFailed(issue)
      IteratorComplete => EvaluationSucceeded(Value::bool(true))
      IteratorAdvanced(_, _) => EvaluationSucceeded(Value::bool(false))
    }
  }
  match collect_iterable_values(receiver, span, context) {
    ValueCollectionFailed(issue) => EvaluationFailed(issue)
    ValuesCollected(values) =>
      if name == "count" {
        EvaluationSucceeded(Value::number(Double::from_int(values.length())))
      } else {
        EvaluationSucceeded(context.new_list(values))
      }
  }
}

///|
fn read_core_class_property(
  class_value : CoreClass,
  name : String,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if name == "name" || name == "toString" {
    return EvaluationSucceeded(Value::string(class_value.name()))
  }
  if name == "supertype" {
    return if class_value == ObjectClass {
      EvaluationSucceeded(Value::null())
    } else if class_value == ListClass ||
      class_value == MapClass ||
      class_value == RangeClass ||
      class_value == StringClass {
      EvaluationSucceeded(Value::core_class(SequenceClass))
    } else {
      EvaluationSucceeded(Value::core_class(ObjectClass))
    }
  }
  if class_value == FiberClass && name == "current" {
    return EvaluationSucceeded(Value::fiber(context.current_fiber))
  }
  if class_value == NumClass {
    return match name {
      "infinity" => EvaluationSucceeded(Value::number(@double.infinity))
      "nan" => EvaluationSucceeded(Value::number(@double.not_a_number))
      "pi" => EvaluationSucceeded(Value::number(@math.PI))
      "tau" => EvaluationSucceeded(Value::number(@math.PI * 2.0))
      "largest" => EvaluationSucceeded(Value::number(1.7976931348623157e308))
      "smallest" => EvaluationSucceeded(Value::number(5.0e-324))
      "maxSafeInteger" => EvaluationSucceeded(Value::number(9007199254740991.0))
      "minSafeInteger" =>
        EvaluationSucceeded(Value::number(-9007199254740991.0))
      _ =>
        evaluation_error(
          UndefinedMethod,
          "Num does not implement static getter '\{name}'",
          span,
        )
    }
  }
  evaluation_error(
    UndefinedMethod,
    "\{class_value.name()} does not implement static getter '\{name}'",
    span,
  )
}

///|
fn read_number_property(
  number : Double,
  name : String,
  span : SourceSpan,
) -> EvaluationResult {
  let truncated = if number < 0.0 { number.ceil() } else { number.floor() }
  match name {
    "abs" => EvaluationSucceeded(Value::number(number.abs()))
    "acos" => EvaluationSucceeded(Value::number(@math.acos(number)))
    "asin" => EvaluationSucceeded(Value::number(@math.asin(number)))
    "atan" => EvaluationSucceeded(Value::number(@math.atan(number)))
    "cbrt" => EvaluationSucceeded(Value::number(@math.cbrt(number)))
    "ceil" => EvaluationSucceeded(Value::number(number.ceil()))
    "cos" => EvaluationSucceeded(Value::number(@math.cos(number)))
    "exp" => EvaluationSucceeded(Value::number(@math.exp(number)))
    "floor" => EvaluationSucceeded(Value::number(number.floor()))
    "fraction" => EvaluationSucceeded(Value::number(number - truncated))
    "isInfinity" => EvaluationSucceeded(Value::bool(number.is_inf()))
    "isInteger" =>
      EvaluationSucceeded(
        Value::bool(!number.is_nan() && !number.is_inf() && truncated == number),
      )
    "isNan" => EvaluationSucceeded(Value::bool(number.is_nan()))
    "log" => EvaluationSucceeded(Value::number(@math.ln(number)))
    "log2" => EvaluationSucceeded(Value::number(@math.log2(number)))
    "round" => EvaluationSucceeded(Value::number(number.round()))
    "sign" => EvaluationSucceeded(Value::number(number.signum()))
    "sin" => EvaluationSucceeded(Value::number(@math.sin(number)))
    "sqrt" => EvaluationSucceeded(Value::number(number.sqrt()))
    "tan" => EvaluationSucceeded(Value::number(@math.tan(number)))
    "truncate" => EvaluationSucceeded(Value::number(truncated))
    "toString" =>
      EvaluationSucceeded(Value::string(Value::number(number).to_text()))
    "type" => EvaluationSucceeded(Value::core_class(NumClass))
    _ =>
      evaluation_error(
        UndefinedMethod,
        "Num does not implement getter '\{name}'",
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
          } else if name == "type" {
            EvaluationSucceeded(Value::class_value(class_identifier))
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
          if name == "toString" || name == "name" {
            EvaluationSucceeded(Value::string(context.classes[identifier].name))
          } else if name == "type" {
            EvaluationSucceeded(Value::core_class(ClassClass))
          } else if name == "supertype" {
            match context.classes[identifier].superclass {
              Some(superclass) =>
                EvaluationSucceeded(Value::class_value(superclass))
              None => EvaluationSucceeded(Value::core_class(ObjectClass))
            }
          } else {
            evaluation_error(
              UndefinedMethod,
              "\{context.classes[identifier].name} does not implement static getter '\{name}'",
              span,
            )
          }
      }
    CoreClassValue(class_value) =>
      if name == "type" {
        EvaluationSucceeded(Value::core_class(ClassClass))
      } else {
        read_core_class_property(class_value, name, span, context)
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
    FunctionValue(identifier) =>
      if name == "arity" {
        if identifier < 0 || identifier >= context.closures.length() {
          evaluation_error(InvalidOperand, "function is not available", span)
        } else {
          EvaluationSucceeded(
            Value::number(
              Double::from_int(context.closures[identifier].parameters.length()),
            ),
          )
        }
      } else if name == "type" {
        EvaluationSucceeded(Value::core_class(FnClass))
      } else if name == "toString" {
        EvaluationSucceeded(Value::string("<fn>"))
      } else {
        evaluation_error(
          UndefinedMethod,
          "Fn does not implement getter '\{name}'",
          span,
        )
      }
    NumberValue(number) => read_number_property(number, name, span)
    StringValue(text) =>
      match name {
        "count" =>
          EvaluationSucceeded(
            Value::number(Double::from_int(text.char_length())),
          )
        "toString" => EvaluationSucceeded(receiver)
        "bytes" => {
          let values : Array[Value] = []
          for character in text.to_array() {
            let code = character.to_int()
            if code <= 0x7f {
              values.push(Value::number(Double::from_int(code)))
            } else if code <= 0x7ff {
              values.push(Value::number(Double::from_int(0xc0 | (code >> 6))))
              values.push(Value::number(Double::from_int(0x80 | (code & 0x3f))))
            } else if code <= 0xffff {
              values.push(Value::number(Double::from_int(0xe0 | (code >> 12))))
              values.push(
                Value::number(Double::from_int(0x80 | ((code >> 6) & 0x3f))),
              )
              values.push(Value::number(Double::from_int(0x80 | (code & 0x3f))))
            } else {
              values.push(Value::number(Double::from_int(0xf0 | (code >> 18))))
              values.push(
                Value::number(Double::from_int(0x80 | ((code >> 12) & 0x3f))),
              )
              values.push(
                Value::number(Double::from_int(0x80 | ((code >> 6) & 0x3f))),
              )
              values.push(Value::number(Double::from_int(0x80 | (code & 0x3f))))
            }
          }
          EvaluationSucceeded(context.new_sequence(values))
        }
        "codePoints" => {
          let values : Array[Value] = []
          for character in text.to_array() {
            values.push(Value::number(Double::from_int(character.to_int())))
          }
          EvaluationSucceeded(context.new_sequence(values))
        }
        "type" => EvaluationSucceeded(Value::core_class(StringClass))
        _ => read_sequence_property(receiver, name, span, context)
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
        "type" => EvaluationSucceeded(Value::core_class(RangeClass))
        _ => read_sequence_property(receiver, name, span, context)
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
          "type" => EvaluationSucceeded(Value::core_class(ListClass))
          _ => read_sequence_property(receiver, name, span, context)
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
          "type" => EvaluationSucceeded(Value::core_class(MapClass))
          _ => read_sequence_property(receiver, name, span, context)
        }
      }
    SequenceValue(identifier) =>
      if identifier < 0 || identifier >= context.sequences.length() {
        evaluation_error(InvalidOperand, "sequence is not available", span)
      } else if name == "type" {
        EvaluationSucceeded(Value::core_class(SequenceClass))
      } else {
        read_sequence_property(receiver, name, span, context)
      }
    FiberValue(identifier) =>
      if identifier < 0 || identifier >= context.fibers.length() {
        evaluation_error(InvalidFiberState, "fiber is not available", span)
      } else {
        let fiber = context.fibers[identifier]
        match name {
          "isDone" =>
            EvaluationSucceeded(
              Value::bool(fiber.state == 3 || fiber.state == 4),
            )
          "error" => EvaluationSucceeded(fiber.error)
          "type" => EvaluationSucceeded(Value::core_class(FiberClass))
          "toString" => EvaluationSucceeded(Value::string("<fiber>"))
          _ =>
            evaluation_error(
              UndefinedMethod,
              "Fiber does not implement getter '\{name}'",
              span,
            )
        }
      }
    MapEntryValue(identifier) =>
      if identifier < 0 || identifier >= context.map_entries.length() {
        evaluation_error(InvalidOperand, "map entry is not available", span)
      } else {
        let entry = context.map_entries[identifier]
        match name {
          "key" => EvaluationSucceeded(entry.key)
          "value" => EvaluationSucceeded(entry.value)
          "toString" =>
            EvaluationSucceeded(
              Value::string(runtime_value_to_text(receiver, context, 0)),
            )
          "type" => EvaluationSucceeded(Value::core_class(ObjectClass))
          _ =>
            evaluation_error(
              UndefinedMethod,
              "MapEntry does not implement getter '\{name}'",
              span,
            )
        }
      }
    SystemValue =>
      if name == "name" || name == "toString" {
        EvaluationSucceeded(Value::string("System"))
      } else if name == "type" {
        EvaluationSucceeded(Value::core_class(ClassClass))
      } else if name == "supertype" {
        EvaluationSucceeded(Value::core_class(ObjectClass))
      } else {
        evaluation_error(
          UndefinedMethod,
          "System does not implement static getter '\{name}'",
          span,
        )
      }
    value =>
      if name == "toString" {
        EvaluationSucceeded(Value::string(value.to_text()))
      } else if name == "type" {
        EvaluationSucceeded(core_class_for_value(value, context))
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
        source_name: context.current_source,
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
              evaluate_binary_values(
                operator, left_value, right_value, span, context,
              )
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
    StringValue(text) => context.new_sequence(string_items(text))
    value => value
  }
  match iterable {
    RangeValue(_, _, _)
    | ListValue(_)
    | MapValue(_)
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
priv enum ModuleExecutionResult {
  ModuleExecuted(Environment, Value)
  ModuleExecutionFailed(Array[Diagnostic])
}

///|
fn find_runtime_module(context : RuntimeContext, name : String) -> Int? {
  for index = 0; index < context.modules.length(); index = index + 1 {
    if context.modules[index].name == name {
      return Some(index)
    }
  }
  None
}

///|
fn execute_module_source(
  name : String,
  source : String,
  context : RuntimeContext,
) -> ModuleExecutionResult {
  match find_runtime_module(context, name) {
    Some(index) =>
      if context.modules[index].state == 0 {
        return ModuleExecutionFailed([
          Diagnostic::new(
            Runtime,
            CircularImport,
            "circular import reached module '\{name}'",
            SourceSpan::empty(),
          ).with_source(name),
        ])
      } else if context.modules[index].state == 1 {
        return ModuleExecuted(context.modules[index].environment, Value::null())
      } else {
        return ModuleExecutionFailed([
          Diagnostic::new(
            Runtime,
            ModuleNotFound,
            "module '\{name}' previously failed to load",
            SourceSpan::empty(),
          ).with_source(name),
        ])
      }
    None => ()
  }
  let environment = Environment::new()
  bind_core_globals(environment)
  let module_index = context.modules.length()
  context.modules.push({ name, environment, state: 0, })
  let statements = match parse_program(source) {
    ProgramParseFailed(diagnostics) => {
      context.modules[module_index].state = 2
      let issues : Array[Diagnostic] = []
      for diagnostic in diagnostics {
        issues.push(diagnostic.with_source(name))
      }
      return ModuleExecutionFailed(issues)
    }
    ProgramParsed(statements) => statements
  }
  let previous_source = context.current_source
  context.current_source = name
  let result = execute_statements_in(statements, environment, context)
  context.current_source = previous_source
  match result {
    StatementCompleted(value) => {
      context.modules[module_index].state = 1
      ModuleExecuted(environment, value)
    }
    StatementFailed(issue) => {
      context.modules[module_index].state = 2
      ModuleExecutionFailed([issue.with_source(name)])
    }
    StatementReturned(_, span) => {
      context.modules[module_index].state = 2
      ModuleExecutionFailed([
        Diagnostic::new(
          Runtime,
          ReturnOutsideFunction,
          "return can only be used inside a function",
          span,
        ).with_source(name),
      ])
    }
    StatementBroken(span) => {
      context.modules[module_index].state = 2
      ModuleExecutionFailed([
        Diagnostic::new(
          Runtime,
          BreakOutsideLoop,
          "break can only be used inside a loop",
          span,
        ).with_source(name),
      ])
    }
    StatementContinued(span) => {
      context.modules[module_index].state = 2
      ModuleExecutionFailed([
        Diagnostic::new(
          Runtime,
          ContinueOutsideLoop,
          "continue can only be used inside a loop",
          span,
        ).with_source(name),
      ])
    }
  }
}

///|
fn load_imported_module(
  importer : String,
  specifier : String,
  span : SourceSpan,
  context : RuntimeContext,
) -> ModuleExecutionResult {
  match (context.loader)(importer, specifier) {
    ModuleLoadFailed(message) =>
      ModuleExecutionFailed([
        Diagnostic::new(Runtime, ModuleNotFound, message, span).with_source(
          importer,
        ),
      ])
    ModuleLoaded(name, source) =>
      match execute_module_source(name, source, context) {
        ModuleExecuted(environment, value) => ModuleExecuted(environment, value)
        ModuleExecutionFailed(issues) => {
          let traced : Array[Diagnostic] = []
          for issue in issues {
            traced.push(
              issue.with_frame(
                CallFrame::new("import \"\{specifier}\"", importer, span),
              ),
            )
          }
          ModuleExecutionFailed(traced)
        }
      }
  }
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
    ImportStatement(specifier, bindings, span) =>
      match
        load_imported_module(context.current_source, specifier, span, context) {
        ModuleExecutionFailed(issues) => StatementFailed(issues[0])
        ModuleExecuted(module_environment, _) => {
          for binding in bindings {
            let value = match module_environment.get(binding.name) {
              Some(value) => value
              None =>
                return StatementFailed(
                  Diagnostic::new(
                    Runtime,
                    UndefinedExport,
                    "module '\{specifier}' does not define '\{binding.name}'",
                    span,
                  ).with_source(context.current_source),
                )
            }
            if !environment.bind(binding.local_name, value) {
              return StatementFailed(
                Diagnostic::new(
                  Runtime,
                  DuplicateVariable,
                  "imported name '\{binding.local_name}' is already declared in this scope",
                  span,
                ).with_source(context.current_source),
              )
            }
          }
          StatementCompleted(Value::null())
        }
      }
    ClassStatement(name, superclass_name, methods, is_foreign, span) => {
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
      let foreign_binding = if is_foreign {
        match
          find_foreign_class_binding(context, context.current_source, name) {
          Some(binding) => Some(binding)
          None =>
            return StatementFailed(
              Diagnostic::new(
                Runtime,
                ForeignClassBindingMissing,
                "no foreign class binding for \{context.current_source}:\{name}",
                span,
              ),
            )
        }
      } else {
        None
      }
      let identifier = context.classes.length()
      context.classes.push({
        name,
        superclass,
        methods,
        is_foreign,
        foreign_binding,
        environment: environment.capture(),
        static_fields: [],
        source_name: context.current_source,
      })
      let value = Value::class_value(identifier)
      ignore(environment.assign(name, value))
      StatementCompleted(value)
    }
  }
}

///|
fn finalize_foreign_instances(context : RuntimeContext) -> Unit {
  for instance in context.instances {
    if instance.finalized {
      continue
    }
    match instance.foreign_handle {
      None => ()
      Some(handle) => {
        let class_definition = context.classes[instance.class_identifier]
        match class_definition.foreign_binding {
          Some(binding_identifier) => {
            context.foreign_classes[binding_identifier].finalize(handle)
            instance.finalized = true
          }
          None => ()
        }
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
      bind_core_globals(environment)
      evaluate_expression_in(
        expression,
        environment,
        RuntimeContext::new(100000),
      )
    }
    ExpressionParseFailed(diagnostics) => EvaluationFailed(diagnostics[0])
  }
}
