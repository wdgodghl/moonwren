///|
/// One operation executed by the optional stack-based bytecode backend.
pub(all) enum BytecodeOp {
  PushConstant(Int)
  LoadName(String)
  DefineName(String)
  StoreName(String)
  Duplicate
  Pop
  EnterScope
  ExitScope
  UnaryOp(UnaryOperator)
  BinaryOp(BinaryOperator)
  BuildList(Int)
  BuildMap(Int)
  GetSubscript
  SetSubscript
  GetProperty(String)
  SetProperty(String)
  InvokeMethod(String, Int)
  Jump(Int)
  JumpIfFalse(Int)
  JumpIfFalseKeep(Int)
  JumpIfTrueKeep(Int)
  SetLast
  ReturnValue
  ReturnLast
} derive(Eq, Debug)

///|
pub extend BytecodeOp with Eq::{equal, not_equal}

///|
pub extend BytecodeOp with Debug::{to_repr}

///|
pub(all) struct BytecodeInstruction {
  op : BytecodeOp
  span : SourceSpan
} derive(Eq, Debug)

///|
pub extend BytecodeInstruction with Eq::{equal, not_equal}

///|
pub extend BytecodeInstruction with Debug::{to_repr}

///|
/// Immutable compiled program. The initial backend intentionally covers the
/// procedural expression subset and rejects unsupported object constructs.
pub(all) struct BytecodeProgram {
  constants : Array[Value]
  instructions : Array[BytecodeInstruction]
}

///|
pub(all) enum BytecodeCompileResult {
  BytecodeCompiled(BytecodeProgram)
  BytecodeCompileFailed(Array[Diagnostic])
}

///|
pub(all) enum BytecodeRunResult {
  BytecodeCompleted(Value, Int)
  BytecodeFailed(Diagnostic, Int)
}

///|
/// Dynamic counters collected by the bytecode profiler.
pub(all) struct BytecodeProfile {
  result : BytecodeRunResult
  executed_instructions : Int
  max_stack_depth : Int
  loads : Int
  stores : Int
  branches : Int
  arithmetic_operations : Int
  calls : Int
}

///|
/// One executed instruction captured for debugger frontends.
pub(all) struct BytecodeTraceEvent {
  instruction_pointer : Int
  step : Int
  stack_depth : Int
  instruction : BytecodeInstruction
}

///|
pub(all) struct BytecodeTrace {
  result : BytecodeRunResult
  events : Array[BytecodeTraceEvent]
}

///|
priv struct BytecodeProfiler {
  mut max_stack_depth : Int
  mut loads : Int
  mut stores : Int
  mut branches : Int
  mut arithmetic_operations : Int
  mut calls : Int
  capture_trace : Bool
  events : Array[BytecodeTraceEvent]
}

///|
fn BytecodeProfiler::new(capture_trace : Bool) -> BytecodeProfiler {
  {
    max_stack_depth: 0,
    loads: 0,
    stores: 0,
    branches: 0,
    arithmetic_operations: 0,
    calls: 0,
    capture_trace,
    events: [],
  }
}

///|
fn BytecodeProfiler::observe(
  self : BytecodeProfiler,
  operation : BytecodeOp,
  stack_depth : Int,
  instruction_pointer : Int,
  step : Int,
  instruction : BytecodeInstruction,
) -> Unit {
  if stack_depth > self.max_stack_depth {
    self.max_stack_depth = stack_depth
  }
  match operation {
    LoadName(_) => self.loads = self.loads + 1
    DefineName(_) | StoreName(_) => self.stores = self.stores + 1
    Jump(_) | JumpIfFalse(_) | JumpIfFalseKeep(_) | JumpIfTrueKeep(_) =>
      self.branches = self.branches + 1
    UnaryOp(_) | BinaryOp(_) =>
      self.arithmetic_operations = self.arithmetic_operations + 1
    GetSubscript
    | SetSubscript
    | GetProperty(_)
    | SetProperty(_)
    | InvokeMethod(_, _) => self.calls = self.calls + 1
    _ => ()
  }
  if self.capture_trace {
    self.events.push({ instruction_pointer, step, stack_depth, instruction, })
  }
}

