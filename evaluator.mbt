///|
pub(all) enum EvaluationResult {
  EvaluationSucceeded(Value)
  EvaluationFailed(Diagnostic)
}

///|
/// Summary returned by a persistent VM garbage-collection pass.
pub(all) struct VmGcStats {
  before_objects : Int
  reachable_objects : Int
  reclaimed_objects : Int
  before_instances : Int
  reachable_instances : Int
  reclaimed_instances : Int
  finalized_foreign_instances : Int
}

///|
priv struct Closure {
  parameters : Array[String]
  body : Array[Stmt]
  environment : Environment
  source_name : String
  alive : Bool
}

///|
priv struct ClassDefinition {
  name : String
  superclass : Int?
  inherits_sequence : Bool
  methods : Array[MethodDecl]
  is_foreign : Bool
  foreign_binding : Int?
  environment : Environment
  static_fields : Array[InstanceField]
  attributes : Value
  source_name : String
  alive : Bool
}

///|
priv struct ResolvedMethod {
  declaration : MethodDecl
  owner_identifier : Int
}

///|
priv struct InstanceField {
  owner_identifier : Int
  name : String
  mut value : Value
}

///|
priv struct Instance {
  class_identifier : Int
  fields : Array[InstanceField]
  foreign_handle : Int?
  mut finalized : Bool
  mut alive : Bool
}

///|
priv struct RuntimeList {
  items : Array[Value]
  mut alive : Bool
}

///|
priv struct RuntimeMapEntry {
  key : Value
  mut value : Value
}

///|
priv struct RuntimeMap {
  entries : Array[RuntimeMapEntry]
  mut alive : Bool
}

///|
priv struct RuntimeMapEntryValue {
  key : Value
  value : Value
  alive : Bool
}

///|
priv enum RuntimeSequenceKind {
  SequenceSnapshot(Array[Value])
  SequenceMapView(Array[Value], String)
  SequenceStringBytes(Array[Value])
  SequenceStringCodePoints(Array[Value], Array[Value])
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
  alive : Bool
}

///|
priv struct RuntimeIterator {
  sequence_identifier : Int
  mut source_iterator : Value
  mut current : Value
  mut yielded : Int
  mut started : Bool
  mut completed : Bool
  alive : Bool
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
  alive : Bool
}

///|
priv struct RuntimeModule {
  name : String
  environment : Environment
  mut state : Int
}

///|
/// Runtime state owned by `Vm`. Its fields and constructors remain internal;
/// embedders interact with it through the persistent VM API.
priv struct RuntimeContext {
  start_clock : @bench.Timestamp
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
  free_instances : Array[Int]
  free_lists : Array[Int]
  free_maps : Array[Int]
  free_map_entries : Array[Int]
  free_sequences : Array[Int]
  free_fibers : Array[Int]
  modules : Array[RuntimeModule]
  foreign_methods : Array[ForeignMethodBinding]
  foreign_classes : Array[ForeignClassBinding]
  loader : (String, String) -> ModuleLoadResult
  mut current_source : String
  mut steps : Int
  max_steps : Int
  mut call_depth : Int
  max_call_depth : Int
  mut output_characters : Int
  max_output_characters : Int
  max_modules : Int
  max_objects : Int
  max_source_characters : Int
  should_cancel : () -> Bool
  mut current_fiber : Int
  mut transfer_target : Int
  mut transferred_to_main : Bool
  mut terminate_main : Bool
  mut gc_requested : Bool
  mut debugger : RuntimeDebugger?
}

///|
fn RuntimeContext::new_with_loader(
  max_steps : Int,
  source_name : String,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
) -> RuntimeContext {
  RuntimeContext::new_with_limits(
    max_steps,
    64,
    2147483647,
    2147483647,
    2147483647,
    2147483647,
    source_name,
    loader,
    foreign_methods,
    foreign_classes,
    fn() { false },
  )
}

///|
fn RuntimeContext::new_with_limits(
  max_steps : Int,
  max_call_depth : Int,
  max_output_characters : Int,
  max_modules : Int,
  max_objects : Int,
  max_source_characters : Int,
  source_name : String,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
  should_cancel : () -> Bool,
) -> RuntimeContext {
  {
    start_clock: @bench.monotonic_clock_start(),
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
        alive: true,
      },
    ],
    free_instances: [],
    free_lists: [],
    free_maps: [],
    free_map_entries: [],
    free_sequences: [],
    free_fibers: [],
    modules: [],
    foreign_methods,
    foreign_classes,
    loader,
    current_source: source_name,
    steps: 0,
    max_steps,
    call_depth: 0,
    max_call_depth,
    output_characters: 0,
    max_output_characters,
    max_modules,
    max_objects,
    max_source_characters,
    should_cancel,
    current_fiber: 0,
    transfer_target: -1,
    transferred_to_main: false,
    terminate_main: false,
    gc_requested: false,
    debugger: None,
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
fn RuntimeContext::begin_operation(self : RuntimeContext) -> Unit {
  self.steps = 0
  self.call_depth = 0
  self.output.clear()
  self.output_line_open = false
  self.output_characters = 0
  self.transferred_to_main = false
  self.terminate_main = false
}

///|
fn RuntimeContext::allocated_objects(self : RuntimeContext) -> Int {
  let mut live = self.instances.length() -
    self.free_instances.length() +
    self.lists.length() -
    self.free_lists.length() +
    self.maps.length() -
    self.free_maps.length() +
    self.map_entries.length() -
    self.free_map_entries.length() +
    self.sequences.length() -
    self.free_sequences.length() +
    self.fibers.length() -
    self.free_fibers.length()
  for closure in self.closures {
    if closure.alive {
      live = live + 1
    }
  }
  for class_definition in self.classes {
    if class_definition.alive {
      live = live + 1
    }
  }
  for iterator in self.iterators {
    if iterator.alive {
      live = live + 1
    }
  }
  live
}

///|
fn RuntimeContext::new_instance(
  self : RuntimeContext,
  class_identifier : Int,
  foreign_handle : Int?,
) -> Int {
  match self.free_instances.pop() {
    Some(identifier) => {
      self.instances[identifier] = {
        class_identifier,
        fields: [],
        foreign_handle,
        finalized: false,
        alive: true,
      }
      return identifier
    }
    None => ()
  }
  let identifier = self.instances.length()
  self.instances.push({
    class_identifier,
    fields: [],
    foreign_handle,
    finalized: false,
    alive: true,
  })
  identifier
}

///|
fn RuntimeContext::new_list(
  self : RuntimeContext,
  items : Array[Value],
) -> Value {
  match self.free_lists.pop() {
    Some(identifier) => {
      self.lists[identifier] = { items, alive: true, }
      return Value::list(identifier)
    }
    None => ()
  }
  let identifier = self.lists.length()
  self.lists.push({ items, alive: true, })
  Value::list(identifier)
}

///|
fn RuntimeContext::new_map(self : RuntimeContext) -> Value {
  match self.free_maps.pop() {
    Some(identifier) => {
      self.maps[identifier] = { entries: [], alive: true, }
      return Value::map(identifier)
    }
    None => ()
  }
  let identifier = self.maps.length()
  self.maps.push({ entries: [], alive: true, })
  Value::map(identifier)
}

///|
fn RuntimeContext::new_fiber(
  self : RuntimeContext,
  function_identifier : Int,
) -> Value {
  match self.free_fibers.pop() {
    Some(identifier) => {
      self.fibers[identifier] = {
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
        alive: true,
      }
      return Value::fiber(identifier)
    }
    None => ()
  }
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
    alive: true,
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
  match self.free_fibers.pop() {
    Some(identifier) => {
      self.fibers[identifier] = {
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
        alive: true,
      }
      return identifier
    }
    None => ()
  }
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
    alive: true,
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
  match self.free_sequences.pop() {
    Some(identifier) => {
      self.sequences[identifier] = { kind, alive: true, }
      return Value::sequence(identifier)
    }
    None => ()
  }
  let identifier = self.sequences.length()
  self.sequences.push({ kind, alive: true, })
  Value::sequence(identifier)
}

///|
fn RuntimeContext::new_map_entry(
  self : RuntimeContext,
  key : Value,
  value : Value,
) -> Value {
  match self.free_map_entries.pop() {
    Some(identifier) => {
      self.map_entries[identifier] = { key, value, alive: true, }
      return Value::map_entry(identifier)
    }
    None => ()
  }
  let identifier = self.map_entries.length()
  self.map_entries.push({ key, value, alive: true, })
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
  ignore(environment.bind("MapEntry", Value::core_class(MapEntryClass)))
  ignore(
    environment.bind("MapKeySequence", Value::core_class(MapKeySequenceClass)),
  )
  ignore(
    environment.bind(
      "MapValueSequence",
      Value::core_class(MapValueSequenceClass),
    ),
  )
  ignore(environment.bind("Null", Value::core_class(NullClass)))
  ignore(environment.bind("Num", Value::core_class(NumClass)))
  ignore(environment.bind("Range", Value::core_class(RangeClass)))
  ignore(environment.bind("Sequence", Value::core_class(SequenceClass)))
  ignore(environment.bind("String", Value::core_class(StringClass)))
  ignore(
    environment.bind(
      "StringByteSequence",
      Value::core_class(StringByteSequenceClass),
    ),
  )
  ignore(
    environment.bind(
      "StringCodePointSequence",
      Value::core_class(StringCodePointSequenceClass),
    ),
  )
}

///|
fn find_map_key(entries : Array[RuntimeMapEntry], key : Value) -> Int? {
  for index = 0; index < entries.length(); index = index + 1 {
    if runtime_values_equal(entries[index].key, key) {
      return Some(index)
    }
  }
  None
}

///|
fn integer_arrays_equal(left : Array[Int], right : Array[Int]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn runtime_values_equal(left : Value, right : Value) -> Bool {
  match (string_bytes_of(left), string_bytes_of(right)) {
    (Some(left_bytes), Some(right_bytes)) =>
      integer_arrays_equal(left_bytes, right_bytes)
    _ => left == right
  }
}

///|
fn is_valid_map_key(value : Value) -> Bool {
  match value {
    NullValue
    | BoolValue(_)
    | NumberValue(_)
    | StringValue(_)
    | RawStringValue(_)
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
    RawStringValue(bytes) => string_display_from_bytes(bytes)
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
          SequenceMapView(_, class_name) => "instance of " + class_name
          SequenceStringBytes(_) => "<sequence>"
          SequenceStringCodePoints(_, _) => "<sequence>"
          SequenceMap(_, _) => "instance of MapSequence"
          SequenceWhere(_, _) => "instance of WhereSequence"
          SequenceSkip(_, _) => "instance of SkipSequence"
          SequenceTake(_, _) => "instance of TakeSequence"
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
    InstanceValue(identifier) =>
      if identifier < 0 || identifier >= context.instances.length() {
        "<instance>"
      } else {
        let class_identifier = context.instances[identifier].class_identifier
        match
          find_method_in_class(
            context, class_identifier, "toString", 0, false, true, false,
          ) {
          Some(resolved) =>
            match
              invoke_user_method(
                identifier,
                resolved,
                [],
                SourceSpan::empty(),
                context,
              ) {
              EvaluationSucceeded(StringValue(text)) => text
              EvaluationSucceeded(RawStringValue(bytes)) =>
                string_display_from_bytes(bytes)
              EvaluationSucceeded(_) | EvaluationFailed(_) =>
                "[invalid toString]"
            }
          None => "instance of " + context.classes[class_identifier].name
        }
      }
    ClassValue(identifier) =>
      if identifier < 0 || identifier >= context.classes.length() {
        "<class>"
      } else {
        match
          find_method_in_class(
            context, identifier, "toString", 0, false, true, true,
          ) {
          Some(resolved) =>
            match
              invoke_static_method(
                identifier,
                resolved,
                [],
                SourceSpan::empty(),
                context,
              ) {
              EvaluationSucceeded(StringValue(text)) => text
              EvaluationSucceeded(RawStringValue(bytes)) =>
                string_display_from_bytes(bytes)
              EvaluationSucceeded(_) | EvaluationFailed(_) =>
                "[invalid toString]"
            }
          None => context.classes[identifier].name
        }
      }
    MetaClassValue(name) => name
    ClassAttributesValue(_, _) => "<class attributes>"
    _ => value.to_text()
  }
}

///|
fn RuntimeContext::get_instance_field(
  self : RuntimeContext,
  identifier : Int,
  owner_identifier : Int,
  name : String,
) -> Value? {
  if identifier < 0 || identifier >= self.instances.length() {
    return None
  }
  for field in self.instances[identifier].fields {
    if field.owner_identifier == owner_identifier && field.name == name {
      return Some(field.value)
    }
  }
  Some(Value::null())
}

///|
fn RuntimeContext::set_instance_field(
  self : RuntimeContext,
  identifier : Int,
  owner_identifier : Int,
  name : String,
  value : Value,
) -> Bool {
  if identifier < 0 || identifier >= self.instances.length() {
    return false
  }
  let fields = self.instances[identifier].fields
  for field in fields {
    if field.owner_identifier == owner_identifier && field.name == name {
      field.value = value
      return true
    }
  }
  fields.push({ owner_identifier, name, value, })
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
  fields.push({ owner_identifier: class_identifier, name, value, })
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
  environment : Environment,
) -> Diagnostic? {
  if (self.should_cancel)() {
    return Some(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "execution cancelled by host",
        span,
      ),
    )
  }
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
  } else if self.allocated_objects() > self.max_objects {
    Some(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "runtime object limit exceeded",
        span,
      ),
    )
  } else {
    self.debug_before_statement(span, environment)
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
  context : RuntimeContext,
) -> EvaluationResult {
  match value {
    InstanceValue(identifier) => {
      let name = match operator {
        LogicalNot => "!"
        Negate => "-"
        BitwiseNot => "~"
      }
      if identifier >= 0 && identifier < context.instances.length() {
        let class_identifier = context.instances[identifier].class_identifier
        match
          find_method_in_class(
            context, class_identifier, name, 0, false, false, false,
          ) {
          Some(resolved) =>
            return invoke_user_method(identifier, resolved, [], span, context)
          None => ()
        }
      }
    }
    ClassValue(identifier) => {
      let name = match operator {
        LogicalNot => "!"
        Negate => "-"
        BitwiseNot => "~"
      }
      match
        find_method_in_class(context, identifier, name, 0, false, false, true) {
        Some(resolved) =>
          return invoke_static_method(identifier, resolved, [], span, context)
        None => ()
      }
    }
    _ => ()
  }
  match (operator, value) {
    (LogicalNot, value) => EvaluationSucceeded(Value::bool(!value.is_truthy()))
    (Negate, NumberValue(number)) =>
      EvaluationSucceeded(
        Value::number(
          (number.reinterpret_as_uint64() ^ 0x8000_0000_0000_0000UL).reinterpret_as_double(),
        ),
      )
    (BitwiseNot, NumberValue(number)) =>
      EvaluationSucceeded(Value::number(wren_u32(number).lnot().to_double()))
    (Negate, value) => invalid_unary("-", value, span)
    (BitwiseNot, value) => invalid_unary("~", value, span)
  }
}

