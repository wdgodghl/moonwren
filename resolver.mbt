///|
/// Compile-time semantic analysis for bindings and context-sensitive syntax.
priv struct Resolver {
  diagnostics : Array[Diagnostic]
  scopes : Array[Array[String]]
  globals : Array[String]
  forward_references : Array[String]
  mut function_depth : Int
  mut loop_depth : Int
  mut class_depth : Int
  mut in_static_method : Bool
  mut in_constructor : Bool
  mut in_foreign_class : Bool
  mut local_count : Int
}

///|
fn string_array_contains(values : Array[String], name : String) -> Bool {
  for value in values {
    if value == name {
      return true
    }
  }
  false
}

///|
fn Resolver::new(statements : Array[Stmt]) -> Resolver {
  let globals = [
    "System", "Object", "Bool", "Class", "Fiber", "Fn", "List", "Map", "MapEntry",
    "MapKeySequence", "MapValueSequence", "Null", "Num", "Range", "Sequence", "String",
    "StringByteSequence", "StringCodePointSequence",
  ]
  for statement in statements {
    match statement {
      VariableStatement(name, _, _) | ClassStatement(name, _, _, _, _, _) =>
        if !string_array_contains(globals, name) {
          globals.push(name)
        }
      ImportStatement(_, bindings, _) =>
        for binding in bindings {
          if !string_array_contains(globals, binding.local_name) {
            globals.push(binding.local_name)
          }
        }
      _ => ()
    }
  }
  {
    diagnostics: [],
    scopes: [[]],
    globals,
    forward_references: [],
    function_depth: 0,
    loop_depth: 0,
    class_depth: 0,
    in_static_method: false,
    in_constructor: false,
    in_foreign_class: false,
    local_count: 0,
  }
}

///|
fn Resolver::report(
  self : Resolver,
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
) -> Unit {
  self.diagnostics.push(Diagnostic::new(Resolve, code, message, span))
}

///|
fn Resolver::push_scope(self : Resolver) -> Unit {
  self.scopes.push([])
}

///|
fn Resolver::pop_scope(self : Resolver) -> Unit {
  ignore(self.scopes.pop())
}

///|
fn Resolver::is_declared(self : Resolver, name : String) -> Bool {
  let mut index = self.scopes.length() - 1
  while index >= 0 {
    if string_array_contains(self.scopes[index], name) {
      return true
    }
    index = index - 1
  }
  false
}

///|
fn Resolver::define_name(
  self : Resolver,
  name : String,
  span : SourceSpan,
) -> Unit {
  if string_array_contains(self.forward_references, name) {
    self.report(
      UndefinedVariable,
      "variable '\{name}' is referenced before its definition",
      span,
    )
  }
  let scope = self.scopes[self.scopes.length() - 1]
  if string_array_contains(scope, name) {
    self.report(
      DuplicateVariable,
      "variable '\{name}' is already declared in this scope",
      span,
    )
    return
  }
  scope.push(name)
  if self.scopes.length() > 1 {
    self.local_count = self.local_count + 1
    if self.local_count > 255 {
      self.report(
        InvalidOperand,
        "a function may not contain more than 256 local variables",
        span,
      )
    }
  }
}

///|
fn starts_with_uppercase(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let code = name.unsafe_get(0).to_int()
  code >= 65 && code <= 90
}

///|
fn Resolver::resolve_variable(
  self : Resolver,
  name : String,
  span : SourceSpan,
) -> Unit {
  if name == "this" {
    if self.class_depth == 0 {
      self.report(
        UndefinedVariable,
        "'this' cannot be used outside a class",
        span,
      )
    }
    return
  }
  if name == "$super" {
    if self.class_depth == 0 {
      self.report(
        UndefinedVariable,
        "'super' cannot be used outside a class",
        span,
      )
    }
    return
  }
  if self.is_declared(name) {
    return
  }
  if string_array_contains(self.globals, name) {
    if self.function_depth == 0 && !starts_with_uppercase(name) {
      if !string_array_contains(self.forward_references, name) {
        self.forward_references.push(name)
      }
    }
    return
  }
  if self.class_depth > 0 {
    return
  }
  self.report(UndefinedVariable, "undefined variable '\{name}'", span)
}