///|
priv struct BytecodeBuilder {
  constants : Array[Value]
  instructions : Array[BytecodeInstruction]
  mut failure : Diagnostic?
}

///|
fn BytecodeBuilder::new() -> BytecodeBuilder {
  { constants: [], instructions: [], failure: None, }
}

///|
fn BytecodeBuilder::emit(
  self : BytecodeBuilder,
  op : BytecodeOp,
  span : SourceSpan,
) -> Int {
  let index = self.instructions.length()
  self.instructions.push({ op, span, })
  index
}

///|
fn BytecodeBuilder::constant(self : BytecodeBuilder, value : Value) -> Int {
  let index = self.constants.length()
  self.constants.push(value)
  index
}

///|
fn BytecodeBuilder::unsupported(
  self : BytecodeBuilder,
  message : String,
  span : SourceSpan,
) -> Unit {
  if self.failure is None {
    self.failure = Some(
      Diagnostic::new(Parse, UnsupportedFeature, message, span).with_source(
        "<bytecode>",
      ),
    )
  }
}

///|
fn BytecodeBuilder::patch_jump(
  self : BytecodeBuilder,
  index : Int,
  target : Int,
) -> Unit {
  let instruction = self.instructions[index]
  let op = match instruction.op {
    Jump(_) => Jump(target)
    JumpIfFalse(_) => JumpIfFalse(target)
    JumpIfFalseKeep(_) => JumpIfFalseKeep(target)
    JumpIfTrueKeep(_) => JumpIfTrueKeep(target)
    other => other
  }
  self.instructions[index] = { op, span: instruction.span, }
}

///|
fn BytecodeBuilder::compile_expression(
  self : BytecodeBuilder,
  expression : Expr,
) -> Unit {
  if self.failure is Some(_) {
    return
  }
  match expression {
    Literal(value, span) =>
      ignore(self.emit(PushConstant(self.constant(value)), span))
    Variable(name, span) => ignore(self.emit(LoadName(name), span))
    Assign(name, value, span) => {
      self.compile_expression(value)
      ignore(self.emit(Duplicate, span))
      ignore(self.emit(StoreName(name), span))
    }
    Grouping(inner, _) => self.compile_expression(inner)
    Unary(operator, value, span) => {
      self.compile_expression(value)
      ignore(self.emit(UnaryOp(operator), span))
    }
    Binary(left, LogicalAnd, right, span) => {
      self.compile_expression(left)
      let skip = self.emit(JumpIfFalseKeep(-1), span)
      ignore(self.emit(Pop, span))
      self.compile_expression(right)
      self.patch_jump(skip, self.instructions.length())
    }
    Binary(left, LogicalOr, right, span) => {
      self.compile_expression(left)
      let skip = self.emit(JumpIfTrueKeep(-1), span)
      ignore(self.emit(Pop, span))
      self.compile_expression(right)
      self.patch_jump(skip, self.instructions.length())
    }
    Binary(left, operator, right, span) => {
      self.compile_expression(left)
      self.compile_expression(right)
      ignore(self.emit(BinaryOp(operator), span))
    }
    Conditional(condition, truthy, falsey, span) => {
      self.compile_expression(condition)
      let false_jump = self.emit(JumpIfFalse(-1), span)
      self.compile_expression(truthy)
      let end_jump = self.emit(Jump(-1), span)
      self.patch_jump(false_jump, self.instructions.length())
      self.compile_expression(falsey)
      self.patch_jump(end_jump, self.instructions.length())
    }
    ListLiteral(items, span) => {
      for item in items {
        self.compile_expression(item)
      }
      ignore(self.emit(BuildList(items.length()), span))
    }
    MapLiteral(entries, span) => {
      for entry in entries {
        self.compile_expression(entry.key)
        self.compile_expression(entry.value)
      }
      ignore(self.emit(BuildMap(entries.length()), span))
    }
    SubscriptGet(receiver, index, span) => {
      self.compile_expression(receiver)
      self.compile_expression(index)
      ignore(self.emit(GetSubscript, span))
    }
    SubscriptSet(receiver, index, value, span) => {
      self.compile_expression(receiver)
      self.compile_expression(index)
      self.compile_expression(value)
      ignore(self.emit(SetSubscript, span))
    }
    PropertyGet(receiver, name, span) => {
      self.compile_expression(receiver)
      ignore(self.emit(GetProperty(name), span))
    }
    PropertySet(receiver, name, value, span) => {
      self.compile_expression(receiver)
      self.compile_expression(value)
      ignore(self.emit(SetProperty(name), span))
    }
    MethodCall(receiver, name, arguments, span) => {
      self.compile_expression(receiver)
      for argument in arguments {
        self.compile_expression(argument)
      }
      ignore(self.emit(InvokeMethod(name, arguments.length()), span))
    }
    FieldGet(_, span)
    | FieldAssign(_, _, span)
    | StaticFieldGet(_, span)
    | StaticFieldAssign(_, _, span)
    | SuperConstructorCall(_, span)
    | FunctionLiteral(_, _, span)
    | FiberCallResume(_, _, _, span)
    | FiberSequenceResume(_, _, _, _, _, _, _, _, span) =>
      self.unsupported(
        "expression is not supported by the bytecode backend", span,
      )
  }
}

