///|
pub(all) enum ProgramRunResult {
  ProgramCompleted(Value, Array[String])
  ProgramFailed(Array[Diagnostic], Array[String])
}

///|
fn invalid_execution_limit(source_name : String) -> ProgramRunResult {
  ProgramFailed(
    [
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "execution step limit must be positive",
        SourceSpan::empty(),
      ).with_source(source_name),
    ],
    [],
  )
}

///|
/// Run one named entry module and resolve imports through an embedding callback.
pub fn run_with_loader(
  source_name : String,
  source : String,
  max_steps : Int,
  loader : (String, String) -> ModuleLoadResult,
) -> ProgramRunResult {
  run_with_foreign_bindings(source_name, source, max_steps, loader, [], [])
}

///|
/// Run a named entry module with host implementations for declared foreign
/// methods. Bindings are matched by module, class, static flag, and signature.
pub fn run_with_foreign_methods(
  source_name : String,
  source : String,
  max_steps : Int,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
) -> ProgramRunResult {
  run_with_foreign_bindings(
    source_name,
    source,
    max_steps,
    loader,
    foreign_methods,
    [],
  )
}

///|
/// Run one named entry module with host implementations for foreign methods
/// and host-owned foreign class state.
pub fn run_with_foreign_bindings(
  source_name : String,
  source : String,
  max_steps : Int,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
) -> ProgramRunResult {
  if max_steps <= 0 {
    return invalid_execution_limit(source_name)
  }
  let context = RuntimeContext::new_with_loader(
    max_steps, source_name, loader, foreign_methods, foreign_classes,
  )
  let result = match execute_module_source(source_name, source, context) {
    ModuleExecuted(_, value) => ProgramCompleted(value, context.output)
    ModuleExecutionFailed(issues) => ProgramFailed(issues, context.output)
  }
  finalize_foreign_instances(context)
  result
}

///|
fn find_module_source(modules : Array[ModuleSource], name : String) -> String? {
  for module_source in modules {
    if module_source.name == name {
      return Some(module_source.source)
    }
  }
  None
}

///|
/// Run an entry module from a complete in-memory source collection.
/// Import specifiers are matched against module names exactly.
pub fn run_modules(
  entry_name : String,
  modules : Array[ModuleSource],
  max_steps : Int,
) -> ProgramRunResult {
  let entry_source = match find_module_source(modules, entry_name) {
    Some(source) => source
    None =>
      return ProgramFailed(
        [
          Diagnostic::new(
            Runtime,
            ModuleNotFound,
            "entry module '\{entry_name}' was not provided",
            SourceSpan::empty(),
          ).with_source(entry_name),
        ],
        [],
      )
  }
  let loader = fn(_importer : String, specifier : String) -> ModuleLoadResult {
    match find_module_source(modules, specifier) {
      Some(source) => ModuleLoaded(specifier, source)
      None => ModuleLoadFailed("module '\{specifier}' was not provided")
    }
  }
  run_with_loader(entry_name, entry_source, max_steps, loader)
}

///|
/// Run a source file with a configurable guard against unbounded loops.
pub fn run_with_limit(source : String, max_steps : Int) -> ProgramRunResult {
  run_with_loader("<source>", source, max_steps, fn(_, name) {
    ModuleLoadFailed("module '\{name}' is not available")
  })
}

///|
/// Run a source file using a conservative default step budget.
pub fn run(source : String) -> ProgramRunResult {
  run_with_limit(source, 100000)
}
