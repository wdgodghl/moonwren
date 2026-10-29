///|
pub(all) enum LanguageSymbolKind {
  SymbolVariable
  SymbolClass
  SymbolMethod
  SymbolParameter
  SymbolImport
} derive(Eq, Debug)

///|
pub extend LanguageSymbolKind with Eq::{equal, not_equal}

///|
pub extend LanguageSymbolKind with Debug::{to_repr}

///|
pub(all) struct LanguageSymbol {
  name : String
  kind : LanguageSymbolKind
  span : SourceSpan
  container : String?
} derive(Eq, Debug)

///|
pub extend LanguageSymbol with Eq::{equal, not_equal}

///|
pub extend LanguageSymbol with Debug::{to_repr}

///|
pub(all) struct LanguageLocation {
  source_name : String
  span : SourceSpan
} derive(Eq, Debug)

///|
pub extend LanguageLocation with Eq::{equal, not_equal}

///|
pub extend LanguageLocation with Debug::{to_repr}

///|
pub(all) struct LanguageTextEdit {
  source_name : String
  span : SourceSpan
  replacement : String
} derive(Eq, Debug)

///|
pub extend LanguageTextEdit with Eq::{equal, not_equal}

///|
pub extend LanguageTextEdit with Debug::{to_repr}

///|
pub(all) struct LanguageHover {
  title : String
  detail : String
  span : SourceSpan
} derive(Eq, Debug)

///|
pub extend LanguageHover with Eq::{equal, not_equal}

///|
pub extend LanguageHover with Debug::{to_repr}

///|
/// Parsed editor document used by the reusable LSP service core.
pub(all) struct LanguageDocument {
  source_name : String
  source : String
  tokens : Array[Token]
  statements : Array[Stmt]
  diagnostics : Array[Diagnostic]
  symbols : Array[LanguageSymbol]
}

///|
fn span_contains_offset(span : SourceSpan, offset : Int) -> Bool {
  offset >= span.start.offset && offset < span.end.offset
}

///|
fn symbol_kind_text(kind : LanguageSymbolKind) -> String {
  match kind {
    SymbolVariable => "variable"
    SymbolClass => "class"
    SymbolMethod => "method"
    SymbolParameter => "parameter"
    SymbolImport => "import"
  }
}

///|
fn find_name_span(
  tokens : Array[Token],
  name : String,
  within : SourceSpan,
) -> SourceSpan {
  for token in tokens {
    if token.kind == Identifier &&
      token.lexeme == name &&
      token.span.start.offset >= within.start.offset &&
      token.span.end.offset <= within.end.offset {
      return token.span
    }
  }
  within
}

///|
fn push_language_symbol(
  symbols : Array[LanguageSymbol],
  tokens : Array[Token],
  name : String,
  kind : LanguageSymbolKind,
  within : SourceSpan,
  container : String?,
) -> Unit {
  symbols.push({
    name,
    kind,
    span: find_name_span(tokens, name, within),
    container,
  })
}

///|
fn collect_expression_symbols(
  expression : Expr,
  tokens : Array[Token],
  symbols : Array[LanguageSymbol],
  container : String?,
) -> Unit {
  match expression {
    FunctionLiteral(parameters, body, span) => {
      for parameter in parameters {
        push_language_symbol(
          symbols,
          tokens,
          parameter,
          SymbolParameter,
          span,
          container,
        )
      }
      for statement in body {
        collect_statement_symbols(statement, tokens, symbols, container)
      }
    }
    ListLiteral(items, _) =>
      for item in items {
        collect_expression_symbols(item, tokens, symbols, container)
      }
    MapLiteral(entries, _) =>
      for entry in entries {
        collect_expression_symbols(entry.key, tokens, symbols, container)
        collect_expression_symbols(entry.value, tokens, symbols, container)
      }
    SubscriptGet(receiver, index, _) => {
      collect_expression_symbols(receiver, tokens, symbols, container)
      collect_expression_symbols(index, tokens, symbols, container)
    }
    SubscriptSet(receiver, index, value, _) => {
      collect_expression_symbols(receiver, tokens, symbols, container)
      collect_expression_symbols(index, tokens, symbols, container)
      collect_expression_symbols(value, tokens, symbols, container)
    }
    PropertyGet(receiver, _, _) =>
      collect_expression_symbols(receiver, tokens, symbols, container)
    PropertySet(receiver, _, value, _) => {
      collect_expression_symbols(receiver, tokens, symbols, container)
      collect_expression_symbols(value, tokens, symbols, container)
    }
    MethodCall(receiver, _, arguments, _) => {
      collect_expression_symbols(receiver, tokens, symbols, container)
      for argument in arguments {
        collect_expression_symbols(argument, tokens, symbols, container)
      }
    }
    Assign(_, value, _)
    | FieldAssign(_, value, _)
    | StaticFieldAssign(_, value, _)
    | Unary(_, value, _)
    | Grouping(value, _) =>
      collect_expression_symbols(value, tokens, symbols, container)
    Binary(left, _, right, _) => {
      collect_expression_symbols(left, tokens, symbols, container)
      collect_expression_symbols(right, tokens, symbols, container)
    }
    Conditional(condition, yes, no, _) => {
      collect_expression_symbols(condition, tokens, symbols, container)
      collect_expression_symbols(yes, tokens, symbols, container)
      collect_expression_symbols(no, tokens, symbols, container)
    }
    SuperConstructorCall(arguments, _) =>
      for argument in arguments {
        collect_expression_symbols(argument, tokens, symbols, container)
      }
    Literal(_, _)
    | Variable(_, _)
    | FieldGet(_, _)
    | StaticFieldGet(_, _)
    | FiberCallResume(_, _, _, _)
    | FiberSequenceResume(_, _, _, _, _, _, _, _, _) => ()
  }
}