///|
fn BytecodeBuilder::compile_statement(
  self : BytecodeBuilder,
  statement : Stmt,
) -> Unit {
  if self.failure is Some(_) {
    return
  }
  match statement {
    ExpressionStatement(expression, span) => {
      self.compile_expression(expression)
      ignore(self.emit(SetLast, span))
    }
    VariableStatement(name, initializer, span) => {
      match initializer {
        Some(expression) => self.compile_expression(expression)
        None =>
          ignore(self.emit(PushConstant(self.constant(Value::null())), span))
      }
      ignore(self.emit(Duplicate, span))
      ignore(self.emit(DefineName(name), span))
      ignore(self.emit(SetLast, span))
    }
    BlockStatement(statements, span) => {
      ignore(self.emit(EnterScope, span))
      for child in statements {
        self.compile_statement(child)
      }
      ignore(self.emit(ExitScope, span))
    }
    IfStatement(condition, then_branch, else_branch, span) => {
      self.compile_expression(condition)
      let false_jump = self.emit(JumpIfFalse(-1), span)
      self.compile_statement(then_branch)
      let end_jump = self.emit(Jump(-1), span)
      self.patch_jump(false_jump, self.instructions.length())
      match else_branch {
        Some(branch) => self.compile_statement(branch)
        None => ()
      }
      self.patch_jump(end_jump, self.instructions.length())
    }
    WhileStatement(condition, body, span) => {
      let start = self.instructions.length()
      self.compile_expression(condition)
      let end_jump = self.emit(JumpIfFalse(-1), span)
      self.compile_statement(body)
      ignore(self.emit(Jump(start), span))
      self.patch_jump(end_jump, self.instructions.length())
    }
    ReturnStatement(value, span) => {
      match value {
        Some(expression) => self.compile_expression(expression)
        None =>
          ignore(self.emit(PushConstant(self.constant(Value::null())), span))
      }
      ignore(self.emit(ReturnValue, span))
    }
    ForStatement(_, _, _, span)
    | BreakStatement(span)
    | ContinueStatement(span)
    | ImportStatement(_, _, span)
    | ClassStatement(_, _, _, _, _, span) =>
      self.unsupported(
        "statement is not supported by the bytecode backend", span,
      )
  }
}

