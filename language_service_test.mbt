///|
test "language service publishes diagnostics and document symbols" {
  let valid = @moonwren.LanguageDocument::new(
    "main.wren", "var answer = 40\nclass Math {\n add(value) { return value + answer }\n}\n",
  )
  assert_eq(valid.diagnostics.length(), 0)
  assert_true(valid.symbols.length() >= 4)
  assert_eq(valid.symbols[0].name, "answer")
  assert_eq(valid.symbols[0].kind, @moonwren.SymbolVariable)
  let invalid = @moonwren.LanguageDocument::new("bad.wren", "var = 1\n")
  assert_true(invalid.diagnostics.length() > 0)
  assert_eq(invalid.diagnostics[0].source_name, "bad.wren")
}

///|
test "language service completes, hovers, navigates, references, and renames" {
  let source = "var answer = 40\nvar result = answer + 2\nresult\n"
  let document = @moonwren.LanguageDocument::new("main.wren", source)
  let completions = document.completions("an")
  assert_true(completions.contains("answer"))
  let use_offset = source.find("answer +").unwrap()
  let hover = document.hover(use_offset).unwrap()
  assert_eq(hover.title, "answer")
  assert_eq(hover.detail, "variable")
  let definition = document.definition(use_offset).unwrap()
  assert_eq(definition.span.start.line, 1)
  assert_eq(document.references(use_offset).length(), 2)
  let edits = document.rename(use_offset, "total").unwrap()
  assert_eq(edits.length(), 2)
  assert_eq(edits[0].replacement, "total")
  assert_true(document.rename(use_offset, "not valid") is None)
}

///|
test "language server updates documents and closes them" {
  let server = @moonwren.LanguageServer::new()
  assert_eq(server.open("main", "var value = 42\n").length(), 0)
  assert_true(server.document("main") is Some(_))
  assert_true(server.close("main"))
  assert_true(server.document("main") is None)
}

///|
test "debug adapter drives live breakpoints and step commands" {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(10000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let adapter = @moonwren.DebugAdapterSession::new()
  ignore(adapter.set_breakpoints("main", [2]))
  adapter.set_pause_on_entry(false)
  adapter.enqueue(@moonwren.DebugStepInto)
  adapter.enqueue(@moonwren.DebugContinue)
  assert_true(adapter.attach(vm))
  match vm.interpret("main", "var value = 1\nvalue = value + 1\nvalue\n") {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(2.0))
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let stops = adapter.stops()
  assert_true(stops.length() >= 1)
  assert_eq(stops[0].source_name, "main")
  assert_true(stops[0].variables.length() > 0)
  assert_true(adapter.detach(vm))
  vm.close()
}