///|
fn collect_statement_symbols(
  statement : Stmt,
  tokens : Array[Token],
  symbols : Array[LanguageSymbol],
  container : String?,
) -> Unit {
  match statement {
    VariableStatement(name, initializer, span) => {
      push_language_symbol(
        symbols,
        tokens,
        name,
        SymbolVariable,
        span,
        container,
      )
      match initializer {
        Some(value) =>
          collect_expression_symbols(value, tokens, symbols, container)
        None => ()
      }
    }
    ClassStatement(name, superclass, methods, _, _, span) => {
      push_language_symbol(symbols, tokens, name, SymbolClass, span, container)
      match superclass {
        Some(value) =>
          collect_expression_symbols(value, tokens, symbols, container)
        None => ()
      }
      for declaration in methods {
        push_language_symbol(
          symbols,
          tokens,
          declaration.name,
          SymbolMethod,
          declaration.span,
          Some(name),
        )
        for parameter in declaration.parameters {
          push_language_symbol(
            symbols,
            tokens,
            parameter,
            SymbolParameter,
            declaration.span,
            Some(name + "." + declaration.name),
          )
        }
        for child in declaration.body {
          collect_statement_symbols(child, tokens, symbols, Some(name))
        }
      }
    }
    ImportStatement(_, bindings, span) =>
      for binding in bindings {
        push_language_symbol(
          symbols,
          tokens,
          binding.local_name,
          SymbolImport,
          span,
          container,
        )
      }
    ForStatement(name, sequence, body, span) => {
      push_language_symbol(
        symbols,
        tokens,
        name,
        SymbolVariable,
        span,
        container,
      )
      collect_expression_symbols(sequence, tokens, symbols, container)
      collect_statement_symbols(body, tokens, symbols, container)
    }
    BlockStatement(statements, _) =>
      for child in statements {
        collect_statement_symbols(child, tokens, symbols, container)
      }
    IfStatement(condition, yes, no, _) => {
      collect_expression_symbols(condition, tokens, symbols, container)
      collect_statement_symbols(yes, tokens, symbols, container)
      match no {
        Some(child) =>
          collect_statement_symbols(child, tokens, symbols, container)
        None => ()
      }
    }
    WhileStatement(condition, body, _) => {
      collect_expression_symbols(condition, tokens, symbols, container)
      collect_statement_symbols(body, tokens, symbols, container)
    }
    ExpressionStatement(expression, _) =>
      collect_expression_symbols(expression, tokens, symbols, container)
    ReturnStatement(value, _) =>
      match value {
        Some(expression) =>
          collect_expression_symbols(expression, tokens, symbols, container)
        None => ()
      }
    BreakStatement(_) | ContinueStatement(_) => ()
  }
}

///|
pub fn LanguageDocument::new(
  source_name : String,
  source : String,
) -> LanguageDocument {
  let scanned = scan(source)
  let diagnostics : Array[Diagnostic] = []
  let statements : Array[Stmt] = []
  for issue in scanned.diagnostics {
    diagnostics.push(issue.with_source(source_name))
  }
  if diagnostics.is_empty() {
    match parse_program(source) {
      ProgramParsed(parsed) => {
        for statement in parsed {
          statements.push(statement)
        }
        for issue in resolve_program(parsed) {
          diagnostics.push(issue.with_source(source_name))
        }
      }
      ProgramParseFailed(issues) =>
        for issue in issues {
          diagnostics.push(issue.with_source(source_name))
        }
    }
  }
  let symbols : Array[LanguageSymbol] = []
  for statement in statements {
    collect_statement_symbols(statement, scanned.tokens, symbols, None)
  }
  {
    source_name,
    source,
    tokens: scanned.tokens,
    statements,
    diagnostics,
    symbols,
  }
}