///|
/// Compile the arithmetic/control-flow subset to portable stack bytecode.
/// Unsupported constructs fail explicitly and can continue to use `run`.
pub fn compile_bytecode(source : String) -> BytecodeCompileResult {
  match parse_program(source) {
    ProgramParseFailed(issues) => BytecodeCompileFailed(issues)
    ProgramParsed(statements) => {
      let builder = BytecodeBuilder::new()
      for statement in statements {
        builder.compile_statement(statement)
      }
      match builder.failure {
        Some(issue) => BytecodeCompileFailed([issue])
        None => {
          ignore(
            builder.emit(
              ReturnLast,
              if statements.is_empty() {
                SourceSpan::empty()
              } else {
                statements[statements.length() - 1].span()
              },
            ),
          )
          BytecodeCompiled({
            constants: builder.constants,
            instructions: builder.instructions,
          })
        }
      }
    }
  }
}

///|
fn bytecode_failure(
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
  steps : Int,
) -> BytecodeRunResult {
  BytecodeFailed(
    Diagnostic::new(Runtime, code, message, span).with_source("<bytecode>"),
    steps,
  )
}

///|
fn pop_bytecode_value(
  stack : Array[Value],
  span : SourceSpan,
  steps : Int,
) -> (Value?, BytecodeRunResult?) {
  match stack.pop() {
    Some(value) => (Some(value), None)
    None =>
      (
        None,
        Some(
          bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow",
            span,
            steps,
          ),
        ),
      )
  }
}