///|
fn Resolver::resolve_function(
  self : Resolver,
  parameters : Array[String],
  body : Array[Stmt],
  span : SourceSpan,
) -> Unit {
  if parameters.length() > 16 {
    self.report(
      InvalidArity,
      "a function may not have more than 16 parameters",
      span,
    )
  }
  let saved_function_depth = self.function_depth
  let saved_loop_depth = self.loop_depth
  let saved_local_count = self.local_count
  let saved_constructor = self.in_constructor
  self.function_depth = self.function_depth + 1
  self.loop_depth = 0
  self.local_count = 0
  self.in_constructor = false
  self.push_scope()
  for parameter in parameters {
    self.define_name(parameter, span)
  }
  for statement in body {
    self.resolve_statement(statement)
  }
  self.pop_scope()
  self.function_depth = saved_function_depth
  self.loop_depth = saved_loop_depth
  self.local_count = saved_local_count
  self.in_constructor = saved_constructor
}

///|
fn Resolver::resolve_expression(self : Resolver, expression : Expr) -> Unit {
  match expression {
    Literal(_, _) => ()
    Variable(name, span) => self.resolve_variable(name, span)
    Assign(name, value, span) => {
      self.resolve_expression(value)
      if !self.is_declared(name) &&
        !string_array_contains(self.globals, name) &&
        self.class_depth == 0 {
        self.report(UndefinedVariable, "undefined variable '\{name}'", span)
      }
    }
    FieldGet(_, span) | FieldAssign(_, _, span) => {
      if self.class_depth == 0 {
        self.report(
          UndefinedVariable,
          "instance fields may only be used inside a class",
          span,
        )
      } else if self.in_static_method {
        self.report(
          UndefinedVariable,
          "instance fields cannot be used in a static method",
          span,
        )
      } else if self.in_foreign_class {
        self.report(
          UndefinedVariable,
          "foreign classes cannot declare instance fields",
          span,
        )
      }
      match expression {
        FieldAssign(_, value, _) => self.resolve_expression(value)
        _ => ()
      }
    }
    StaticFieldGet(_, span) | StaticFieldAssign(_, _, span) => {
      if self.class_depth == 0 {
        self.report(
          UndefinedVariable,
          "static fields may only be used inside a class",
          span,
        )
      }
      match expression {
        StaticFieldAssign(_, value, _) => self.resolve_expression(value)
        _ => ()
      }
    }
    ListLiteral(items, _) =>
      for item in items {
        self.resolve_expression(item)
      }
    MapLiteral(entries, _) =>
      for entry in entries {
        self.resolve_expression(entry.key)
        self.resolve_expression(entry.value)
      }
    SubscriptGet(receiver, index, _) => {
      self.resolve_expression(receiver)
      self.resolve_expression(index)
    }
    SubscriptSet(receiver, index, value, _) => {
      self.resolve_expression(receiver)
      self.resolve_expression(index)
      self.resolve_expression(value)
    }
    PropertyGet(receiver, name, span) => {
      self.resolve_expression(receiver)
      if name.length() > 64 {
        self.report(
          InvalidOperand,
          "method names may not be longer than 64 characters",
          span,
        )
      }
    }
    PropertySet(receiver, _, value, _) => {
      self.resolve_expression(receiver)
      self.resolve_expression(value)
    }
    MethodCall(receiver, name, arguments, span) => {
      self.resolve_expression(receiver)
      if name.length() > 64 {
        self.report(
          InvalidOperand,
          "method names may not be longer than 64 characters",
          span,
        )
      }
      if arguments.length() > 16 {
        self.report(
          InvalidArity,
          "a call may not have more than 16 arguments",
          span,
        )
      }
      for argument in arguments {
        self.resolve_expression(argument)
      }
    }
    SuperConstructorCall(arguments, span) => {
      if self.class_depth == 0 {
        self.report(
          UndefinedVariable,
          "'super' cannot be used outside a class",
          span,
        )
      }
      for argument in arguments {
        self.resolve_expression(argument)
      }
    }
    FunctionLiteral(parameters, body, span) =>
      self.resolve_function(parameters, body, span)
    FiberCallResume(_, _, _, _)
    | FiberSequenceResume(_, _, _, _, _, _, _, _, _) => ()
    Unary(_, value, _) | Grouping(value, _) => self.resolve_expression(value)
    Binary(left, _, right, _) => {
      self.resolve_expression(left)
      self.resolve_expression(right)
    }
    Conditional(condition, then_branch, else_branch, _) => {
      self.resolve_expression(condition)
      self.resolve_expression(then_branch)
      self.resolve_expression(else_branch)
    }
  }
}