///|
pub fn LanguageDocument::token_at(
  self : LanguageDocument,
  offset : Int,
) -> Token? {
  for token in self.tokens {
    if span_contains_offset(token.span, offset) ||
      (token.span.length() == 0 && token.span.start.offset == offset) {
      return Some(token)
    }
  }
  None
}

///|
pub fn LanguageDocument::completions(
  self : LanguageDocument,
  prefix : String,
) -> Array[String] {
  let candidates : Array[String] = [
    "break", "class", "construct", "continue", "else", "false", "for", "foreign",
    "if", "import", "as", "in", "is", "null", "return", "static", "super", "this",
    "true", "var", "while", "Fiber", "Fn", "List", "Map", "Num", "Object", "Range",
    "Sequence", "String", "System",
  ]
  for symbol in self.symbols {
    candidates.push(symbol.name)
  }
  let result : Array[String] = []
  for candidate in candidates {
    if candidate.has_prefix(prefix) {
      let mut duplicate = false
      for existing in result {
        if existing == candidate {
          duplicate = true
        }
      }
      if !duplicate {
        result.push(candidate)
      }
    }
  }
  result
}

///|
pub fn LanguageDocument::hover(
  self : LanguageDocument,
  offset : Int,
) -> LanguageHover? {
  let token = match self.token_at(offset) {
    Some(value) => value
    None => return None
  }
  for symbol in self.symbols {
    if symbol.name == token.lexeme {
      let owner = match symbol.container {
        Some(value) => " in " + value
        None => ""
      }
      return Some({
        title: symbol.name,
        detail: symbol_kind_text(symbol.kind) + owner,
        span: token.span,
      })
    }
  }
  if token.is_keyword() {
    Some({ title: token.lexeme, detail: "Wren 0.4 keyword", span: token.span, })
  } else {
    None
  }
}

///|
pub fn LanguageDocument::definition(
  self : LanguageDocument,
  offset : Int,
) -> LanguageLocation? {
  let token = match self.token_at(offset) {
    Some(value) => value
    None => return None
  }
  for symbol in self.symbols {
    if symbol.name == token.lexeme {
      return Some({ source_name: self.source_name, span: symbol.span, })
    }
  }
  None
}

///|
pub fn LanguageDocument::references(
  self : LanguageDocument,
  offset : Int,
) -> Array[LanguageLocation] {
  let token = match self.token_at(offset) {
    Some(value) => value
    None => return []
  }
  let result : Array[LanguageLocation] = []
  for candidate in self.tokens {
    if candidate.lexeme == token.lexeme &&
      (
        candidate.kind == Identifier ||
        candidate.kind == Field ||
        candidate.kind == StaticField
      ) {
      result.push({ source_name: self.source_name, span: candidate.span, })
    }
  }
  result
}

///|
fn valid_language_identifier(name : String) -> Bool {
  let scanned = scan(name)
  scanned.diagnostics.is_empty() &&
  scanned.tokens.length() == 2 &&
  scanned.tokens[0].kind == Identifier &&
  scanned.tokens[0].lexeme == name
}

///|
pub fn LanguageDocument::rename(
  self : LanguageDocument,
  offset : Int,
  new_name : String,
) -> Array[LanguageTextEdit]? {
  if !valid_language_identifier(new_name) {
    return None
  }
  let references = self.references(offset)
  if references.is_empty() {
    return None
  }
  let edits : Array[LanguageTextEdit] = []
  for location in references {
    edits.push({
      source_name: location.source_name,
      span: location.span,
      replacement: new_name,
    })
  }
  Some(edits)
}

///|
/// Stateful document registry that can be embedded behind an LSP transport.
pub(all) struct LanguageServer {
  documents : Map[String, LanguageDocument]
}

///|
pub fn LanguageServer::new() -> LanguageServer {
  { documents: {}, }
}

///|
pub fn LanguageServer::open(
  self : LanguageServer,
  source_name : String,
  source : String,
) -> Array[Diagnostic] {
  let document = LanguageDocument::new(source_name, source)
  self.documents[source_name] = document
  document.diagnostics
}

///|
pub fn LanguageServer::close(
  self : LanguageServer,
  source_name : String,
) -> Bool {
  if self.documents.get(source_name) is Some(_) {
    self.documents.remove(source_name)
    true
  } else {
    false
  }
}

///|
pub fn LanguageServer::document(
  self : LanguageServer,
  source_name : String,
) -> LanguageDocument? {
  self.documents.get(source_name)
}