///|
/// Execute compiled bytecode with a deterministic instruction budget.
fn execute_bytecode(
  program : BytecodeProgram,
  max_steps : Int,
  profiler : BytecodeProfiler?,
) -> BytecodeRunResult {
  if max_steps <= 0 {
    return bytecode_failure(
      ExecutionLimit,
      "bytecode step limit must be positive",
      SourceSpan::empty(),
      0,
    )
  }
  let environment = Environment::new()
  bind_core_globals(environment)
  let context = RuntimeContext::new(max_steps)
  let stack : Array[Value] = []
  let mut last = Value::null()
  let mut ip = 0
  let mut steps = 0
  while ip >= 0 && ip < program.instructions.length() {
    let instruction = program.instructions[ip]
    match profiler {
      Some(value) =>
        value.observe(
          instruction.op,
          stack.length(),
          ip,
          steps + 1,
          instruction,
        )
      None => ()
    }
    steps = steps + 1
    if steps > max_steps {
      return bytecode_failure(
        ExecutionLimit,
        "bytecode execution step limit exceeded",
        instruction.span,
        steps,
      )
    }
    ip = ip + 1
    match instruction.op {
      PushConstant(index) =>
        if index < 0 || index >= program.constants.length() {
          return bytecode_failure(
            InvalidIndex,
            "invalid bytecode constant index",
            instruction.span,
            steps,
          )
        } else {
          stack.push(program.constants[index])
        }
      LoadName(name) =>
        match environment.get(name) {
          Some(value) => stack.push(value)
          None =>
            return bytecode_failure(
              UndefinedVariable,
              "undefined variable '\{name}'",
              instruction.span,
              steps,
            )
        }
      DefineName(name) => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => ()
        }
        if !environment.bind(name, value.unwrap()) {
          return bytecode_failure(
            DuplicateVariable,
            "variable '\{name}' is already declared in this scope",
            instruction.span,
            steps,
          )
        }
      }
      StoreName(name) => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => ()
        }
        if !environment.assign(name, value.unwrap()) {
          return bytecode_failure(
            UndefinedVariable,
            "undefined variable '\{name}'",
            instruction.span,
            steps,
          )
        }
      }
      Duplicate =>
        if stack.is_empty() {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow",
            instruction.span,
            steps,
          )
        } else {
          stack.push(stack[stack.length() - 1])
        }
      Pop => ignore(stack.pop())
      EnterScope => environment.push_scope()
      ExitScope => ignore(environment.pop_scope())
      UnaryOp(operator) => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => ()
        }
        match
          evaluate_unary(operator, value.unwrap(), instruction.span, context) {
          EvaluationSucceeded(result) => stack.push(result)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      BinaryOp(operator) => {
        let (right, right_failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match right_failure {
          Some(result) => return result
          None => ()
        }
        let (left, left_failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match left_failure {
          Some(result) => return result
          None => ()
        }
        match
          evaluate_binary_values(
            operator,
            left.unwrap(),
            right.unwrap(),
            instruction.span,
            context,
          ) {
          EvaluationSucceeded(result) => stack.push(result)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      BuildList(count) => {
        if count < 0 || stack.length() < count {
          return bytecode_failure(
            InvalidOperand,
            "invalid bytecode list item count",
            instruction.span,
            steps,
          )
        }
        let reversed : Array[Value] = []
        for item_index = 0; item_index < count; item_index = item_index + 1 {
          reversed.push(stack.pop().unwrap())
        }
        let items : Array[Value] = []
        let mut index = reversed.length() - 1
        while index >= 0 {
          items.push(reversed[index])
          index = index - 1
        }
        stack.push(context.new_list(items))
      }
      BuildMap(count) => {
        if count < 0 || stack.length() < count * 2 {
          return bytecode_failure(
            InvalidOperand,
            "invalid bytecode map entry count",
            instruction.span,
            steps,
          )
        }
        let keys : Array[Value] = []
        let values : Array[Value] = []
        for entry_index = 0; entry_index < count; entry_index = entry_index + 1 {
          values.push(stack.pop().unwrap())
          keys.push(stack.pop().unwrap())
        }
        let map = context.new_map()
        let identifier = match map {
          MapValue(value) => value
          _ => -1
        }
        let mut index = count - 1
        while index >= 0 {
          if !is_valid_map_key(keys[index]) {
            return BytecodeFailed(
              Diagnostic::new(
                Runtime,
                InvalidMapKey,
                "Map keys must be immutable values, received \{keys[index].type_name()}",
                instruction.span,
              ).with_source("<bytecode>"),
              steps,
            )
          }
          ignore(context.set_map_entry(identifier, keys[index], values[index]))
          index = index - 1
        }
        stack.push(map)
      }
      GetSubscript => {
        if stack.length() < 2 {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow while reading subscript",
            instruction.span,
            steps,
          )
        }
        let index = stack.pop().unwrap()
        let receiver = stack.pop().unwrap()
        match read_subscript(receiver, index, instruction.span, context) {
          EvaluationSucceeded(value) => stack.push(value)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      SetSubscript => {
        if stack.length() < 3 {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow while writing subscript",
            instruction.span,
            steps,
          )
        }
        let value = stack.pop().unwrap()
        let index = stack.pop().unwrap()
        let receiver = stack.pop().unwrap()
        match
          write_subscript(receiver, index, value, instruction.span, context) {
          EvaluationSucceeded(result) => stack.push(result)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      GetProperty(name) => {
        if stack.is_empty() {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow while reading property",
            instruction.span,
            steps,
          )
        }
        let receiver = stack.pop().unwrap()
        match read_property(receiver, name, instruction.span, context) {
          EvaluationSucceeded(value) => stack.push(value)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      SetProperty(name) => {
        if stack.length() < 2 {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow while writing property",
            instruction.span,
            steps,
          )
        }
        let value = stack.pop().unwrap()
        let receiver = stack.pop().unwrap()
        match
          invoke_method(
            receiver,
            name + "=",
            [value],
            instruction.span,
            context,
          ) {
          EvaluationSucceeded(result) => stack.push(result)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      InvokeMethod(name, arity) => {
        if arity < 0 || stack.length() < arity + 1 {
          return bytecode_failure(
            InvalidOperand,
            "invalid bytecode method arity",
            instruction.span,
            steps,
          )
        }
        let reversed : Array[Value] = []
        for argument_index = 0
            argument_index < arity
            argument_index = argument_index + 1 {
          reversed.push(stack.pop().unwrap())
        }
        let arguments : Array[Value] = []
        let mut index = reversed.length() - 1
        while index >= 0 {
          arguments.push(reversed[index])
          index = index - 1
        }
        let receiver = stack.pop().unwrap()
        match
          invoke_method(receiver, name, arguments, instruction.span, context) {
          EvaluationSucceeded(value) => stack.push(value)
          EvaluationFailed(issue) => return BytecodeFailed(issue, steps)
        }
      }
      Jump(target) => ip = target
      JumpIfFalse(target) => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => ()
        }
        if !value.unwrap().is_truthy() {
          ip = target
        }
      }
      JumpIfFalseKeep(target) =>
        if stack.is_empty() {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow",
            instruction.span,
            steps,
          )
        } else if !stack[stack.length() - 1].is_truthy() {
          ip = target
        }
      JumpIfTrueKeep(target) =>
        if stack.is_empty() {
          return bytecode_failure(
            InvalidOperand,
            "bytecode stack underflow",
            instruction.span,
            steps,
          )
        } else if stack[stack.length() - 1].is_truthy() {
          ip = target
        }
      SetLast => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => last = value.unwrap()
        }
      }
      ReturnValue => {
        let (value, failure) = pop_bytecode_value(
          stack,
          instruction.span,
          steps,
        )
        match failure {
          Some(result) => return result
          None => return BytecodeCompleted(value.unwrap(), steps)
        }
      }
      ReturnLast => return BytecodeCompleted(last, steps)
    }
  }
  BytecodeCompleted(last, steps)
}

///|
/// Execute compiled bytecode with a deterministic instruction budget.
pub fn run_bytecode(
  program : BytecodeProgram,
  max_steps : Int,
) -> BytecodeRunResult {
  execute_bytecode(program, max_steps, None)
}

///|
/// Execute bytecode and return dynamic instruction, stack, branch and
/// variable-access counters for profiling and regression analysis.
pub fn profile_bytecode(
  program : BytecodeProgram,
  max_steps : Int,
) -> BytecodeProfile {
  let profiler = BytecodeProfiler::new(false)
  let result = execute_bytecode(program, max_steps, Some(profiler))
  let executed_instructions = match result {
    BytecodeCompleted(_, steps) | BytecodeFailed(_, steps) => steps
  }
  {
    result,
    executed_instructions,
    max_stack_depth: profiler.max_stack_depth,
    loads: profiler.loads,
    stores: profiler.stores,
    branches: profiler.branches,
    arithmetic_operations: profiler.arithmetic_operations,
    calls: profiler.calls,
  }
}

///|
/// Execute while capturing an instruction-by-instruction trace. Source-level
/// debugger UIs can filter events by `instruction.span.line()` for breakpoints.
pub fn trace_bytecode(
  program : BytecodeProgram,
  max_steps : Int,
) -> BytecodeTrace {
  let profiler = BytecodeProfiler::new(true)
  let result = execute_bytecode(program, max_steps, Some(profiler))
  { result, events: profiler.events, }
}

///|
/// Render bytecode with instruction offsets and source positions. This is the
/// stable inspection surface used by debuggers and teaching tools.
pub fn disassemble_bytecode(program : BytecodeProgram) -> Array[String] {
  let lines : Array[String] = []
  for index = 0; index < program.instructions.length(); index = index + 1 {
    let instruction = program.instructions[index]
    lines.push(
      "\{index}  \{instruction.span.line()}:\{instruction.span.column()}  " +
      "\{Repr(instruction.op)}",
    )
  }
  lines
}

///|
/// Compile and execute source through the optional bytecode backend.
pub fn run_compiled(source : String, max_steps : Int) -> BytecodeRunResult {
  match compile_bytecode(source) {
    BytecodeCompiled(program) => run_bytecode(program, max_steps)
    BytecodeCompileFailed(issues) => BytecodeFailed(issues[0], 0)
  }
}