///|
fn Resolver::resolve_method(self : Resolver, declaration : MethodDecl) -> Unit {
  if declaration.name.length() > 64 {
    self.report(
      InvalidOperand,
      "method names may not be longer than 64 characters",
      declaration.span,
    )
  }
  if declaration.parameters.length() > 16 {
    self.report(
      InvalidArity,
      "a method may not have more than 16 parameters",
      declaration.span,
    )
  }
  let saved_function_depth = self.function_depth
  let saved_loop_depth = self.loop_depth
  let saved_static = self.in_static_method
  let saved_constructor = self.in_constructor
  let saved_local_count = self.local_count
  self.function_depth = self.function_depth + 1
  self.loop_depth = 0
  self.in_static_method = declaration.is_static
  self.in_constructor = declaration.is_constructor
  self.local_count = 0
  self.push_scope()
  for parameter in declaration.parameters {
    self.define_name(parameter, declaration.span)
  }
  for statement in declaration.body {
    self.resolve_statement(statement)
  }
  self.pop_scope()
  self.function_depth = saved_function_depth
  self.loop_depth = saved_loop_depth
  self.in_static_method = saved_static
  self.in_constructor = saved_constructor
  self.local_count = saved_local_count
}

///|
fn Resolver::resolve_statement(self : Resolver, statement : Stmt) -> Unit {
  match statement {
    ExpressionStatement(expression, _) => self.resolve_expression(expression)
    VariableStatement(name, initializer, span) => {
      match initializer {
        Some(expression) => self.resolve_expression(expression)
        None => ()
      }
      self.define_name(name, span)
    }
    BlockStatement(statements, _) => {
      let saved_local_count = self.local_count
      self.push_scope()
      for child in statements {
        self.resolve_statement(child)
      }
      self.pop_scope()
      self.local_count = saved_local_count
    }
    IfStatement(condition, then_branch, else_branch, _) => {
      self.resolve_expression(condition)
      self.resolve_statement(then_branch)
      match else_branch {
        Some(branch) => self.resolve_statement(branch)
        None => ()
      }
    }
    WhileStatement(condition, body, _) => {
      self.resolve_expression(condition)
      self.loop_depth = self.loop_depth + 1
      self.resolve_statement(body)
      self.loop_depth = self.loop_depth - 1
    }
    ForStatement(name, sequence, body, span) => {
      self.resolve_expression(sequence)
      let saved_local_count = self.local_count
      self.push_scope()
      self.define_name(name, span)
      self.loop_depth = self.loop_depth + 1
      self.resolve_statement(body)
      self.loop_depth = self.loop_depth - 1
      self.pop_scope()
      self.local_count = saved_local_count
    }
    ReturnStatement(value, span) => {
      if self.function_depth == 0 {
        self.report(
          ReturnOutsideFunction,
          "return can only be used inside a function or method",
          span,
        )
      } else if self.in_constructor {
        match value {
          Some(_) =>
            self.report(
              ReturnOutsideFunction,
              "a constructor cannot return a value",
              span,
            )
          None => ()
        }
      }
      match value {
        Some(expression) => self.resolve_expression(expression)
        None => ()
      }
    }
    BreakStatement(span) =>
      if self.loop_depth == 0 {
        self.report(
          BreakOutsideLoop,
          "break can only be used inside a loop",
          span,
        )
      }
    ContinueStatement(span) =>
      if self.loop_depth == 0 {
        self.report(
          ContinueOutsideLoop,
          "continue can only be used inside a loop",
          span,
        )
      }
    ImportStatement(_, bindings, span) =>
      for binding in bindings {
        self.define_name(binding.local_name, span)
      }
    ClassStatement(name, superclass, methods, _, is_foreign, span) => {
      match superclass {
        Some(expression) => self.resolve_expression(expression)
        None => ()
      }
      self.define_name(name, span)
      for left_index = 0
          left_index < methods.length()
          left_index = left_index + 1 {
        for right_index = left_index + 1
            right_index < methods.length()
            right_index = right_index + 1 {
          let left = methods[left_index]
          let right = methods[right_index]
          if left.name == right.name &&
            left.parameters.length() == right.parameters.length() &&
            left.is_constructor == right.is_constructor &&
            left.is_getter == right.is_getter &&
            left.is_static == right.is_static {
            self.report(
              DuplicateMethod,
              "duplicate method '\{right.name}'",
              right.span,
            )
          }
        }
      }
      self.class_depth = self.class_depth + 1
      let saved_foreign_class = self.in_foreign_class
      self.in_foreign_class = is_foreign
      for declaration in methods {
        self.resolve_method(declaration)
      }
      self.in_foreign_class = saved_foreign_class
      self.class_depth = self.class_depth - 1
    }
  }
}

///|
fn resolve_program(statements : Array[Stmt]) -> Array[Diagnostic] {
  let resolver = Resolver::new(statements)
  for statement in statements {
    resolver.resolve_statement(statement)
  }
  resolver.diagnostics
}