///|
fn wren_u32(number : Double) -> UInt {
  let mut normalized = number % 4294967296.0
  if normalized < 0.0 {
    normalized = normalized + 4294967296.0
  }
  if normalized >= 2147483648.0 {
    (normalized - 2147483648.0).to_int().reinterpret_as_uint() + 0x80000000U
  } else {
    normalized.to_int().reinterpret_as_uint()
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
    Divide => EvaluationSucceeded(Value::number(left / right))
    Remainder => EvaluationSucceeded(Value::number(left % right))
    LessThan => EvaluationSucceeded(Value::bool(left < right))
    LessThanOrEqual => EvaluationSucceeded(Value::bool(left <= right))
    GreaterThan => EvaluationSucceeded(Value::bool(left > right))
    GreaterThanOrEqual => EvaluationSucceeded(Value::bool(left >= right))
    BitwiseAnd =>
      EvaluationSucceeded(
        Value::number(wren_u32(left).land(wren_u32(right)).to_double()),
      )
    BitwiseOr =>
      EvaluationSucceeded(
        Value::number(wren_u32(left).lor(wren_u32(right)).to_double()),
      )
    BitwiseXor =>
      EvaluationSucceeded(
        Value::number(wren_u32(left).lxor(wren_u32(right)).to_double()),
      )
    ShiftLeft =>
      EvaluationSucceeded(
        Value::number((wren_u32(left) << (right.to_int() & 31)).to_double()),
      )
    ShiftRight =>
      EvaluationSucceeded(
        Value::number((wren_u32(left) >> (right.to_int() & 31)).to_double()),
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
  match left {
    InstanceValue(identifier) => {
      let name = match operator {
        Add => "+"
        Subtract => "-"
        Multiply => "*"
        Divide => "/"
        Remainder => "%"
        EqualTo => "=="
        NotEqualTo => "!="
        LessThan => "<"
        LessThanOrEqual => "<="
        GreaterThan => ">"
        GreaterThanOrEqual => ">="
        BitwiseAnd => "&"
        BitwiseOr => "|"
        BitwiseXor => "^"
        ShiftLeft => "<<"
        ShiftRight => ">>"
        InclusiveRange => ".."
        ExclusiveRange => "..."
        IsType => "is"
        LogicalAnd | LogicalOr => ""
      }
      if name != "" &&
        identifier >= 0 &&
        identifier < context.instances.length() {
        let class_identifier = context.instances[identifier].class_identifier
        match
          find_method_in_class(
            context, class_identifier, name, 1, false, false, false,
          ) {
          Some(resolved) =>
            return invoke_user_method(
              identifier,
              resolved,
              [right],
              span,
              context,
            )
          None => ()
        }
      }
    }
    ClassValue(identifier) => {
      let name = match operator {
        Add => "+"
        Subtract => "-"
        Multiply => "*"
        Divide => "/"
        Remainder => "%"
        EqualTo => "=="
        NotEqualTo => "!="
        LessThan => "<"
        LessThanOrEqual => "<="
        GreaterThan => ">"
        GreaterThanOrEqual => ">="
        BitwiseAnd => "&"
        BitwiseOr => "|"
        BitwiseXor => "^"
        ShiftLeft => "<<"
        ShiftRight => ">>"
        InclusiveRange => ".."
        ExclusiveRange => "..."
        IsType => "is"
        LogicalAnd | LogicalOr => ""
      }
      if name != "" {
        match
          find_method_in_class(context, identifier, name, 1, false, false, true) {
          Some(resolved) =>
            return invoke_static_method(
              identifier,
              resolved,
              [right],
              span,
              context,
            )
          None => ()
        }
      }
    }
    _ => ()
  }
  match operator {
    EqualTo =>
      EvaluationSucceeded(Value::bool(runtime_values_equal(left, right)))
    NotEqualTo =>
      EvaluationSucceeded(Value::bool(!runtime_values_equal(left, right)))
    Add =>
      match (left, right) {
        (NumberValue(left), NumberValue(right)) =>
          number_binary(Add, left, right, span)
        (StringValue(_) | RawStringValue(_), StringValue(_) | RawStringValue(_)) => {
          let left_bytes = match string_bytes_of(left) {
            Some(bytes) => bytes
            None => []
          }
          let right_bytes = match string_bytes_of(right) {
            Some(bytes) => bytes
            None => []
          }
          for byte in right_bytes {
            left_bytes.push(byte)
          }
          EvaluationSucceeded(string_value_from_bytes(left_bytes))
        }
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
        (StringValue(_) | RawStringValue(_), count_value) =>
          match non_negative_count(count_value) {
            None =>
              evaluation_error(
                InvalidOperand,
                "String repetition count must be a non-negative integer",
                span,
              )
            Some(count) => {
              let bytes = match string_bytes_of(left) {
                Some(bytes) => bytes
                None => []
              }
              let result : Array[Int] = []
              for index = 0; index < count; index = index + 1 {
                for byte in bytes {
                  result.push(byte)
                }
              }
              EvaluationSucceeded(string_value_from_bytes(result))
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
    IsType => evaluate_is_type(left, right, span, context)
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
    StringValue(_) | RawStringValue(_) => Value::core_class(StringClass)
    RangeValue(_, _, _) => Value::core_class(RangeClass)
    ListValue(_) => Value::core_class(ListClass)
    MapValue(_) => Value::core_class(MapClass)
    SequenceValue(identifier) =>
      if identifier >= 0 && identifier < context.sequences.length() {
        match context.sequences[identifier].kind {
          SequenceStringBytes(_) => Value::core_class(StringByteSequenceClass)
          SequenceStringCodePoints(_, _) =>
            Value::core_class(StringCodePointSequenceClass)
          _ => Value::core_class(SequenceClass)
        }
      } else {
        Value::core_class(SequenceClass)
      }
    FunctionValue(_) => Value::core_class(FnClass)
    FiberValue(_) => Value::core_class(FiberClass)
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        Value::class_value(context.instances[identifier].class_identifier)
      } else {
        Value::core_class(ObjectClass)
      }
    ClassValue(_) | MetaClassValue(_) | CoreClassValue(_) | SystemValue =>
      Value::core_class(ClassClass)
    ClassAttributesValue(_, _) => Value::core_class(ObjectClass)
    MapEntryValue(_) => Value::core_class(MapEntryClass)
    IteratorValue(_) => Value::core_class(ObjectClass)
    SuperValue(_, instance_identifier, _, _) =>
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
fn value_is_core_class(
  value : Value,
  target : CoreClass,
  context : RuntimeContext,
) -> Bool {
  if target == ObjectClass {
    return true
  }
  match value {
    NullValue => target == NullClass
    BoolValue(_) => target == BoolClass
    NumberValue(_) => target == NumClass
    StringValue(_) | RawStringValue(_) =>
      target == StringClass || target == SequenceClass
    RangeValue(_, _, _) => target == RangeClass || target == SequenceClass
    ListValue(_) => target == ListClass || target == SequenceClass
    MapValue(_) => target == MapClass || target == SequenceClass
    SequenceValue(identifier) =>
      if target == SequenceClass {
        true
      } else if identifier >= 0 && identifier < context.sequences.length() {
        match context.sequences[identifier].kind {
          SequenceStringBytes(_) => target == StringByteSequenceClass
          SequenceStringCodePoints(_, _) =>
            target == StringCodePointSequenceClass
          _ => false
        }
      } else {
        false
      }
    FunctionValue(_) => target == FnClass
    FiberValue(_) => target == FiberClass
    ClassValue(_) | MetaClassValue(_) | CoreClassValue(_) | SystemValue =>
      target == ClassClass
    ClassAttributesValue(_, _) => false
    MapEntryValue(_) => target == MapEntryClass
    InstanceValue(_) | IteratorValue(_) => false
    SuperValue(_, _, _, _) => false
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
      EvaluationSucceeded(
        Value::bool(value_is_core_class(value, target, context)),
      )
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
  if !is_constructor && !is_static {
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
fn attribute_method_signature(declaration : MethodDecl) -> String {
  let mut signature = if declaration.is_static { "static " } else { "" }
  signature = signature + declaration.name
  if declaration.is_getter {
    return signature
  }
  signature = signature + "("
  for index = 0; index < declaration.parameters.length(); index = index + 1 {
    if index > 0 {
      signature = signature + ","
    }
    signature = signature + "_"
  }
  signature + ")"
}

///|
fn build_attribute_map(
  attributes : Array[AttributeDecl],
  context : RuntimeContext,
) -> Int {
  if attributes.is_empty() {
    return -1
  }
  let outer = context.new_map()
  let outer_identifier = match outer {
    MapValue(identifier) => identifier
    _ => -1
  }
  for attribute in attributes {
    let group_key = match attribute.group {
      Some(group) => Value::string(group)
      None => Value::null()
    }
    let group_identifier = match
      find_map_key(context.maps[outer_identifier].entries, group_key) {
      Some(index) =>
        match context.maps[outer_identifier].entries[index].value {
          MapValue(identifier) => identifier
          _ => -1
        }
      None => {
        let group = context.new_map()
        let identifier = match group {
          MapValue(identifier) => identifier
          _ => -1
        }
        ignore(context.set_map_entry(outer_identifier, group_key, group))
        identifier
      }
    }
    let key = Value::string(attribute.key)
    match find_map_key(context.maps[group_identifier].entries, key) {
      Some(index) =>
        match context.maps[group_identifier].entries[index].value {
          ListValue(identifier) =>
            context.lists[identifier].items.push(attribute.value)
          _ => ()
        }
      None => {
        let values = context.new_list([attribute.value])
        ignore(context.set_map_entry(group_identifier, key, values))
      }
    }
  }
  outer_identifier
}

///|
fn build_class_attributes(
  class_attributes : Array[AttributeDecl],
  methods : Array[MethodDecl],
  context : RuntimeContext,
) -> Value {
  let self_identifier = build_attribute_map(class_attributes, context)
  let mut methods_identifier = -1
  for declaration in methods {
    let attributes_identifier = build_attribute_map(
      declaration.attributes,
      context,
    )
    if attributes_identifier >= 0 {
      if methods_identifier < 0 {
        let map = context.new_map()
        methods_identifier = match map {
          MapValue(identifier) => identifier
          _ => -1
        }
      }
      ignore(
        context.set_map_entry(
          methods_identifier,
          Value::string(attribute_method_signature(declaration)),
          Value::map(attributes_identifier),
        ),
      )
    }
  }
  if self_identifier < 0 && methods_identifier < 0 {
    Value::null()
  } else {
    ClassAttributesValue(self_identifier, methods_identifier)
  }
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
  if !context.instances[instance_identifier].alive {
    return evaluation_error(
      UndefinedMethod,
      "instance was released by the runtime garbage collector",
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
  ignore(environment.bind("$method", Value::null()))
  ignore(environment.bind("this", Value::instance(instance_identifier)))
  ignore(
    environment.bind("$class", Value::class_value(resolved.owner_identifier)),
  )
  ignore(
    environment.bind(
      "$super",
      SuperValue(
        owner.superclass.unwrap_or(-1),
        instance_identifier,
        declaration.name,
        declaration.is_constructor,
      ),
    ),
  )
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
  ignore(environment.bind("$method", Value::null()))
  ignore(environment.bind("this", Value::class_value(receiver_class)))
  ignore(
    environment.bind("$class", Value::class_value(resolved.owner_identifier)),
  )
  ignore(
    environment.bind(
      "$super",
      SuperClassValue(owner.superclass.unwrap_or(-1), receiver_class),
    ),
  )
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
      let instance_identifier = context.new_instance(
        class_identifier, foreign_handle,
      )
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
  method_name : String,
  is_constructor : Bool,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match
    find_method_in_class(
      context,
      superclass,
      method_name,
      arguments.length(),
      is_constructor,
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
        "superclass does not implement method '\{method_name}' with \{arguments.length()} arguments",
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
      if class_definition.inherits_sequence {
        invoke_sequence_operation(
          Value::instance(instance_identifier),
          name,
          arguments,
          span,
          context,
        )
      } else {
        evaluation_error(
          UndefinedMethod,
          "\{class_definition.name} does not implement method '\{name}' with \{arguments.length()} arguments",
          span,
        )
      }
  }
}

///|
priv enum CollectionIndexResult {
  CollectionIndexSucceeded(Int)
  CollectionIndexFailed(Diagnostic)
}

///|
priv enum CollectionRangeResult {
  CollectionRangeSucceeded(Int, Int, Int)
  CollectionRangeFailed(Diagnostic)
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
fn collection_range(
  length : Int,
  from : Double,
  to : Double,
  inclusive : Bool,
  span : SourceSpan,
) -> CollectionRangeResult {
  if from == Double::from_int(length) &&
    to == (if inclusive { -1.0 } else { Double::from_int(length) }) {
    return CollectionRangeSucceeded(0, 0, 0)
  }
  let start = match collection_index(Value::number(from), length, false, span) {
    CollectionIndexSucceeded(index) => index
    CollectionIndexFailed(issue) => return CollectionRangeFailed(issue)
  }
  let raw_end = to.to_int()
  if Double::from_int(raw_end) != to {
    return CollectionRangeFailed(
      Diagnostic::new(
        Runtime,
        InvalidIndex,
        "range end must be an integer",
        span,
      ),
    )
  }
  let mut end = if raw_end < 0 { length + raw_end } else { raw_end }
  if !inclusive {
    if end == start {
      return CollectionRangeSucceeded(start, 0, 0)
    }
    end = end + (if end >= start { -1 } else { 1 })
  }
  if end < 0 || end >= length {
    return CollectionRangeFailed(
      Diagnostic::new(
        Runtime,
        IndexOutOfBounds,
        "range end is outside the valid range",
        span,
      ),
    )
  }
  let count = (start - end).abs() + 1
  let step = if start < end { 1 } else { -1 }
  CollectionRangeSucceeded(start, count, step)
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
  let (start, count, step) = match
    collection_range(items.length(), from, to, inclusive, span) {
    CollectionRangeSucceeded(start, count, step) => (start, count, step)
    CollectionRangeFailed(issue) => return EvaluationFailed(issue)
  }
  let result : Array[Value] = []
  let mut index = start
  let mut remaining = count
  while remaining > 0 {
    result.push(items[index])
    index = index + step
    remaining = remaining - 1
  }
  EvaluationSucceeded(context.new_list(result))
}

///|
fn read_string_range(
  bytes : Array[Int],
  from : Double,
  to : Double,
  inclusive : Bool,
  span : SourceSpan,
) -> EvaluationResult {
  let (start, count, step) = match
    collection_range(bytes.length(), from, to, inclusive, span) {
    CollectionRangeSucceeded(start, count, step) => (start, count, step)
    CollectionRangeFailed(issue) => return EvaluationFailed(issue)
  }
  let mut index = start
  let result : Array[Int] = []
  let mut remaining = count
  while remaining > 0 {
    match decode_utf8_at(bytes, index) {
      Some((_, width)) =>
        for offset = 0; offset < width; offset = offset + 1 {
          result.push(bytes[index + offset])
        }
      None =>
        if !byte_is_valid_continuation_at(bytes, index) {
          result.push(bytes[index])
        }
    }
    index = index + step
    remaining = remaining - 1
  }
  EvaluationSucceeded(string_value_from_bytes(result))
}

///|
fn read_subscript(
  receiver : Value,
  index : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  match receiver {
    InstanceValue(identifier) =>
      invoke_instance_method(identifier, "[]", [index], span, context)
    ClassValue(identifier) =>
      match
        find_method_in_class(context, identifier, "[]", 1, false, false, true) {
        Some(resolved) =>
          invoke_static_method(identifier, resolved, [index], span, context)
        None =>
          evaluation_error(
            UndefinedMethod,
            "\{context.classes[identifier].name} does not implement static subscript with one argument",
            span,
          )
      }
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
    StringValue(_) | RawStringValue(_) => {
      let bytes = match string_bytes_of(receiver) {
        Some(bytes) => bytes
        None => []
      }
      let byte_length = bytes.length()
      match index {
        RangeValue(from, to, inclusive) =>
          read_string_range(bytes, from, to, inclusive, span)
        value =>
          match collection_index(value, byte_length, false, span) {
            CollectionIndexSucceeded(index) =>
              match string_value_at_byte_from_bytes(bytes, index) {
                Some(value) => EvaluationSucceeded(value)
                None =>
                  evaluation_error(
                    IndexOutOfBounds,
                    "string index is outside the valid range",
                    span,
                  )
              }
            CollectionIndexFailed(issue) => EvaluationFailed(issue)
          }
      }
    }
    SequenceValue(identifier) =>
      if identifier < 0 || identifier >= context.sequences.length() {
        evaluation_error(InvalidOperand, "sequence is not available", span)
      } else {
        let indexed = match context.sequences[identifier].kind {
          SequenceSnapshot(items) => items
          SequenceStringBytes(items) => items
          SequenceStringCodePoints(items, _) => items
          _ =>
            return evaluation_error(
              InvalidOperand,
              "lazy Sequence values cannot be indexed",
              span,
            )
        }
        match collection_index(index, indexed.length(), false, span) {
          CollectionIndexSucceeded(position) =>
            EvaluationSucceeded(indexed[position])
          CollectionIndexFailed(issue) => EvaluationFailed(issue)
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
    InstanceValue(identifier) =>
      invoke_instance_method(identifier, "[]=", [index, value], span, context)
    ClassValue(identifier) =>
      match
        find_method_in_class(context, identifier, "[]=", 2, false, false, true) {
        Some(resolved) =>
          invoke_static_method(
            identifier,
            resolved,
            [index, value],
            span,
            context,
          )
        None =>
          evaluation_error(
            UndefinedMethod,
            "\{context.classes[identifier].name} does not implement static subscript setter with two arguments",
            span,
          )
      }
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
    StringValue(_) | RawStringValue(_) =>
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
        if Double::from_int(index) != number {
          evaluation_error(
            InvalidOperand,
            "\{owner} iterator must be an integer",
            span,
          )
        } else if index < 0 || index >= items.length() {
          EvaluationSucceeded(Value::bool(false))
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
fn sparse_indexed_iterator(
  owner : String,
  items : Array[Value],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if arguments.length() != 1 {
    return invalid_collection_arity(owner, name, 1, arguments.length(), span)
  }
  if name == "iteratorValue" {
    let raw = match arguments[0] {
      NumberValue(number) => {
        let index = number.to_int()
        if Double::from_int(index) != number {
          return evaluation_error(
            InvalidOperand,
            "\{owner} iterator must be an integer",
            span,
          )
        }
        index
      }
      value =>
        return evaluation_error(
          InvalidOperand,
          "\{owner} iterator must be a Num, received \{value.type_name()}",
          span,
        )
    }
    if raw < 0 || raw % 2 != 0 || raw / 2 >= items.length() {
      return evaluation_error(
        IndexOutOfBounds,
        "\{owner} iterator is outside the valid range",
        span,
      )
    }
    return EvaluationSucceeded(items[raw / 2])
  }
  let next = match arguments[0] {
    NullValue => 0
    NumberValue(number) => {
      let current = number.to_int()
      if Double::from_int(current) != number {
        return evaluation_error(
          InvalidOperand,
          "\{owner} iterator must be an integer",
          span,
        )
      }
      if current < 0 {
        return EvaluationSucceeded(Value::bool(false))
      }
      (current / 2 + 1) * 2
    }
    value =>
      return evaluation_error(
        InvalidOperand,
        "\{owner} iterator must be null or Num, received \{value.type_name()}",
        span,
      )
  }
  if next / 2 >= items.length() {
    EvaluationSucceeded(Value::bool(false))
  } else {
    EvaluationSucceeded(Value::number(Double::from_int(next)))
  }
}

///|
fn indexed_string_view_iterator(
  owner : String,
  items : Array[Value],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if name == "iteratorValue" && arguments.length() == 1 {
    match arguments[0] {
      NumberValue(number) => {
        let raw = number.to_int()
        if Double::from_int(raw) == number && raw < 0 {
          return indexed_iterator(
            owner,
            items,
            name,
            [Value::number(Double::from_int(items.length() + raw))],
            span,
          )
        }
      }
      _ => ()
    }
  }
  indexed_iterator(owner, items, name, arguments, span)
}

///|
fn code_point_width(code_point : Int) -> Int {
  if code_point <= 0x7f {
    1
  } else if code_point <= 0x7ff {
    2
  } else if code_point <= 0xffff {
    3
  } else {
    4
  }
}

///|
fn code_point_index_is_continuation(items : Array[Value], index : Int) -> Bool {
  for distance = 1; distance <= 3; distance = distance + 1 {
    let start = index - distance
    if start < 0 {
      break
    }
    match items[start] {
      NumberValue(code_point) => {
        let value = code_point.to_int()
        if value >= 0 && code_point_width(value) > distance {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
fn code_point_view_iterator(
  items : Array[Value],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if name == "iteratorValue" {
    return indexed_string_view_iterator(
      "StringCodePointSequence", items, name, arguments, span,
    )
  }
  if arguments.length() != 1 {
    return invalid_collection_arity(
      "StringCodePointSequence",
      name,
      1,
      arguments.length(),
      span,
    )
  }
  match arguments[0] {
    NullValue =>
      if items.length() == 0 {
        EvaluationSucceeded(Value::bool(false))
      } else {
        EvaluationSucceeded(Value::number(0.0))
      }
    NumberValue(number) => {
      let current = number.to_int()
      if Double::from_int(current) != number {
        return evaluation_error(
          InvalidOperand,
          "StringCodePointSequence iterator must be an integer",
          span,
        )
      }
      if current < 0 || current >= items.length() {
        return EvaluationSucceeded(Value::bool(false))
      }
      let mut next = current + 1
      while next < items.length() &&
            code_point_index_is_continuation(items, next) {
        next = next + 1
      }
      if next < items.length() {
        EvaluationSucceeded(Value::number(Double::from_int(next)))
      } else {
        EvaluationSucceeded(Value::bool(false))
      }
    }
    value =>
      evaluation_error(
        InvalidOperand,
        "StringCodePointSequence iterator must be null or Num, received \{value.type_name()}",
        span,
      )
  }
}

///|
fn string_iterator(
  bytes : Array[Int],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
) -> EvaluationResult {
  if arguments.length() != 1 {
    return invalid_collection_arity("String", name, 1, arguments.length(), span)
  }
  if name == "iteratorValue" {
    return match arguments[0] {
      NumberValue(number) => {
        let raw = number.to_int()
        let index = if raw < 0 { bytes.length() + raw } else { raw }
        if Double::from_int(raw) != number {
          evaluation_error(
            InvalidOperand,
            "String iterator must be an integer",
            span,
          )
        } else {
          match string_value_at_byte_from_bytes(bytes, index) {
            Some(value) => EvaluationSucceeded(value)
            None =>
              evaluation_error(
                InvalidOperand,
                "String iterator is outside the valid range",
                span,
              )
          }
        }
      }
      value =>
        evaluation_error(
          InvalidOperand,
          "String iterator must be a Num, received \{value.type_name()}",
          span,
        )
    }
  }
  match arguments[0] {
    NullValue =>
      if bytes.length() == 0 {
        EvaluationSucceeded(Value::bool(false))
      } else {
        EvaluationSucceeded(Value::number(0.0))
      }
    NumberValue(number) => {
      let current = number.to_int()
      if Double::from_int(current) != number {
        return evaluation_error(
          InvalidOperand,
          "String iterator must be an integer",
          span,
        )
      }
      if current < 0 || current >= bytes.length() {
        return EvaluationSucceeded(Value::bool(false))
      }
      let mut next = current + 1
      while next < bytes.length() && byte_is_valid_continuation_at(bytes, next) {
        next = next + 1
      }
      if next < bytes.length() {
        EvaluationSucceeded(Value::number(Double::from_int(next)))
      } else {
        EvaluationSucceeded(Value::bool(false))
      }
    }
    value =>
      evaluation_error(
        InvalidOperand,
        "String iterator must be null or Num, received \{value.type_name()}",
        span,
      )
  }
}

///|
fn utf8_bytes(text : String) -> Array[Int] {
  let bytes : Array[Int] = []
  for character in text.to_array() {
    let code = character.to_int()
    if code <= 0x7f {
      bytes.push(code)
    } else if code <= 0x7ff {
      bytes.push(0xc0 | (code >> 6))
      bytes.push(0x80 | (code & 0x3f))
    } else if code <= 0xffff {
      bytes.push(0xe0 | (code >> 12))
      bytes.push(0x80 | ((code >> 6) & 0x3f))
      bytes.push(0x80 | (code & 0x3f))
    } else {
      bytes.push(0xf0 | (code >> 18))
      bytes.push(0x80 | ((code >> 12) & 0x3f))
      bytes.push(0x80 | ((code >> 6) & 0x3f))
      bytes.push(0x80 | (code & 0x3f))
    }
  }
  bytes
}

///|
fn string_bytes_of(value : Value) -> Array[Int]? {
  match value {
    StringValue(text) => Some(utf8_bytes(text))
    RawStringValue(bytes) => {
      let copied : Array[Int] = []
      for byte in bytes {
        copied.push(byte)
      }
      Some(copied)
    }
    _ => None
  }
}

///|
fn is_continuation_byte(byte : Int) -> Bool {
  byte >= 0x80 && byte <= 0xbf
}

///|
fn decode_utf8_at(bytes : Array[Int], index : Int) -> (Int, Int)? {
  if index < 0 || index >= bytes.length() {
    return None
  }
  let first = bytes[index]
  if first >= 0 && first <= 0x7f {
    return Some((first, 1))
  }
  if first >= 0xc2 && first <= 0xdf && index + 1 < bytes.length() {
    let second = bytes[index + 1]
    if is_continuation_byte(second) {
      return Some((((first & 0x1f) << 6) | (second & 0x3f), 2))
    }
  }
  if first >= 0xe0 && first <= 0xef && index + 2 < bytes.length() {
    let second = bytes[index + 1]
    let third = bytes[index + 2]
    let second_valid = is_continuation_byte(second) &&
      (first != 0xe0 || second >= 0xa0) &&
      (first != 0xed || second <= 0x9f)
    if second_valid && is_continuation_byte(third) {
      return Some(
        (((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f), 3),
      )
    }
  }
  if first >= 0xf0 && first <= 0xf4 && index + 3 < bytes.length() {
    let second = bytes[index + 1]
    let third = bytes[index + 2]
    let fourth = bytes[index + 3]
    let second_valid = is_continuation_byte(second) &&
      (first != 0xf0 || second >= 0x90) &&
      (first != 0xf4 || second <= 0x8f)
    if second_valid &&
      is_continuation_byte(third) &&
      is_continuation_byte(fourth) {
      return Some(
        (
          ((first & 0x07) << 18) |
          ((second & 0x3f) << 12) |
          ((third & 0x3f) << 6) |
          (fourth & 0x3f),
          4,
        ),
      )
    }
  }
  None
}

///|
fn byte_is_valid_continuation_at(bytes : Array[Int], index : Int) -> Bool {
  for distance = 1; distance <= 3; distance = distance + 1 {
    let start = index - distance
    if start < 0 {
      break
    }
    match decode_utf8_at(bytes, start) {
      Some((_, width)) => if start + width > index { return true }
      None => ()
    }
  }
  false
}

///|
fn string_value_from_bytes(bytes : Array[Int]) -> Value {
  let characters : Array[Char] = []
  let mut index = 0
  while index < bytes.length() {
    match decode_utf8_at(bytes, index) {
      Some((code_point, width)) => {
        characters.push(code_point.unsafe_to_char())
        index = index + width
      }
      None => return Value::raw_string(bytes)
    }
  }
  Value::string(String::from_array(characters))
}

///|
fn string_display_from_bytes(bytes : Array[Int]) -> String {
  let characters : Array[Char] = []
  let mut index = 0
  while index < bytes.length() {
    match decode_utf8_at(bytes, index) {
      Some((code_point, width)) => {
        characters.push(code_point.unsafe_to_char())
        index = index + width
      }
      None => {
        characters.push((0xfffd).unsafe_to_char())
        index = index + 1
      }
    }
  }
  String::from_array(characters)
}

///|
fn string_code_point_views_from_bytes(
  bytes : Array[Int],
) -> (Array[Value], Array[Value]) {
  let indexed : Array[Value] = []
  let iterated : Array[Value] = []
  let mut index = 0
  while index < bytes.length() {
    match decode_utf8_at(bytes, index) {
      Some((code_point, width)) => {
        let value = Value::number(Double::from_int(code_point))
        indexed.push(value)
        iterated.push(value)
        for offset = 1; offset < width; offset = offset + 1 {
          indexed.push(Value::number(-1.0))
        }
        index = index + width
      }
      None => {
        indexed.push(Value::number(-1.0))
        iterated.push(Value::number(-1.0))
        index = index + 1
      }
    }
  }
  (indexed, iterated)
}

///|
fn string_value_at_byte_from_bytes(
  bytes : Array[Int],
  byte_index : Int,
) -> Value? {
  if byte_index < 0 || byte_index >= bytes.length() {
    return None
  }
  match decode_utf8_at(bytes, byte_index) {
    Some((_, width)) => {
      let selected : Array[Int] = []
      for offset = 0; offset < width; offset = offset + 1 {
        selected.push(bytes[byte_index + offset])
      }
      Some(string_value_from_bytes(selected))
    }
    None => Some(Value::raw_string([bytes[byte_index]]))
  }
}

///|
fn string_items_from_bytes(bytes : Array[Int]) -> Array[Value] {
  let items : Array[Value] = []
  let mut index = 0
  while index < bytes.length() {
    match decode_utf8_at(bytes, index) {
      Some((_, width)) => {
        let selected : Array[Int] = []
        for offset = 0; offset < width; offset = offset + 1 {
          selected.push(bytes[index + offset])
        }
        items.push(string_value_from_bytes(selected))
        index = index + width
      }
      None => {
        items.push(Value::raw_string([bytes[index]]))
        index = index + 1
      }
    }
  }
  items
}

///|
fn string_count_from_bytes(bytes : Array[Int]) -> Int {
  string_items_from_bytes(bytes).length()
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
fn string_index_of(
  source : Array[Int],
  search : Array[Int],
  start : Int,
) -> Int {
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
fn bytes_have_prefix(source : Array[Int], prefix : Array[Int]) -> Bool {
  if prefix.length() > source.length() {
    return false
  }
  for index = 0; index < prefix.length(); index = index + 1 {
    if source[index] != prefix[index] {
      return false
    }
  }
  true
}

///|
fn bytes_have_suffix(source : Array[Int], suffix : Array[Int]) -> Bool {
  if suffix.length() > source.length() {
    return false
  }
  let start = source.length() - suffix.length()
  for index = 0; index < suffix.length(); index = index + 1 {
    if source[start + index] != suffix[index] {
      return false
    }
  }
  true
}

///|
fn copy_byte_range(source : Array[Int], start : Int, end : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index = start; index < end; index = index + 1 {
    result.push(source[index])
  }
  result
}

///|
fn byte_is_in(byte : Int, values : Array[Int]) -> Bool {
  for value in values {
    if value == byte {
      return true
    }
  }
  false
}

///|
fn invoke_string_bytes_method(
  receiver : Value,
  bytes : Array[Int],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  if name == "iterate" || name == "iteratorValue" {
    return string_iterator(bytes, name, arguments, span)
  }
  match name {
    "contains" | "startsWith" | "endsWith" | "split" =>
      if arguments.length() != 1 {
        invalid_collection_arity("String", name, 1, arguments.length(), span)
      } else {
        let needle = match string_bytes_of(arguments[0]) {
          Some(value) => value
          None => return invalid_string_argument(name, 1, arguments[0], span)
        }
        match name {
          "contains" =>
            EvaluationSucceeded(
              Value::bool(string_index_of(bytes, needle, 0) >= 0),
            )
          "startsWith" =>
            EvaluationSucceeded(Value::bool(bytes_have_prefix(bytes, needle)))
          "endsWith" =>
            EvaluationSucceeded(Value::bool(bytes_have_suffix(bytes, needle)))
          "split" =>
            if needle.length() == 0 {
              evaluation_error(
                InvalidOperand,
                "String.split separator must not be empty",
                span,
              )
            } else {
              let parts : Array[Value] = []
              let mut start = 0
              while start <= bytes.length() {
                let found = string_index_of(bytes, needle, start)
                if found < 0 {
                  parts.push(
                    string_value_from_bytes(
                      copy_byte_range(bytes, start, bytes.length()),
                    ),
                  )
                  break
                }
                parts.push(
                  string_value_from_bytes(copy_byte_range(bytes, start, found)),
                )
                start = found + needle.length()
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
      let needle = match string_bytes_of(arguments[0]) {
        Some(value) => value
        None => return invalid_string_argument(name, 1, arguments[0], span)
      }
      let length = bytes.length()
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
            if normalized < 0 || normalized >= length {
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
        Value::number(Double::from_int(string_index_of(bytes, needle, start))),
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
        [9, 10, 13, 32]
      } else {
        match string_bytes_of(arguments[0]) {
          Some(value) => value
          None => return invalid_string_argument(name, 1, arguments[0], span)
        }
      }
      let mut start = 0
      let mut end = bytes.length()
      if name == "trim" || name == "trimStart" {
        while start < end && byte_is_in(bytes[start], characters) {
          start = start + 1
        }
      }
      if name == "trim" || name == "trimEnd" {
        while end > start && byte_is_in(bytes[end - 1], characters) {
          end = end - 1
        }
      }
      EvaluationSucceeded(
        string_value_from_bytes(copy_byte_range(bytes, start, end)),
      )
    }
    "replace" =>
      if arguments.length() != 2 {
        invalid_collection_arity("String", name, 2, arguments.length(), span)
      } else {
        let old = match string_bytes_of(arguments[0]) {
          Some(value) => value
          None => return invalid_string_argument(name, 1, arguments[0], span)
        }
        let replacement = match string_bytes_of(arguments[1]) {
          Some(value) => value
          None => return invalid_string_argument(name, 2, arguments[1], span)
        }
        if old.length() == 0 {
          evaluation_error(
            InvalidOperand,
            "String.replace search text must not be empty",
            span,
          )
        } else {
          let result : Array[Int] = []
          let mut start = 0
          while start < bytes.length() {
            let found = string_index_of(bytes, old, start)
            if found < 0 {
              for byte in copy_byte_range(bytes, start, bytes.length()) {
                result.push(byte)
              }
              break
            }
            for byte in copy_byte_range(bytes, start, found) {
              result.push(byte)
            }
            for byte in replacement {
              result.push(byte)
            }
            start = found + old.length()
          }
          EvaluationSucceeded(string_value_from_bytes(result))
        }
      }
    _ => invoke_sequence_operation(receiver, name, arguments, span, context)
  }
}

///|
fn invoke_string_method(
  text : String,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  invoke_string_bytes_method(
    Value::string(text),
    utf8_bytes(text),
    name,
    arguments,
    span,
    context,
  )
}

///|
fn invoke_raw_string_method(
  bytes : Array[Int],
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  invoke_string_bytes_method(
    Value::raw_string(bytes),
    bytes,
    name,
    arguments,
    span,
    context,
  )
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
    return EvaluationSucceeded(arguments[0])
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
    EvaluationSucceeded(value) if !value.is_truthy() => IteratorComplete
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
    SequenceSnapshot(items) | SequenceMapView(items, _) =>
      if iterator.yielded >= items.length() {
        complete()
      } else {
        iterator.current = items[iterator.yielded]
        iterator.yielded = iterator.yielded + 1
        EvaluationSucceeded(Value::iterator(iterator_identifier))
      }
    SequenceStringBytes(items) =>
      if iterator.yielded >= items.length() {
        complete()
      } else {
        iterator.current = items[iterator.yielded]
        iterator.yielded = iterator.yielded + 1
        EvaluationSucceeded(Value::iterator(iterator_identifier))
      }
    SequenceStringCodePoints(_, iterated) =>
      if iterator.yielded >= iterated.length() {
        complete()
      } else {
        iterator.current = iterated[iterator.yielded]
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
      EvaluationSucceeded(value) if !value.is_truthy() => break
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
  FiberExpressionReady(Expr)
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
fn method_call_closure(
  receiver : Value,
  resolved : ResolvedMethod,
  context : RuntimeContext,
) -> Int? {
  if resolved.owner_identifier < 0 ||
    resolved.owner_identifier >= context.classes.length() ||
    resolved.declaration.is_foreign {
    return None
  }
  let owner = context.classes[resolved.owner_identifier]
  let environment = owner.environment.capture()
  environment.push_scope()
  match receiver {
    InstanceValue(instance_identifier) => {
      ignore(environment.bind("this", receiver))
      ignore(
        environment.bind(
          "$class",
          Value::class_value(resolved.owner_identifier),
        ),
      )
      ignore(
        environment.bind(
          "$super",
          SuperValue(
            owner.superclass.unwrap_or(-1),
            instance_identifier,
            resolved.declaration.name,
            resolved.declaration.is_constructor,
          ),
        ),
      )
    }
    ClassValue(receiver_class) => {
      ignore(environment.bind("this", receiver))
      ignore(
        environment.bind(
          "$class",
          Value::class_value(resolved.owner_identifier),
        ),
      )
      ignore(
        environment.bind(
          "$super",
          SuperClassValue(owner.superclass.unwrap_or(-1), receiver_class),
        ),
      )
    }
    _ => return None
  }
  let identifier = context.closures.length()
  context.closures.push({
    parameters: resolved.declaration.parameters,
    body: resolved.declaration.body,
    environment,
    source_name: owner.source_name,
    alive: true,
  })
  Some(identifier)
}

///|
fn instance_has_method(
  receiver : Value,
  name : String,
  arity : Int,
  context : RuntimeContext,
) -> Bool {
  match receiver {
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        let class_identifier = context.instances[identifier].class_identifier
        match
          find_method_in_class(
            context, class_identifier, name, arity, false, false, false,
          ) {
          Some(_) => true
          None => false
        }
      } else {
        false
      }
    ClassValue(identifier) =>
      match
        find_method_in_class(
          context, identifier, name, arity, false, false, true,
        ) {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
fn receiver_has_getter(
  receiver : Value,
  name : String,
  context : RuntimeContext,
) -> Bool {
  match receiver {
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        match
          find_method_in_class(
            context,
            context.instances[identifier].class_identifier,
            name,
            0,
            false,
            true,
            false,
          ) {
          Some(_) => true
          None => false
        }
      } else {
        false
      }
    ClassValue(identifier) =>
      match
        find_method_in_class(context, identifier, name, 0, false, true, true) {
        Some(_) => true
        None => false
      }
    _ => false
  }
}

///|
fn unary_method_name(operator : UnaryOperator) -> String {
  match operator {
    LogicalNot => "!"
    Negate => "-"
    BitwiseNot => "~"
  }
}

///|
fn binary_method_name(operator : BinaryOperator) -> String {
  match operator {
    Add => "+"
    Subtract => "-"
    Multiply => "*"
    Divide => "/"
    Remainder => "%"
    EqualTo => "=="
    NotEqualTo => "!="
    LessThan => "<"
    LessThanOrEqual => "<="
    GreaterThan => ">"
    GreaterThanOrEqual => ">="
    BitwiseAnd => "&"
    BitwiseOr => "|"
    BitwiseXor => "^"
    ShiftLeft => "<<"
    ShiftRight => ">>"
    InclusiveRange => ".."
    ExclusiveRange => "..."
    LogicalAnd | LogicalOr | IsType => ""
  }
}

///|
fn finish_fiber_sequence_operation(
  name : String,
  aggregate : Value,
  count : Int,
  span : SourceSpan,
) -> FiberExpressionStep {
  FiberExpressionReady(
    Literal(
      if name == "count" {
        Value::number(Double::from_int(count))
      } else if name == "each" {
        Value::null()
      } else {
        aggregate
      },
      span,
    ),
  )
}

///|
fn resume_fiber_sequence_callback(
  call_identifier : Int,
  input : Value,
  iterable : Value,
  iterator : Value,
  function_identifier : Int,
  name : String,
  aggregate : Value,
  count : Int,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  match resume_runtime_fiber(call_identifier, input, span, context) {
    EvaluationFailed(issue) => FiberExpressionFailed(issue)
    EvaluationSucceeded(result) => {
      let call_fiber = context.fibers[call_identifier]
      if call_fiber.state == 2 {
        FiberExpressionYielded(result, fn(resumed) {
          FiberSequenceResume(
            call_identifier, resumed, iterable, iterator, function_identifier, name,
            aggregate, count, span,
          )
        })
      } else if name == "all" && !result.is_truthy() {
        FiberExpressionReady(Literal(result, span))
      } else if name == "any" && result.is_truthy() {
        FiberExpressionReady(Literal(result, span))
      } else {
        execute_fiber_sequence_operation(
          iterable,
          iterator,
          function_identifier,
          name,
          if name == "all" {
            result
          } else {
            aggregate
          },
          if name == "count" && result.is_truthy() {
            count + 1
          } else {
            count
          },
          span,
          context,
        )
      }
    }
  }
}

///|
fn execute_fiber_sequence_operation(
  iterable : Value,
  iterator : Value,
  function_identifier : Int,
  name : String,
  aggregate : Value,
  count : Int,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  match advance_iterable(iterable, iterator, span, context) {
    IteratorAdvanceFailed(issue) => FiberExpressionFailed(issue)
    IteratorComplete =>
      finish_fiber_sequence_operation(name, aggregate, count, span)
    IteratorAdvanced(next, value) => {
      let call_identifier = context.new_function_fiber(
        function_identifier,
        [value],
        context.current_fiber,
      )
      resume_fiber_sequence_callback(
        call_identifier,
        Value::null(),
        iterable,
        next,
        function_identifier,
        name,
        aggregate,
        count,
        span,
        context,
      )
    }
  }
}

///|
fn resume_fiber_expression_call(
  identifier : Int,
  input : Value,
  result_override : Value?,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  match resume_runtime_fiber(identifier, input, span, context) {
    EvaluationFailed(issue) => FiberExpressionFailed(issue)
    EvaluationSucceeded(value) => {
      let fiber = context.fibers[identifier]
      if fiber.state == 2 {
        FiberExpressionYielded(value, fn(resumed) {
          FiberCallResume(identifier, resumed, result_override, span)
        })
      } else {
        FiberExpressionReady(
          Literal(
            match result_override {
              Some(overridden_result) => overridden_result
              None => value
            },
            span,
          ),
        )
      }
    }
  }
}

///|
fn start_fiber_expression_call(
  function_identifier : Int,
  arguments : Array[Value],
  result_override : Value?,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  if function_identifier < 0 || function_identifier >= context.closures.length() {
    return FiberExpressionFailed(
      Diagnostic::new(
        Runtime,
        UndefinedMethod,
        "function is not available in this runtime",
        span,
      ),
    )
  }
  let closure = context.closures[function_identifier]
  if arguments.length() < closure.parameters.length() {
    return FiberExpressionFailed(
      Diagnostic::new(
        Runtime,
        InvalidArity,
        "function expects at least {closure.parameters.length()} arguments, received {arguments.length()}",
        span,
      ),
    )
  }
  let identifier = context.new_function_fiber(
    function_identifier,
    arguments,
    context.current_fiber,
  )
  resume_fiber_expression_call(
    identifier,
    Value::null(),
    result_override,
    span,
    context,
  )
}

///|
fn prepare_evaluated_method_call(
  receiver : Value,
  name : String,
  arguments : Array[Value],
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  if (name == "all" || name == "any" || name == "count" || name == "each") &&
    arguments.length() == 1 {
    match arguments[0] {
      FunctionValue(function_identifier) =>
        return execute_fiber_sequence_operation(
          receiver,
          Value::null(),
          function_identifier,
          name,
          Value::bool(name == "all"),
          0,
          span,
          context,
        )
      _ => ()
    }
  }
  let resolved = match receiver {
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        find_method_in_class(
          context,
          context.instances[identifier].class_identifier,
          name,
          arguments.length(),
          false,
          false,
          false,
        )
      } else {
        None
      }
    ClassValue(identifier) =>
      find_method_in_class(
        context,
        identifier,
        name,
        arguments.length(),
        false,
        false,
        true,
      )
    SuperValue(superclass, _, _, _) =>
      find_method_in_class(
        context,
        superclass,
        name,
        arguments.length(),
        false,
        false,
        false,
      )
    SuperClassValue(superclass, _) =>
      find_method_in_class(
        context,
        superclass,
        name,
        arguments.length(),
        false,
        false,
        true,
      )
    _ => None
  }
  match resolved {
    Some(resolved) => {
      let method_receiver = match receiver {
        SuperValue(_, instance_identifier, _, _) =>
          Value::instance(instance_identifier)
        SuperClassValue(_, receiver_class) => Value::class_value(receiver_class)
        value => value
      }
      match method_call_closure(method_receiver, resolved, context) {
        Some(function_identifier) =>
          start_fiber_expression_call(
            function_identifier,
            arguments,
            None,
            span,
            context,
          )
        None =>
          match invoke_method(receiver, name, arguments, span, context) {
            EvaluationSucceeded(value) =>
              FiberExpressionReady(Literal(value, span))
            EvaluationFailed(issue) => FiberExpressionFailed(issue)
          }
      }
    }
    None =>
      match receiver {
        ClassValue(identifier) if identifier >= 0 &&
          identifier < context.classes.length() => {
          let class_definition = context.classes[identifier]
          match
            find_method_in_class(
              context,
              identifier,
              name,
              arguments.length(),
              true,
              false,
              false,
            ) {
            Some(constructor_method) if !class_definition.is_foreign => {
              let instance_identifier = context.new_instance(identifier, None)
              let instance = Value::instance(instance_identifier)
              match method_call_closure(instance, constructor_method, context) {
                Some(function_identifier) =>
                  start_fiber_expression_call(
                    function_identifier,
                    arguments,
                    Some(instance),
                    span,
                    context,
                  )
                None =>
                  match
                    invoke_method(receiver, name, arguments, span, context) {
                    EvaluationSucceeded(value) =>
                      FiberExpressionReady(Literal(value, span))
                    EvaluationFailed(issue) => FiberExpressionFailed(issue)
                  }
              }
            }
            _ =>
              match invoke_method(receiver, name, arguments, span, context) {
                EvaluationSucceeded(value) =>
                  FiberExpressionReady(Literal(value, span))
                EvaluationFailed(issue) => FiberExpressionFailed(issue)
              }
          }
        }
        FunctionValue(identifier) if name == "call" =>
          start_fiber_expression_call(
            identifier,
            arguments,
            None,
            span,
            context,
          )
        _ =>
          match invoke_method(receiver, name, arguments, span, context) {
            EvaluationSucceeded(value) =>
              FiberExpressionReady(Literal(value, span))
            EvaluationFailed(issue) => FiberExpressionFailed(issue)
          }
      }
  }
}

///|
fn prepare_evaluated_property_get(
  receiver : Value,
  name : String,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberExpressionStep {
  let resolved = match receiver {
    InstanceValue(identifier) =>
      if identifier >= 0 && identifier < context.instances.length() {
        find_method_in_class(
          context,
          context.instances[identifier].class_identifier,
          name,
          0,
          false,
          true,
          false,
        )
      } else {
        None
      }
    ClassValue(identifier) =>
      find_method_in_class(context, identifier, name, 0, false, true, true)
    SuperValue(superclass, _, _, _) =>
      find_method_in_class(context, superclass, name, 0, false, true, false)
    SuperClassValue(superclass, _) =>
      find_method_in_class(context, superclass, name, 0, false, true, true)
    _ => None
  }
  match resolved {
    Some(resolved) => {
      let method_receiver = match receiver {
        SuperValue(_, instance_identifier, _, _) =>
          Value::instance(instance_identifier)
        SuperClassValue(_, receiver_class) => Value::class_value(receiver_class)
        value => value
      }
      match method_call_closure(method_receiver, resolved, context) {
        Some(function_identifier) =>
          start_fiber_expression_call(
            function_identifier,
            [],
            None,
            span,
            context,
          )
        None =>
          match read_property(receiver, name, span, context) {
            EvaluationSucceeded(value) =>
              FiberExpressionReady(Literal(value, span))
            EvaluationFailed(issue) => FiberExpressionFailed(issue)
          }
      }
    }
    None =>
      match read_property(receiver, name, span, context) {
        EvaluationSucceeded(value) => FiberExpressionReady(Literal(value, span))
        EvaluationFailed(issue) => FiberExpressionFailed(issue)
      }
  }
}

///|
fn prepare_fiber_expression(
  expression : Expr,
  environment : Environment,
  context : RuntimeContext,
) -> FiberExpressionStep {
  match expression {
    FiberCallResume(identifier, input, result_override, span) =>
      resume_fiber_expression_call(
        identifier, input, result_override, span, context,
      )
    FiberSequenceResume(
      call_identifier,
      input,
      iterable,
      iterator,
      function_identifier,
      name,
      aggregate,
      count,
      span
    ) =>
      resume_fiber_sequence_callback(
        call_identifier, input, iterable, iterator, function_identifier, name, aggregate,
        count, span, context,
      )
    MethodCall(receiver, name, arguments, span) => {
      let prepared_receiver = match
        prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberExpressionYielded(yielded, fn(resumed) {
            MethodCall(continuation(resumed), name, arguments, span)
          })
        FiberExpressionReady(prepared) => prepared
      }
      let prepared_arguments : Array[Expr] = []
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
                if position < argument_index {
                  rebuilt.push(prepared_arguments[position])
                } else if position == argument_index {
                  rebuilt.push(continuation(resumed))
                } else {
                  rebuilt.push(arguments[position])
                }
              }
              MethodCall(prepared_receiver, name, rebuilt, span)
            })
          }
          FiberExpressionReady(prepared) => prepared_arguments.push(prepared)
        }
      }
      let receiver_value = match
        evaluate_expression_in(prepared_receiver, environment, context) {
        EvaluationFailed(issue) => return FiberExpressionFailed(issue)
        EvaluationSucceeded(value) => value
      }
      let argument_values : Array[Value] = []
      for argument in prepared_arguments {
        match evaluate_expression_in(argument, environment, context) {
          EvaluationFailed(issue) => return FiberExpressionFailed(issue)
          EvaluationSucceeded(value) => argument_values.push(value)
        }
      }
      match receiver_value {
        CoreClassValue(FiberClass) if name == "yield" || name == "suspend" => {
          let valid_arity = if name == "suspend" {
            argument_values.length() == 0
          } else {
            argument_values.length() <= 1
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
          let yielded = if argument_values.length() == 0 {
            Value::null()
          } else {
            argument_values[0]
          }
          FiberExpressionYielded(yielded, fn(resumed) { Literal(resumed, span) })
        }
        FiberValue(target) if name == "transfer" && context.current_fiber != 0 => {
          if target == context.current_fiber {
            let value = if argument_values.length() == 0 {
              Value::null()
            } else {
              argument_values[0]
            }
            return FiberExpressionReady(Literal(value, span))
          }
          if argument_values.length() > 1 {
            return FiberExpressionFailed(
              Diagnostic::new(
                Runtime,
                InvalidArity,
                "Fiber.transfer expects zero or one argument",
                span,
              ),
            )
          }
          context.transfer_target = target
          let yielded = if argument_values.length() == 0 {
            Value::null()
          } else {
            argument_values[0]
          }
          FiberExpressionYielded(yielded, fn(resumed) { Literal(resumed, span) })
        }
        _ =>
          prepare_evaluated_method_call(
            receiver_value, name, argument_values, span, context,
          )
      }
    }
    PropertyGet(receiver, name, span) => {
      let prepared_receiver = match
        prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberExpressionYielded(yielded, fn(resumed) {
            PropertyGet(continuation(resumed), name, span)
          })
        FiberExpressionReady(prepared) => prepared
      }
      match evaluate_expression_in(prepared_receiver, environment, context) {
        EvaluationFailed(issue) => FiberExpressionFailed(issue)
        EvaluationSucceeded(receiver_value) =>
          prepare_evaluated_property_get(receiver_value, name, span, context)
      }
    }
    PropertySet(receiver, name, value, span) => {
      let prepared_receiver = match
        prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          return FiberExpressionYielded(yielded, fn(resumed) {
            PropertySet(continuation(resumed), name, value, span)
          })
        FiberExpressionReady(prepared) => prepared
      }
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            PropertySet(prepared_receiver, name, continuation(resumed), span)
          })
        FiberExpressionReady(prepared_value) => {
          let receiver_value = match
            evaluate_expression_in(prepared_receiver, environment, context) {
            EvaluationFailed(issue) => return FiberExpressionFailed(issue)
            EvaluationSucceeded(result) => result
          }
          let assigned = match
            evaluate_expression_in(prepared_value, environment, context) {
            EvaluationFailed(issue) => return FiberExpressionFailed(issue)
            EvaluationSucceeded(result) => result
          }
          prepare_evaluated_method_call(
            receiver_value,
            name + "=",
            [assigned],
            span,
            context,
          )
        }
      }
    }
    Grouping(inner, span) =>
      match prepare_fiber_expression(inner, environment, context) {
        FiberExpressionReady(prepared) =>
          FiberExpressionReady(Grouping(prepared, span))
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Grouping(continuation(resumed), span)
          })
      }
    Unary(operator, right, span) =>
      match prepare_fiber_expression(right, environment, context) {
        FiberExpressionReady(prepared) => {
          let value = match
            evaluate_expression_in(prepared, environment, context) {
            EvaluationFailed(issue) => return FiberExpressionFailed(issue)
            EvaluationSucceeded(value) => value
          }
          let name = unary_method_name(operator)
          if instance_has_method(value, name, 0, context) {
            prepare_evaluated_method_call(value, name, [], span, context)
          } else {
            match evaluate_unary(operator, value, span, context) {
              EvaluationFailed(issue) => FiberExpressionFailed(issue)
              EvaluationSucceeded(result) =>
                FiberExpressionReady(Literal(result, span))
            }
          }
        }
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
        FiberExpressionReady(prepared_left) => {
          if operator == LogicalAnd || operator == LogicalOr {
            let left_value = match
              evaluate_expression_in(prepared_left, environment, context) {
              EvaluationFailed(issue) => return FiberExpressionFailed(issue)
              EvaluationSucceeded(value) => value
            }
            if (operator == LogicalAnd && !left_value.is_truthy()) ||
              (operator == LogicalOr && left_value.is_truthy()) {
              return FiberExpressionReady(Literal(left_value, span))
            }
            return prepare_fiber_expression(right, environment, context)
          }
          match prepare_fiber_expression(right, environment, context) {
            FiberExpressionReady(prepared_right) => {
              let left_value = match
                evaluate_expression_in(prepared_left, environment, context) {
                EvaluationFailed(issue) => return FiberExpressionFailed(issue)
                EvaluationSucceeded(value) => value
              }
              let right_value = match
                evaluate_expression_in(prepared_right, environment, context) {
                EvaluationFailed(issue) => return FiberExpressionFailed(issue)
                EvaluationSucceeded(value) => value
              }
              let name = binary_method_name(operator)
              if name != "" && instance_has_method(left_value, name, 1, context) {
                prepare_evaluated_method_call(
                  left_value,
                  name,
                  [right_value],
                  span,
                  context,
                )
              } else {
                match
                  evaluate_binary_values(
                    operator, left_value, right_value, span, context,
                  ) {
                  EvaluationFailed(issue) => FiberExpressionFailed(issue)
                  EvaluationSucceeded(result) =>
                    FiberExpressionReady(Literal(result, span))
                }
              }
            }
            FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
            FiberExpressionYielded(yielded, continuation) =>
              FiberExpressionYielded(yielded, fn(resumed) {
                Binary(prepared_left, operator, continuation(resumed), span)
              })
          }
        }
      }
    Assign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady(prepared) =>
          FiberExpressionReady(Assign(name, prepared, span))
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Assign(name, continuation(resumed), span)
          })
      }
    FieldAssign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady(prepared) =>
          FiberExpressionReady(FieldAssign(name, prepared, span))
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            FieldAssign(name, continuation(resumed), span)
          })
      }
    StaticFieldAssign(name, value, span) =>
      match prepare_fiber_expression(value, environment, context) {
        FiberExpressionReady(prepared) =>
          FiberExpressionReady(StaticFieldAssign(name, prepared, span))
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
        FiberExpressionReady(prepared_receiver) =>
          match prepare_fiber_expression(index, environment, context) {
            FiberExpressionReady(prepared_index) => {
              let receiver_value = match
                evaluate_expression_in(prepared_receiver, environment, context) {
                EvaluationFailed(issue) => return FiberExpressionFailed(issue)
                EvaluationSucceeded(value) => value
              }
              let index_value = match
                evaluate_expression_in(prepared_index, environment, context) {
                EvaluationFailed(issue) => return FiberExpressionFailed(issue)
                EvaluationSucceeded(value) => value
              }
              if instance_has_method(receiver_value, "[]", 1, context) {
                prepare_evaluated_method_call(
                  receiver_value,
                  "[]",
                  [index_value],
                  span,
                  context,
                )
              } else {
                match
                  read_subscript(receiver_value, index_value, span, context) {
                  EvaluationFailed(issue) => FiberExpressionFailed(issue)
                  EvaluationSucceeded(result) =>
                    FiberExpressionReady(Literal(result, span))
                }
              }
            }
            FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
            FiberExpressionYielded(yielded, continuation) =>
              FiberExpressionYielded(yielded, fn(resumed) {
                SubscriptGet(prepared_receiver, continuation(resumed), span)
              })
          }
      }
    SubscriptSet(receiver, index, value, span) =>
      match prepare_fiber_expression(receiver, environment, context) {
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            SubscriptSet(continuation(resumed), index, value, span)
          })
        FiberExpressionReady(prepared_receiver) =>
          match prepare_fiber_expression(index, environment, context) {
            FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
            FiberExpressionYielded(yielded, continuation) =>
              FiberExpressionYielded(yielded, fn(resumed) {
                SubscriptSet(
                  prepared_receiver,
                  continuation(resumed),
                  value,
                  span,
                )
              })
            FiberExpressionReady(prepared_index) =>
              match prepare_fiber_expression(value, environment, context) {
                FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
                FiberExpressionYielded(yielded, continuation) =>
                  FiberExpressionYielded(yielded, fn(resumed) {
                    SubscriptSet(
                      prepared_receiver,
                      prepared_index,
                      continuation(resumed),
                      span,
                    )
                  })
                FiberExpressionReady(prepared_value) => {
                  let receiver_value = match
                    evaluate_expression_in(
                      prepared_receiver, environment, context,
                    ) {
                    EvaluationFailed(issue) =>
                      return FiberExpressionFailed(issue)
                    EvaluationSucceeded(result) => result
                  }
                  let index_value = match
                    evaluate_expression_in(prepared_index, environment, context) {
                    EvaluationFailed(issue) =>
                      return FiberExpressionFailed(issue)
                    EvaluationSucceeded(result) => result
                  }
                  let assigned = match
                    evaluate_expression_in(prepared_value, environment, context) {
                    EvaluationFailed(issue) =>
                      return FiberExpressionFailed(issue)
                    EvaluationSucceeded(result) => result
                  }
                  if instance_has_method(receiver_value, "[]=", 2, context) {
                    prepare_evaluated_method_call(
                      receiver_value,
                      "[]=",
                      [index_value, assigned],
                      span,
                      context,
                    )
                  } else {
                    match
                      write_subscript(
                        receiver_value, index_value, assigned, span, context,
                      ) {
                      EvaluationFailed(issue) => FiberExpressionFailed(issue)
                      EvaluationSucceeded(result) =>
                        FiberExpressionReady(Literal(result, span))
                    }
                  }
                }
              }
          }
      }
    SuperConstructorCall(arguments, span) => {
      let prepared : Array[Expr] = []
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
                if position < argument_index {
                  rebuilt.push(prepared[position])
                } else if position == argument_index {
                  rebuilt.push(continuation(resumed))
                } else {
                  rebuilt.push(arguments[position])
                }
              }
              SuperConstructorCall(rebuilt, span)
            })
          }
          FiberExpressionReady(argument) => prepared.push(argument)
        }
      }
      let values : Array[Value] = []
      for argument in prepared {
        match evaluate_expression_in(argument, environment, context) {
          EvaluationFailed(issue) => return FiberExpressionFailed(issue)
          EvaluationSucceeded(value) => values.push(value)
        }
      }
      match environment.get("$super") {
        Some(
          SuperValue(
            superclass,
            instance_identifier,
            method_name,
            is_constructor
          )
        ) =>
          match
            find_method_in_class(
              context,
              superclass,
              method_name,
              values.length(),
              is_constructor,
              false,
              false,
            ) {
            Some(resolved) => {
              let instance = Value::instance(instance_identifier)
              match method_call_closure(instance, resolved, context) {
                Some(function_identifier) =>
                  start_fiber_expression_call(
                    function_identifier,
                    values,
                    Some(instance),
                    span,
                    context,
                  )
                None =>
                  match
                    invoke_super_constructor(
                      superclass, instance_identifier, method_name, is_constructor,
                      values, span, context,
                    ) {
                    EvaluationFailed(issue) => FiberExpressionFailed(issue)
                    EvaluationSucceeded(result) =>
                      FiberExpressionReady(Literal(result, span))
                  }
              }
            }
            None =>
              FiberExpressionFailed(
                Diagnostic::new(
                  Runtime,
                  UndefinedMethod,
                  "superclass constructor is not available",
                  span,
                ),
              )
          }
        _ =>
          FiberExpressionFailed(
            Diagnostic::new(
              Runtime,
              UndefinedMethod,
              "super can only be used in a subclass constructor",
              span,
            ),
          )
      }
    }
    Conditional(condition, then_branch, else_branch, span) =>
      match prepare_fiber_expression(condition, environment, context) {
        FiberExpressionFailed(issue) => FiberExpressionFailed(issue)
        FiberExpressionYielded(yielded, continuation) =>
          FiberExpressionYielded(yielded, fn(resumed) {
            Conditional(continuation(resumed), then_branch, else_branch, span)
          })
        FiberExpressionReady(prepared_condition) =>
          match
            evaluate_expression_in(prepared_condition, environment, context) {
            EvaluationFailed(issue) => FiberExpressionFailed(issue)
            EvaluationSucceeded(value) =>
              prepare_fiber_expression(
                if value.is_truthy() {
                  then_branch
                } else {
                  else_branch
                },
                environment,
                context,
              )
          }
      }
    ListLiteral(items, span) => {
      let prepared : Array[Expr] = []
      for index = 0; index < items.length(); index = index + 1 {
        match prepare_fiber_expression(items[index], environment, context) {
          FiberExpressionFailed(issue) => return FiberExpressionFailed(issue)
          FiberExpressionYielded(yielded, continuation) => {
            let item_index = index
            return FiberExpressionYielded(yielded, fn(resumed) {
              let rebuilt : Array[Expr] = []
              for position = 0
                  position < items.length()
                  position = position + 1 {
                if position < item_index {
                  rebuilt.push(prepared[position])
                } else if position == item_index {
                  rebuilt.push(continuation(resumed))
                } else {
                  rebuilt.push(items[position])
                }
              }
              ListLiteral(rebuilt, span)
            })
          }
          FiberExpressionReady(item) => prepared.push(item)
        }
      }
      FiberExpressionReady(ListLiteral(prepared, span))
    }
    _ => FiberExpressionReady(expression)
  }
}

///|
fn resume_fiber_each_callback(
  call_identifier : Int,
  input : Value,
  iterable : Value,
  iterator : Value,
  function_identifier : Int,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberStatementStep {
  match resume_runtime_fiber(call_identifier, input, span, context) {
    EvaluationFailed(issue) => FiberStatementFailed(issue)
    EvaluationSucceeded(value) => {
      let call_fiber = context.fibers[call_identifier]
      if call_fiber.state == 2 {
        FiberStatementYielded(value, fn(resumed) {
          resume_fiber_each_callback(
            call_identifier, resumed, iterable, iterator, function_identifier, span,
            context,
          )
        })
      } else {
        execute_fiber_each(
          iterable, iterator, function_identifier, span, context,
        )
      }
    }
  }
}

///|
fn execute_fiber_each(
  iterable : Value,
  iterator : Value,
  function_identifier : Int,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberStatementStep {
  match advance_iterable(iterable, iterator, span, context) {
    IteratorAdvanceFailed(issue) => FiberStatementFailed(issue)
    IteratorComplete =>
      FiberStatementCompleted(StatementCompleted(Value::null()))
    IteratorAdvanced(next, value) => {
      let call_identifier = context.new_function_fiber(
        function_identifier,
        [value],
        context.current_fiber,
      )
      resume_fiber_each_callback(
        call_identifier,
        Value::null(),
        iterable,
        next,
        function_identifier,
        span,
        context,
      )
    }
  }
}

///|
fn prepare_fiber_each_call(
  receiver : Expr,
  callback : Expr,
  span : SourceSpan,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep? {
  let iterable = match evaluate_expression_in(receiver, environment, context) {
    EvaluationFailed(issue) => return Some(FiberStatementFailed(issue))
    EvaluationSucceeded(value) => value
  }
  let function_identifier = match
    evaluate_expression_in(callback, environment, context) {
    EvaluationFailed(issue) => return Some(FiberStatementFailed(issue))
    EvaluationSucceeded(FunctionValue(identifier)) => identifier
    EvaluationSucceeded(_) => return None
  }
  Some(
    execute_fiber_each(
      iterable,
      Value::null(),
      function_identifier,
      span,
      context,
    ),
  )
}

///|
fn bind_imported_values(
  specifier : String,
  bindings : Array[ImportBinding],
  module_environment : Environment,
  environment : Environment,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberStatementStep {
  for binding in bindings {
    let value = match module_environment.get(binding.name) {
      Some(value) => value
      None =>
        return FiberStatementFailed(
          Diagnostic::new(
            Runtime,
            UndefinedExport,
            "module '\{specifier}' does not define '\{binding.name}'",
            span,
          ).with_source(context.current_source),
        )
    }
    if environment.has_current(binding.local_name) {
      ignore(environment.assign(binding.local_name, value))
    } else if !environment.bind(binding.local_name, value) {
      return FiberStatementFailed(
        Diagnostic::new(
          Runtime,
          DuplicateVariable,
          "imported name '\{binding.local_name}' is already declared in this scope",
          span,
        ).with_source(context.current_source),
      )
    }
  }
  FiberStatementCompleted(StatementCompleted(Value::null()))
}

///|
fn continue_fiber_module(
  step : FiberStatementStep,
  module_index : Int,
  module_name : String,
  importer : String,
  specifier : String,
  bindings : Array[ImportBinding],
  environment : Environment,
  span : SourceSpan,
  context : RuntimeContext,
) -> FiberStatementStep {
  match step {
    FiberStatementReady => abort("module statement was not executed")
    FiberStatementFailed(issue) => {
      context.modules[module_index].state = 2
      context.current_source = importer
      FiberStatementFailed(issue)
    }
    FiberStatementYielded(value, continuation) => {
      context.current_source = importer
      FiberStatementYielded(value, fn(resumed) {
        context.current_source = module_name
        continue_fiber_module(
          continuation(resumed),
          module_index,
          module_name,
          importer,
          specifier,
          bindings,
          environment,
          span,
          context,
        )
      })
    }
    FiberStatementCompleted(result) =>
      match result {
        StatementCompleted(_) => {
          context.modules[module_index].state = 1
          let module_environment = context.modules[module_index].environment
          context.current_source = importer
          bind_imported_values(
            specifier, bindings, module_environment, environment, span, context,
          )
        }
        StatementFailed(issue) => {
          context.modules[module_index].state = 2
          context.current_source = importer
          FiberStatementFailed(issue)
        }
        StatementReturned(_, return_span) => {
          context.modules[module_index].state = 2
          context.current_source = importer
          FiberStatementFailed(
            Diagnostic::new(
              Runtime,
              ReturnOutsideFunction,
              "return can only be used inside a function",
              return_span,
            ).with_source(module_name),
          )
        }
        StatementBroken(control_span) | StatementContinued(control_span) => {
          context.modules[module_index].state = 2
          context.current_source = importer
          FiberStatementFailed(
            Diagnostic::new(
              Runtime,
              BreakOutsideLoop,
              "loop control cannot escape a module",
              control_span,
            ).with_source(module_name),
          )
        }
      }
  }
}

///|
fn prepare_fiber_import(
  specifier : String,
  bindings : Array[ImportBinding],
  span : SourceSpan,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  let importer = context.current_source
  let (module_name, source) = match (context.loader)(importer, specifier) {
    ModuleLoadFailed(message) =>
      return FiberStatementFailed(
        Diagnostic::new(Runtime, ModuleNotFound, message, span).with_source(
          importer,
        ),
      )
    ModuleLoaded(name, source) => (name, source)
  }
  if source.length() > context.max_source_characters {
    return FiberStatementFailed(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "module '\{module_name}' exceeds the source size limit",
        span,
      ).with_source(importer),
    )
  }
  match find_runtime_module(context, module_name) {
    Some(index) =>
      if context.modules[index].state == 2 {
        return FiberStatementFailed(
          Diagnostic::new(
            Runtime,
            ModuleNotFound,
            "module '\{module_name}' previously failed to load",
            span,
          ).with_source(importer),
        )
      } else {
        return bind_imported_values(
          specifier,
          bindings,
          context.modules[index].environment,
          environment,
          span,
          context,
        )
      }
    None => ()
  }
  if context.modules.length() >= context.max_modules {
    return FiberStatementFailed(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "module count limit exceeded",
        span,
      ).with_source(importer),
    )
  }
  let module_environment = Environment::new()
  bind_core_globals(module_environment)
  let module_index = context.modules.length()
  context.modules.push({
    name: module_name,
    environment: module_environment,
    state: 0,
  })
  let statements = match parse_program(source) {
    ProgramParseFailed(issues) => {
      context.modules[module_index].state = 2
      return FiberStatementFailed(
        Diagnostic::new(
          Runtime,
          issues[0].code,
          "could not compile module '\{specifier}': \{issues[0].message}",
          span,
        ).with_source(importer),
      )
    }
    ProgramParsed(statements) => statements
  }
  let resolution_issues = resolve_program(statements)
  if !resolution_issues.is_empty() {
    context.modules[module_index].state = 2
    return FiberStatementFailed(
      Diagnostic::new(
        Runtime,
        resolution_issues[0].code,
        "could not compile module '\{specifier}': \{resolution_issues[0].message}",
        span,
      ).with_source(importer),
    )
  }
  for statement in statements {
    match statement {
      VariableStatement(binding_name, _, _)
      | ClassStatement(binding_name, _, _, _, _, _) =>
        if !module_environment.has_current(binding_name) {
          ignore(module_environment.bind(binding_name, Value::null()))
        }
      ImportStatement(_, imported_bindings, _) =>
        for binding in imported_bindings {
          if !module_environment.has_current(binding.local_name) {
            ignore(module_environment.bind(binding.local_name, Value::null()))
          }
        }
      _ => ()
    }
  }
  context.current_source = module_name
  continue_fiber_module(
    execute_fiber_sequence(
      statements,
      0,
      Value::null(),
      module_environment,
      context,
    ),
    module_index,
    module_name,
    importer,
    specifier,
    bindings,
    environment,
    span,
    context,
  )
}

///|
fn prepare_fiber_statement(
  statement : Stmt,
  environment : Environment,
  context : RuntimeContext,
) -> FiberStatementStep {
  match statement {
    ImportStatement(specifier, bindings, span) =>
      prepare_fiber_import(specifier, bindings, span, environment, context)
    ExpressionStatement(MethodCall(receiver, "each", arguments, call_span), _) => {
      if arguments.length() == 1 {
        match
          prepare_fiber_each_call(
            receiver,
            arguments[0],
            call_span,
            environment,
            context,
          ) {
          Some(step) => return step
          None => ()
        }
      }
      FiberStatementReady
    }
    ExpressionStatement(expression, span) =>
      match prepare_fiber_expression(expression, environment, context) {
        FiberExpressionReady(prepared) =>
          FiberStatementCompleted(
            execute_statement_in(
              ExpressionStatement(prepared, span),
              environment,
              context,
            ),
          )
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
        FiberExpressionReady(prepared) =>
          FiberStatementCompleted(
            execute_statement_in(
              VariableStatement(name, Some(prepared), span),
              environment,
              context,
            ),
          )
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
        FiberExpressionReady(prepared) =>
          FiberStatementCompleted(
            execute_statement_in(
              ReturnStatement(Some(prepared), span),
              environment,
              context,
            ),
          )
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
    FiberExpressionReady(prepared_condition) =>
      match evaluate_expression_in(prepared_condition, environment, context) {
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
    EvaluationSucceeded(value) if !value.is_truthy() =>
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
      match context.step(span, environment) {
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
      match context.step(span, environment) {
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
        FiberExpressionReady(prepared_condition) =>
          match
            evaluate_expression_in(prepared_condition, environment, context) {
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
      match context.step(span, environment) {
        Some(issue) => return FiberStatementFailed(issue)
        None => ()
      }
      execute_fiber_while(condition, body, Value::null(), environment, context)
    }
    ForStatement(name, sequence, body, span) => {
      match context.step(span, environment) {
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
        FiberExpressionReady(prepared_sequence) =>
          match
            evaluate_expression_in(prepared_sequence, environment, context) {
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
      let target_fiber = context.fibers[identifier]
      if target_fiber.state == 1 {
        return evaluation_error(
          InvalidFiberState,
          "Fiber has already been called.",
          span,
        )
      }
      if target_fiber.state == 3 {
        return evaluation_error(
          InvalidFiberState,
          if name == "try" {
            "Cannot try a finished fiber."
          } else {
            "Cannot call a finished fiber."
          },
          span,
        )
      }
      if target_fiber.state == 4 {
        return evaluation_error(
          InvalidFiberState,
          if name == "try" {
            "Cannot try an aborted fiber."
          } else {
            "Cannot call an aborted fiber."
          },
          span,
        )
      }
      let input = if arguments.length() == 0 {
        Value::null()
      } else {
        arguments[0]
      }
      let caller = context.current_fiber
      match resume_fiber_transfer_chain(identifier, input, span, context) {
        EvaluationSucceeded(value) => {
          if name == "transfer" && caller == 0 && !context.transferred_to_main {
            context.terminate_main = true
          }
          EvaluationSucceeded(value)
        }
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
fn resume_fiber_transfer_chain(
  identifier : Int,
  input : Value,
  span : SourceSpan,
  context : RuntimeContext,
) -> EvaluationResult {
  let mut target = identifier
  let mut transferred = input
  context.transferred_to_main = false
  while true {
    context.transfer_target = -1
    let result = resume_runtime_fiber(target, transferred, span, context)
    match result {
      EvaluationFailed(issue) => return EvaluationFailed(issue)
      EvaluationSucceeded(value) => {
        let next = context.transfer_target
        if next == 0 {
          context.transferred_to_main = true
          return EvaluationSucceeded(value)
        }
        if next < 0 {
          return EvaluationSucceeded(value)
        }
        if next >= context.fibers.length() {
          return evaluation_error(
            InvalidFiberState,
            "transfer target is not available in this runtime",
            span,
          )
        }
        target = next
        transferred = value
      }
    }
  }
  EvaluationSucceeded(Value::null())
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
      let mut aggregate = Value::bool(name == "all")
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
              return EvaluationSucceeded(result)
            }
            if name == "any" && result.is_truthy() {
              return EvaluationSucceeded(result)
            }
            if name == "all" {
              aggregate = result
            }
            if name == "count" && result.is_truthy() {
              count = count + 1
            }
          }
        }
      }
      if name == "all" || name == "any" {
        EvaluationSucceeded(aggregate)
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
  if name == "iterate" || name == "iteratorValue" {
    match context.sequences[identifier].kind {
      SequenceSnapshot(items) =>
        return indexed_iterator("Sequence", items, name, arguments, span)
      SequenceMapView(items, _) =>
        return sparse_indexed_iterator(
          "Map sequence", items, name, arguments, span,
        )
      SequenceStringBytes(items) =>
        return indexed_string_view_iterator(
          "StringByteSequence", items, name, arguments, span,
        )
      SequenceStringCodePoints(indexed, _) =>
        return code_point_view_iterator(indexed, name, arguments, span)
      _ => ()
    }
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
        alive: true,
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
        match collection_index(arguments[0], items.length() + 1, false, span) {
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
    if name == "iteratorValue" {
      let raw = match arguments[0] {
        NumberValue(number) => {
          let index = number.to_int()
          if Double::from_int(index) != number {
            return evaluation_error(
              InvalidOperand,
              "Map iterator must be an integer",
              span,
            )
          }
          index
        }
        value =>
          return evaluation_error(
            InvalidOperand,
            "Map iterator must be a Num, received \{value.type_name()}",
            span,
          )
      }
      if raw < 0 || raw % 2 != 0 || raw / 2 >= entries.length() {
        return evaluation_error(
          IndexOutOfBounds,
          "Map iterator is outside the valid range",
          span,
        )
      }
      let index = raw / 2
      return EvaluationSucceeded(
        context.new_map_entry(entries[index].key, entries[index].value),
      )
    }
    let next = match arguments[0] {
      NullValue => 0
      NumberValue(number) => {
        let current = number.to_int()
        if Double::from_int(current) != number {
          return evaluation_error(
            InvalidOperand,
            "Map iterator must be an integer",
            span,
          )
        }
        if current < 0 {
          return EvaluationSucceeded(Value::bool(false))
        }
        (current / 2 + 1) * 2
      }
      value =>
        return evaluation_error(
          InvalidOperand,
          "Map iterator must be null or Num, received \{value.type_name()}",
          span,
        )
    }
    return if next / 2 >= entries.length() {
      EvaluationSucceeded(Value::bool(false))
    } else {
      EvaluationSucceeded(Value::number(Double::from_int(next)))
    }
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
  let mut fractional_digits = 0
  while index < characters.length() && is_digit(characters[index].to_int()) {
    value = value * 10.0 + Double::from_int(characters[index].to_int() - 48)
    digits = digits + 1
    index = index + 1
  }
  if index < characters.length() && characters[index].to_int() == 46 {
    index = index + 1
    while index < characters.length() && is_digit(characters[index].to_int()) {
      value = value * 10.0 + Double::from_int(characters[index].to_int() - 48)
      fractional_digits = fractional_digits + 1
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
  for digit_index = 0
      digit_index < fractional_digits
      digit_index = digit_index + 1 {
    value = value / 10.0
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
        EvaluationSucceeded(
          Value::bool(runtime_values_equal(arguments[0], arguments[1])),
        )
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
    (FiberClass, "yield") | (FiberClass, "suspend") => {
      context.terminate_main = true
      EvaluationSucceeded(Value::null())
    }
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
    (MapEntryClass, "new") =>
      if arguments.length() != 2 {
        invalid_collection_arity("MapEntry", name, 2, arguments.length(), span)
      } else {
        EvaluationSucceeded(context.new_map_entry(arguments[0], arguments[1]))
      }
    (NumClass, "fromString") =>
      if arguments.length() != 1 {
        invalid_collection_arity("Num", name, 1, arguments.length(), span)
      } else {
        match arguments[0] {
          StringValue(text) =>
            match parse_decimal_string(text.trim().to_owned()) {
              Some(number) =>
                if number.is_inf() {
                  evaluation_error(
                    InvalidNumber,
                    "Number literal is too large.",
                    span,
                  )
                } else {
                  EvaluationSucceeded(Value::number(number))
                }
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
            } else if byte <= 0x7f {
              EvaluationSucceeded(
                Value::string(byte.unsafe_to_char().to_string()),
              )
            } else {
              EvaluationSucceeded(Value::raw_string([byte]))
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
) -> Bool {
  let characters : Array[Char] = []
  for character in text.to_array() {
    if character.to_int() == 0 {
      break
    }
    characters.push(character)
  }
  let visible = String::from_array(characters)
  if self.output_characters + visible.length() > self.max_output_characters {
    return false
  }
  self.output_characters = self.output_characters + visible.length()
  if self.output_line_open {
    let index = self.output.length() - 1
    self.output[index] = self.output[index] + visible
  } else {
    self.output.push(visible)
  }
  self.output_line_open = !newline
  true
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
          } else if context.write_output("", true) {
            EvaluationSucceeded(Value::null())
          } else {
            evaluation_error(
              ExecutionLimit,
              "captured output limit exceeded",
              span,
            )
          }
        } else if arguments.length() == 1 {
          let value = arguments[0]
          if context.write_output(
              runtime_value_to_text(value, context, 0),
              name == "print",
            ) {
            EvaluationSucceeded(value)
          } else {
            evaluation_error(
              ExecutionLimit,
              "captured output limit exceeded",
              span,
            )
          }
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
            if context.write_output(text, name == "printAll") {
              EvaluationSucceeded(Value::null())
            } else {
              evaluation_error(
                ExecutionLimit,
                "captured output limit exceeded",
                span,
              )
            }
          }
        }
      } else if name == "gc" {
        if arguments.length() != 0 {
          invalid_collection_arity("System", name, 0, arguments.length(), span)
        } else {
          context.gc_requested = true
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
    RawStringValue(bytes) =>
      invoke_raw_string_method(bytes, name, arguments, span, context)
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
    SuperValue(superclass, instance_identifier, _, _) =>
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
      "\{receiver.type_name()} does not implement '\{name}'.",
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
      class_value == StringClass ||
      class_value == StringByteSequenceClass ||
      class_value == StringCodePointSequenceClass {
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
      "smallest" => EvaluationSucceeded(Value::number(2.2250738585072014e-308))
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
    "fraction" => {
      let fraction = number - truncated
      EvaluationSucceeded(
        Value::number(
          if fraction == 0.0 && number.reinterpret_as_uint64() >> 63 == 1UL {
            0x8000_0000_0000_0000UL.reinterpret_as_double()
          } else {
            fraction
          },
        ),
      )
    }
    "isInfinity" => EvaluationSucceeded(Value::bool(number.is_inf()))
    "isInteger" =>
      EvaluationSucceeded(
        Value::bool(!number.is_nan() && !number.is_inf() && truncated == number),
      )
    "isNan" => EvaluationSucceeded(Value::bool(number.is_nan()))
    "log" => EvaluationSucceeded(Value::number(@math.ln(number)))
    "log2" => EvaluationSucceeded(Value::number(@math.log2(number)))
    "round" => EvaluationSucceeded(Value::number(number.round()))
    "sign" =>
      EvaluationSucceeded(
        Value::number(
          if number > 0.0 {
            1.0
          } else if number < 0.0 {
            -1.0
          } else {
            0.0
          },
        ),
      )
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
              Value::string("instance of \{class_definition.name}"),
            )
          } else if name == "type" {
            EvaluationSucceeded(Value::class_value(class_identifier))
          } else if class_definition.inherits_sequence {
            read_sequence_property(receiver, name, span, context)
          } else {
            evaluation_error(
              UndefinedMethod,
              "\{class_definition.name} does not implement getter '\{name}'",
              span,
            )
          }
      }
    }
    SuperValue(superclass, instance_identifier, _, _) =>
      match
        find_method_in_class(context, superclass, name, 0, false, true, false) {
        Some(resolved) =>
          invoke_user_method(instance_identifier, resolved, [], span, context)
        None =>
          if superclass < 0 && name == "toString" {
            if instance_identifier >= 0 &&
              instance_identifier < context.instances.length() {
              let class_identifier = context.instances[instance_identifier].class_identifier
              EvaluationSucceeded(
                Value::string(
                  "instance of \{context.classes[class_identifier].name}",
                ),
              )
            } else {
              evaluation_error(
                UndefinedMethod,
                "instance is not available in this runtime",
                span,
              )
            }
          } else {
            evaluation_error(
              UndefinedMethod,
              "superclass does not implement getter '\{name}'",
              span,
            )
          }
      }
    ClassValue(identifier) =>
      match
        find_method_in_class(context, identifier, name, 0, false, true, true) {
        Some(resolved) =>
          invoke_static_method(identifier, resolved, [], span, context)
        None =>
          if name == "toString" || name == "name" {
            EvaluationSucceeded(Value::string(context.classes[identifier].name))
          } else if name == "attributes" {
            EvaluationSucceeded(context.classes[identifier].attributes)
          } else if name == "type" {
            EvaluationSucceeded(
              Value::meta_class(context.classes[identifier].name + " metaclass"),
            )
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
        if class_value == ClassClass {
          EvaluationSucceeded(Value::core_class(ClassClass))
        } else {
          EvaluationSucceeded(
            Value::meta_class(class_value.name() + " metaclass"),
          )
        }
      } else {
        read_core_class_property(class_value, name, span, context)
      }
    MetaClassValue(meta_name) =>
      if name == "name" || name == "toString" {
        EvaluationSucceeded(Value::string(meta_name))
      } else if name == "type" {
        EvaluationSucceeded(Value::core_class(ClassClass))
      } else {
        evaluation_error(
          UndefinedMethod,
          "\{meta_name} does not implement getter '\{name}'",
          span,
        )
      }
    ClassAttributesValue(self_identifier, methods_identifier) =>
      if name == "self" {
        if self_identifier < 0 {
          EvaluationSucceeded(Value::null())
        } else {
          EvaluationSucceeded(Value::map(self_identifier))
        }
      } else if name == "methods" {
        if methods_identifier < 0 {
          EvaluationSucceeded(Value::null())
        } else {
          EvaluationSucceeded(Value::map(methods_identifier))
        }
      } else if name == "toString" {
        EvaluationSucceeded(Value::string("<class attributes>"))
      } else {
        evaluation_error(
          UndefinedMethod,
          "ClassAttributes does not implement getter '\{name}'",
          span,
        )
      }
    SuperClassValue(superclass, receiver_class) =>
      match
        find_method_in_class(context, superclass, name, 0, false, true, true) {
        Some(resolved) =>
          invoke_static_method(receiver_class, resolved, [], span, context)
        None =>
          if superclass < 0 && (name == "name" || name == "toString") {
            EvaluationSucceeded(
              Value::string(context.classes[receiver_class].name),
            )
          } else {
            evaluation_error(
              UndefinedMethod,
              "superclass does not implement static getter '\{name}'",
              span,
            )
          }
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
            Value::number(
              Double::from_int(string_count_from_bytes(utf8_bytes(text))),
            ),
          )
        "toString" => EvaluationSucceeded(receiver)
        "bytes" => {
          let values : Array[Value] = []
          for byte in utf8_bytes(text) {
            values.push(Value::number(Double::from_int(byte)))
          }
          EvaluationSucceeded(
            context.new_sequence_kind(SequenceStringBytes(values)),
          )
        }
        "codePoints" => {
          let (indexed, iterated) = string_code_point_views_from_bytes(
            utf8_bytes(text),
          )
          EvaluationSucceeded(
            context.new_sequence_kind(
              SequenceStringCodePoints(indexed, iterated),
            ),
          )
        }
        "type" => EvaluationSucceeded(Value::core_class(StringClass))
        _ => read_sequence_property(receiver, name, span, context)
      }
    RawStringValue(bytes) =>
      match name {
        "count" =>
          EvaluationSucceeded(
            Value::number(Double::from_int(string_count_from_bytes(bytes))),
          )
        "toString" => EvaluationSucceeded(receiver)
        "bytes" => {
          let values : Array[Value] = []
          for byte in bytes {
            values.push(Value::number(Double::from_int(byte)))
          }
          EvaluationSucceeded(
            context.new_sequence_kind(SequenceStringBytes(values)),
          )
        }
        "codePoints" => {
          let (indexed, iterated) = string_code_point_views_from_bytes(bytes)
          EvaluationSucceeded(
            context.new_sequence_kind(
              SequenceStringCodePoints(indexed, iterated),
            ),
          )
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
            EvaluationSucceeded(
              context.new_sequence_kind(
                SequenceMapView(values, "MapKeySequence"),
              ),
            )
          }
          "values" => {
            let values : Array[Value] = []
            for entry in context.maps[identifier].entries {
              values.push(entry.value)
            }
            EvaluationSucceeded(
              context.new_sequence_kind(
                SequenceMapView(values, "MapValueSequence"),
              ),
            )
          }
          "type" => EvaluationSucceeded(Value::core_class(MapClass))
          _ => read_sequence_property(receiver, name, span, context)
        }
      }
    SequenceValue(identifier) =>
      if identifier < 0 || identifier >= context.sequences.length() {
        evaluation_error(InvalidOperand, "sequence is not available", span)
      } else if name == "type" {
        EvaluationSucceeded(core_class_for_value(receiver, context))
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
          "type" => EvaluationSucceeded(Value::core_class(MapEntryClass))
          _ =>
            evaluation_error(
              UndefinedMethod,
              "MapEntry does not implement getter '\{name}'",
              span,
            )
        }
      }
    SystemValue =>
      if name == "clock" {
        EvaluationSucceeded(
          Value::number(
            @bench.monotonic_clock_end(context.start_clock) / 1000000.0,
          ),
        )
      } else if name == "name" || name == "toString" {
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
          "\{value.type_name()} does not implement '\{name}'.",
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
    FiberCallResume(_, _, _, span)
    | FiberSequenceResume(_, _, _, _, _, _, _, _, span) =>
      evaluation_error(
        InvalidFiberState,
        "suspended call continuation escaped Fiber execution",
        span,
      )
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
    Variable(name, span) => {
      if environment.has_method_scope() {
        match environment.get_method_local(name) {
          Some(value) => return EvaluationSucceeded(value)
          None => ()
        }
        match environment.get("this") {
          Some(receiver) =>
            if receiver_has_getter(receiver, name, context) {
              return read_property(receiver, name, span, context)
            }
          None => ()
        }
      }
      match environment.get(name) {
        Some(value) => EvaluationSucceeded(value)
        None =>
          evaluation_error(
            UndefinedVariable,
            "undefined variable '\{name}'",
            span,
          )
      }
    }
    Assign(name, value, span) =>
      match evaluate_expression_in(value, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(value) => {
          if environment.has_method_scope() {
            if environment.assign_method_local(name, value) {
              return EvaluationSucceeded(value)
            }
            match environment.get("this") {
              Some(receiver) =>
                if instance_has_method(receiver, name + "=", 1, context) {
                  return invoke_method(
                    receiver,
                    name + "=",
                    [value],
                    span,
                    context,
                  )
                }
              None => ()
            }
          }
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
      }
    FieldGet(name, span) =>
      match environment.get("this") {
        Some(InstanceValue(identifier)) =>
          match environment.get("$class") {
            Some(ClassValue(owner_identifier)) =>
              match
                context.get_instance_field(identifier, owner_identifier, name) {
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
                "instance field '\{name}' has no declaring class",
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
              match environment.get("$class") {
                Some(ClassValue(owner_identifier)) =>
                  if context.set_instance_field(
                      identifier, owner_identifier, name, value,
                    ) {
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
                    "instance field '\{name}' has no declaring class",
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
    PropertySet(receiver, name, expression, span) =>
      match evaluate_expression_in(receiver, environment, context) {
        EvaluationFailed(issue) => EvaluationFailed(issue)
        EvaluationSucceeded(receiver) =>
          match evaluate_expression_in(expression, environment, context) {
            EvaluationFailed(issue) => EvaluationFailed(issue)
            EvaluationSucceeded(value) =>
              invoke_method(receiver, name + "=", [value], span, context)
          }
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
        Some(
          SuperValue(
            superclass,
            instance_identifier,
            method_name,
            is_constructor
          )
        ) =>
          invoke_super_constructor(
            superclass, instance_identifier, method_name, is_constructor, values,
            span, context,
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
        alive: true,
      })
      EvaluationSucceeded(Value::function(identifier))
    }
    Grouping(inner, _) => evaluate_expression_in(inner, environment, context)
    Unary(operator, right, span) =>
      match evaluate_expression_in(right, environment, context) {
        EvaluationSucceeded(value) =>
          evaluate_unary(operator, value, span, context)
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
              evaluate_binary_values(
                IsType,
                left_value,
                right_value,
                span,
                context,
              )
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
    if context.terminate_main {
      return StatementCompleted(Value::null())
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
    StringValue(text) =>
      context.new_sequence(string_items_from_bytes(utf8_bytes(text)))
    RawStringValue(bytes) =>
      context.new_sequence(string_items_from_bytes(bytes))
    value => value
  }
  match iterable {
    RangeValue(_, _, _)
    | ListValue(_)
    | MapValue(_)
    | StringValue(_)
    | RawStringValue(_)
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
  let mut last = Value::null()
  let mut iterator = Value::null()
  while true {
    match invoke_method(iterable, "iterate", [iterator], span, context) {
      EvaluationFailed(issue) => return StatementFailed(issue)
      EvaluationSucceeded(value) if !value.is_truthy() => break
      EvaluationSucceeded(next) => iterator = next
    }
    let item = match
      invoke_method(iterable, "iteratorValue", [iterator], span, context) {
      EvaluationFailed(issue) => return StatementFailed(issue)
      EvaluationSucceeded(value) => value
    }
    environment.push_scope()
    ignore(environment.bind(name, item))
    let result = execute_statement_in(body, environment, context)
    ignore(environment.pop_scope())
    match result {
      StatementCompleted(value) => last = value
      StatementReturned(value, span) => return StatementReturned(value, span)
      StatementBroken(_) => return StatementCompleted(last)
      StatementContinued(_) => ()
      StatementFailed(issue) => return StatementFailed(issue)
    }
  }
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
  if source.length() > context.max_source_characters {
    return ModuleExecutionFailed([
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "module '\{name}' exceeds the source size limit",
        SourceSpan::empty(),
      ).with_source(name),
    ])
  }
  match find_runtime_module(context, name) {
    Some(index) =>
      if context.modules[index].state == 0 {
        return ModuleExecuted(context.modules[index].environment, Value::null())
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
  if context.modules.length() >= context.max_modules {
    return ModuleExecutionFailed([
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "module count limit exceeded",
        SourceSpan::empty(),
      ).with_source(name),
    ])
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
  let resolution_issues = resolve_program(statements)
  if !resolution_issues.is_empty() {
    context.modules[module_index].state = 2
    let issues : Array[Diagnostic] = []
    for diagnostic in resolution_issues {
      issues.push(diagnostic.with_source(name))
    }
    return ModuleExecutionFailed(issues)
  }
  for statement in statements {
    match statement {
      VariableStatement(binding_name, _, _)
      | ClassStatement(binding_name, _, _, _, _, _) =>
        if !environment.has_current(binding_name) {
          ignore(environment.bind(binding_name, Value::null()))
        }
      ImportStatement(_, bindings, _) =>
        for binding in bindings {
          if !environment.has_current(binding.local_name) {
            ignore(environment.bind(binding.local_name, Value::null()))
          }
        }
      _ => ()
    }
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
            if issue.phase == Runtime {
              traced.push(
                issue.with_frame(
                  CallFrame::new("import \"\{specifier}\"", importer, span),
                ),
              )
            } else {
              traced.push(
                Diagnostic::new(
                  Runtime,
                  issue.code,
                  "could not compile module '\{specifier}': \{issue.message}",
                  span,
                ).with_source(importer),
              )
            }
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
  match context.step(statement.span(), environment) {
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
      let value = match initializer {
        None => Value::null()
        Some(expression) =>
          match evaluate_expression_in(expression, environment, context) {
            EvaluationSucceeded(value) => value
            EvaluationFailed(issue) => return StatementFailed(issue)
          }
      }
      if !environment.has_current(name) &&
        !environment.bind(name, Value::null()) {
        return StatementFailed(
          Diagnostic::new(
            Runtime,
            DuplicateVariable,
            "variable '\{name}' is already declared in this scope",
            span,
          ),
        )
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
            if environment.has_current(binding.local_name) {
              ignore(environment.assign(binding.local_name, value))
            } else if !environment.bind(binding.local_name, value) {
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
    ClassStatement(
      name,
      superclass_expression,
      methods,
      class_attributes,
      is_foreign,
      span
    ) => {
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
      if !environment.has_current(name) &&
        !environment.bind(name, Value::null()) {
        return StatementFailed(
          Diagnostic::new(
            Runtime,
            DuplicateVariable,
            "variable '\{name}' is already declared in this scope",
            span,
          ),
        )
      }
      let (superclass, inherits_sequence) = match superclass_expression {
        None => (None, false)
        Some(expression) =>
          match evaluate_expression_in(expression, environment, context) {
            EvaluationFailed(issue) => return StatementFailed(issue)
            EvaluationSucceeded(value) =>
              match value {
                ClassValue(identifier) =>
                  (
                    Some(identifier),
                    context.classes[identifier].inherits_sequence,
                  )
                CoreClassValue(SequenceClass) => (None, true)
                value =>
                  return StatementFailed(
                    Diagnostic::new(
                      Runtime,
                      InvalidSuperclass,
                      "superclass must be a Class, received \{value.type_name()}",
                      span,
                    ),
                  )
              }
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
      for declaration in methods {
        if declaration.is_foreign {
          let signature = method_signature(declaration)
          let mut found = false
          for binding in context.foreign_methods {
            if binding.matches(
                context.current_source,
                name,
                declaration.is_static,
                signature,
              ) {
              found = true
              break
            }
          }
          if !found {
            return StatementFailed(
              Diagnostic::new(
                Runtime,
                ForeignBindingMissing,
                "no foreign binding for \{context.current_source}:\{name}.\{signature}",
                declaration.span,
              ),
            )
          }
        }
      }
      let identifier = context.classes.length()
      let attributes = build_class_attributes(
        class_attributes, methods, context,
      )
      context.classes.push({
        name,
        superclass,
        inherits_sequence,
        methods,
        is_foreign,
        foreign_binding,
        environment: environment.capture(),
        static_fields: [],
        attributes,
        source_name: context.current_source,
        alive: true,
      })
      let value = Value::class_value(identifier)
      ignore(environment.assign(name, value))
      StatementCompleted(value)
    }
  }
}

///|
priv struct ReachabilityMarks {
  closures : Array[Bool]
  classes : Array[Bool]
  instances : Array[Bool]
  lists : Array[Bool]
  maps : Array[Bool]
  map_entries : Array[Bool]
  sequences : Array[Bool]
  iterators : Array[Bool]
  fibers : Array[Bool]
  mut has_opaque_continuation : Bool
}

///|
fn bool_marks(length : Int) -> Array[Bool] {
  let marks : Array[Bool] = []
  for index = 0; index < length; index = index + 1 {
    marks.push(false)
  }
  marks
}

///|
fn ReachabilityMarks::new(context : RuntimeContext) -> ReachabilityMarks {
  {
    closures: bool_marks(context.closures.length()),
    classes: bool_marks(context.classes.length()),
    instances: bool_marks(context.instances.length()),
    lists: bool_marks(context.lists.length()),
    maps: bool_marks(context.maps.length()),
    map_entries: bool_marks(context.map_entries.length()),
    sequences: bool_marks(context.sequences.length()),
    iterators: bool_marks(context.iterators.length()),
    fibers: bool_marks(context.fibers.length()),
    has_opaque_continuation: false,
  }
}

///|
fn mark_environment(
  environment : Environment,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  for value in environment.retained_values() {
    mark_runtime_value(value, context, marks)
  }
}

///|
fn mark_closure(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.closures.length() ||
    marks.closures[identifier] ||
    !context.closures[identifier].alive {
    return
  }
  marks.closures[identifier] = true
  mark_environment(context.closures[identifier].environment, context, marks)
}

///|
fn mark_class(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.classes.length() ||
    marks.classes[identifier] ||
    !context.classes[identifier].alive {
    return
  }
  marks.classes[identifier] = true
  let definition = context.classes[identifier]
  mark_environment(definition.environment, context, marks)
  match definition.superclass {
    Some(superclass) => mark_class(superclass, context, marks)
    None => ()
  }
  for field in definition.static_fields {
    mark_runtime_value(field.value, context, marks)
  }
  mark_runtime_value(definition.attributes, context, marks)
}

///|
fn mark_instance(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.instances.length() ||
    marks.instances[identifier] ||
    !context.instances[identifier].alive {
    return
  }
  marks.instances[identifier] = true
  let instance = context.instances[identifier]
  mark_class(instance.class_identifier, context, marks)
  for field in instance.fields {
    mark_runtime_value(field.value, context, marks)
  }
}

///|
fn mark_list(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.lists.length() ||
    marks.lists[identifier] ||
    !context.lists[identifier].alive {
    return
  }
  marks.lists[identifier] = true
  for value in context.lists[identifier].items {
    mark_runtime_value(value, context, marks)
  }
}

///|
fn mark_map(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.maps.length() ||
    marks.maps[identifier] ||
    !context.maps[identifier].alive {
    return
  }
  marks.maps[identifier] = true
  for entry in context.maps[identifier].entries {
    mark_runtime_value(entry.key, context, marks)
    mark_runtime_value(entry.value, context, marks)
  }
}

///|
fn mark_map_entry(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.map_entries.length() ||
    marks.map_entries[identifier] ||
    !context.map_entries[identifier].alive {
    return
  }
  marks.map_entries[identifier] = true
  let entry = context.map_entries[identifier]
  mark_runtime_value(entry.key, context, marks)
  mark_runtime_value(entry.value, context, marks)
}

///|
fn mark_sequence(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.sequences.length() ||
    marks.sequences[identifier] ||
    !context.sequences[identifier].alive {
    return
  }
  marks.sequences[identifier] = true
  match context.sequences[identifier].kind {
    SequenceSnapshot(values)
    | SequenceMapView(values, _)
    | SequenceStringBytes(values) =>
      for value in values {
        mark_runtime_value(value, context, marks)
      }
    SequenceStringCodePoints(values, offsets) => {
      for value in values {
        mark_runtime_value(value, context, marks)
      }
      for offset in offsets {
        mark_runtime_value(offset, context, marks)
      }
    }
    SequenceMap(source, function_identifier)
    | SequenceWhere(source, function_identifier) => {
      mark_runtime_value(source, context, marks)
      mark_closure(function_identifier, context, marks)
    }
    SequenceSkip(source, _) | SequenceTake(source, _) =>
      mark_runtime_value(source, context, marks)
  }
}

///|
fn mark_iterator(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.iterators.length() ||
    marks.iterators[identifier] ||
    !context.iterators[identifier].alive {
    return
  }
  marks.iterators[identifier] = true
  let iterator = context.iterators[identifier]
  mark_sequence(iterator.sequence_identifier, context, marks)
  mark_runtime_value(iterator.source_iterator, context, marks)
  mark_runtime_value(iterator.current, context, marks)
}

///|
fn mark_fiber(
  identifier : Int,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  if identifier < 0 ||
    identifier >= marks.fibers.length() ||
    marks.fibers[identifier] ||
    !context.fibers[identifier].alive {
    return
  }
  marks.fibers[identifier] = true
  let fiber = context.fibers[identifier]
  mark_closure(fiber.function_identifier, context, marks)
  mark_environment(fiber.environment, context, marks)
  for value in fiber.arguments {
    mark_runtime_value(value, context, marks)
  }
  mark_runtime_value(fiber.last, context, marks)
  mark_runtime_value(fiber.error, context, marks)
  if fiber.pending is Some(_) {
    // MoonBit closures are opaque. Conservatively retain instances while a
    // suspended continuation may still capture local Wren values.
    marks.has_opaque_continuation = true
  }
}

///|
fn mark_runtime_value(
  value : Value,
  context : RuntimeContext,
  marks : ReachabilityMarks,
) -> Unit {
  match value {
    ListValue(identifier) => mark_list(identifier, context, marks)
    MapValue(identifier) => mark_map(identifier, context, marks)
    SequenceValue(identifier) => mark_sequence(identifier, context, marks)
    FunctionValue(identifier) => mark_closure(identifier, context, marks)
    FiberValue(identifier) => mark_fiber(identifier, context, marks)
    ClassValue(identifier) => mark_class(identifier, context, marks)
    ClassAttributesValue(self_identifier, methods_identifier) => {
      mark_map(self_identifier, context, marks)
      mark_map(methods_identifier, context, marks)
    }
    InstanceValue(identifier) => mark_instance(identifier, context, marks)
    SuperValue(class_identifier, instance_identifier, _, _) => {
      mark_class(class_identifier, context, marks)
      mark_instance(instance_identifier, context, marks)
    }
    SuperClassValue(class_identifier, receiver_identifier) => {
      mark_class(class_identifier, context, marks)
      mark_class(receiver_identifier, context, marks)
    }
    IteratorValue(identifier) => mark_iterator(identifier, context, marks)
    MapEntryValue(identifier) => mark_map_entry(identifier, context, marks)
    _ => ()
  }
}

///|
fn finalize_instance(context : RuntimeContext, identifier : Int) -> Bool {
  let instance = context.instances[identifier]
  if instance.finalized {
    return false
  }
  match instance.foreign_handle {
    None => false
    Some(handle) => {
      let class_definition = context.classes[instance.class_identifier]
      match class_definition.foreign_binding {
        Some(binding_identifier) => {
          context.foreign_classes[binding_identifier].finalize(handle)
          instance.finalized = true
          true
        }
        None => false
      }
    }
  }
}

///|
fn collect_runtime_garbage(
  context : RuntimeContext,
  host_roots : Array[Value],
) -> VmGcStats {
  let marks = ReachabilityMarks::new(context)
  for module_value in context.modules {
    if module_value.state != 2 {
      mark_environment(module_value.environment, context, marks)
    }
  }
  if !context.fibers.is_empty() {
    mark_fiber(0, context, marks)
  }
  for root in host_roots {
    mark_runtime_value(root, context, marks)
  }
  if marks.has_opaque_continuation {
    // MoonBit does not expose values captured by continuation closures. Keep
    // every live registry object until all suspended continuations complete.
    for index = 0; index < context.closures.length(); index = index + 1 {
      if context.closures[index].alive {
        marks.closures[index] = true
      }
    }
    for index = 0; index < context.classes.length(); index = index + 1 {
      if context.classes[index].alive {
        marks.classes[index] = true
      }
    }
    for index = 0; index < context.instances.length(); index = index + 1 {
      if context.instances[index].alive {
        marks.instances[index] = true
      }
    }
    for index = 0; index < context.lists.length(); index = index + 1 {
      if context.lists[index].alive {
        marks.lists[index] = true
      }
    }
    for index = 0; index < context.maps.length(); index = index + 1 {
      if context.maps[index].alive {
        marks.maps[index] = true
      }
    }
    for index = 0; index < context.map_entries.length(); index = index + 1 {
      if context.map_entries[index].alive {
        marks.map_entries[index] = true
      }
    }
    for index = 0; index < context.sequences.length(); index = index + 1 {
      if context.sequences[index].alive {
        marks.sequences[index] = true
      }
    }
    for index = 0; index < context.iterators.length(); index = index + 1 {
      if context.iterators[index].alive {
        marks.iterators[index] = true
      }
    }
    for index = 0; index < context.fibers.length(); index = index + 1 {
      if context.fibers[index].alive {
        marks.fibers[index] = true
      }
    }
  }
  let before_objects = context.allocated_objects()
  let mut before = 0
  let mut reachable = 0
  let mut reclaimed = 0
  let mut finalized = 0
  for identifier = 0
      identifier < context.instances.length()
      identifier = identifier + 1 {
    let instance = context.instances[identifier]
    if !instance.alive {
      continue
    }
    before = before + 1
    if marks.instances[identifier] {
      reachable = reachable + 1
    } else {
      if finalize_instance(context, identifier) {
        finalized = finalized + 1
      }
      instance.fields.clear()
      instance.alive = false
      context.free_instances.push(identifier)
      reclaimed = reclaimed + 1
    }
  }
  let mut reclaimed_objects = reclaimed
  for identifier = 0
      identifier < context.closures.length()
      identifier = identifier + 1 {
    if context.closures[identifier].alive && !marks.closures[identifier] {
      context.closures[identifier] = {
        parameters: [],
        body: [],
        environment: Environment::new(),
        source_name: "<collected>",
        alive: false,
      }
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 0
      identifier < context.lists.length()
      identifier = identifier + 1 {
    if context.lists[identifier].alive && !marks.lists[identifier] {
      context.lists[identifier].items.clear()
      context.lists[identifier].alive = false
      context.free_lists.push(identifier)
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 0
      identifier < context.maps.length()
      identifier = identifier + 1 {
    if context.maps[identifier].alive && !marks.maps[identifier] {
      context.maps[identifier].entries.clear()
      context.maps[identifier].alive = false
      context.free_maps.push(identifier)
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 0
      identifier < context.map_entries.length()
      identifier = identifier + 1 {
    if context.map_entries[identifier].alive && !marks.map_entries[identifier] {
      context.map_entries[identifier] = {
        key: Value::null(),
        value: Value::null(),
        alive: false,
      }
      context.free_map_entries.push(identifier)
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 0
      identifier < context.sequences.length()
      identifier = identifier + 1 {
    if context.sequences[identifier].alive && !marks.sequences[identifier] {
      context.sequences[identifier] = {
        kind: SequenceSnapshot([]),
        alive: false,
      }
      context.free_sequences.push(identifier)
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 0
      identifier < context.iterators.length()
      identifier = identifier + 1 {
    if context.iterators[identifier].alive && !marks.iterators[identifier] {
      context.iterators[identifier] = {
        sequence_identifier: -1,
        source_iterator: Value::null(),
        current: Value::null(),
        yielded: 0,
        started: false,
        completed: true,
        alive: false,
      }
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  for identifier = 1
      identifier < context.fibers.length()
      identifier = identifier + 1 {
    if context.fibers[identifier].alive && !marks.fibers[identifier] {
      context.fibers[identifier] = {
        function_identifier: -1,
        arguments: [],
        identity: identifier,
        is_call_frame: false,
        environment: Environment::new(),
        initialized: true,
        state: 2,
        next_statement: 0,
        pending: None,
        last: Value::null(),
        error: Value::null(),
        alive: false,
      }
      context.free_fibers.push(identifier)
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  // Classes are retired last because foreign instance finalizers need their
  // binding metadata during the instance sweep above.
  for identifier = 0
      identifier < context.classes.length()
      identifier = identifier + 1 {
    if context.classes[identifier].alive && !marks.classes[identifier] {
      context.classes[identifier] = {
        name: "<collected>",
        superclass: None,
        inherits_sequence: false,
        methods: [],
        is_foreign: false,
        foreign_binding: None,
        environment: Environment::new(),
        static_fields: [],
        attributes: Value::null(),
        source_name: "<collected>",
        alive: false,
      }
      reclaimed_objects = reclaimed_objects + 1
    }
  }
  {
    before_objects,
    reachable_objects: before_objects - reclaimed_objects,
    reclaimed_objects,
    before_instances: before,
    reachable_instances: reachable,
    reclaimed_instances: reclaimed,
    finalized_foreign_instances: finalized,
  }
}

///|
fn finalize_foreign_instances(context : RuntimeContext) -> Unit {
  for identifier = 0
      identifier < context.instances.length()
      identifier = identifier + 1 {
    let instance = context.instances[identifier]
    if instance.finalized {
      continue
    }
    ignore(finalize_instance(context, identifier))
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
