///|
pub(all) struct ReloadStateSelection {
  module_name : String
  globals : Array[String]
}

///|
pub fn ReloadStateSelection::new(
  module_name : String,
  globals : Array[String],
) -> ReloadStateSelection {
  { module_name, globals: globals.copy(), }
}

///|
pub(all) struct ReloadStateArchive {
  module_name : String
  archive : String
}

///|
fn reload_failure(module_name : String, message : String) -> ProgramRunResult {
  ProgramFailed([invalid_vm_state(message, module_name)], [])
}

///|
fn reload_visit_dependency(
  name : String,
  names : Array[String],
  sources : Array[ModuleSource],
  states : Array[Int],
  ordered : Array[String],
) -> String? {
  let mut index = -1
  for candidate_index = 0
      candidate_index < names.length()
      candidate_index = candidate_index + 1 {
    if names[candidate_index] == name {
      index = candidate_index
    }
  }
  if index < 0 {
    return None
  }
  if states[index] == 2 {
    return None
  }
  if states[index] == 1 {
    return Some("cyclic reload dependency involving '\{name}'")
  }
  states[index] = 1
  let source = match find_module_source(sources, name) {
    Some(value) => value
    None => return Some("reload module '\{name}' has no source")
  }
  let statements = match parse_program(source) {
    ProgramParsed(value) => value
    ProgramParseFailed(issues) =>
      return Some(
        "reload module '\{name}' does not parse: \{issues[0].message}",
      )
  }
  for statement in statements {
    match statement {
      ImportStatement(specifier, _, _) =>
        if names.contains(specifier) {
          match
            reload_visit_dependency(specifier, names, sources, states, ordered) {
            Some(message) => return Some(message)
            None => ()
          }
        }
      _ => ()
    }
  }
  states[index] = 2
  ordered.push(name)
  None
}

///|
fn reload_dependency_order(
  names : Array[String],
  sources : Array[ModuleSource],
) -> Result[Array[String], String] {
  let states = Array::make(names.length(), 0)
  let ordered : Array[String] = []
  for name in names {
    match reload_visit_dependency(name, names, sources, states, ordered) {
      Some(message) => return Err(message)
      None => ()
    }
  }
  Ok(ordered)
}

///|
/// Atomically replace several modules and migrate full MWS1 state graphs. The
/// migration callback may validate or transform each archive before it enters
/// the candidate runtime. No old runtime state changes until all replacements,
/// migrations, dependent roots, and limits succeed.
pub fn Vm::reload_modules_with_migration(
  self : Vm,
  replacements : Array[ModuleSource],
  preserve : Array[ReloadStateSelection],
  migrate : (ReloadStateArchive) -> Result[String, String],
) -> ProgramRunResult {
  if self.closed {
    return reload_failure("<reload>", "VM is closed")
  }
  if replacements.is_empty() {
    return reload_failure("<reload>", "at least one replacement is required")
  }
  self.prepare_operation()
  let current = self.runtime()
  current.begin_operation()
  let candidate_sources = copy_sources(self.sources)
  let targets : Array[String] = []
  for replacement in replacements {
    if replacement.name.length() == 0 {
      return reload_failure("<reload>", "replacement module name is required")
    }
    if replacement.source.length() > self.limits.max_source_characters {
      return reload_failure(
        replacement.name,
        "replacement source exceeds the source size limit",
      )
    }
    if targets.contains(replacement.name) {
      return reload_failure(replacement.name, "duplicate replacement module")
    }
    targets.push(replacement.name)
    match find_source_index(candidate_sources, replacement.name) {
      Some(index) => candidate_sources[index] = replacement
      None => candidate_sources.push(replacement)
    }
  }
  let archives : Array[ReloadStateArchive] = []
  let migration_targets : Array[String] = []
  for selection in preserve {
    for existing in archives {
      if existing.module_name == selection.module_name {
        return reload_failure(
          selection.module_name,
          "duplicate state migration selection",
        )
      }
    }
    let archive = match
      save_context_state(current, selection.module_name, selection.globals) {
      VmStateSaved(value) => value
      VmStateSaveFailed(issue) => return ProgramFailed([issue], [])
    }
    archives.push({ module_name: selection.module_name, archive, })
    migration_targets.push(selection.module_name)
  }
  let candidate = make_vm_context(
    candidate_sources,
    self.limits,
    self.fallback_loader,
    copy_foreign_methods(self.foreign_methods),
    copy_foreign_classes(self.foreign_classes),
    self.should_cancel,
  )
  candidate.begin_operation()
  let mut last = Value::null()
  let migration_order = match
    reload_dependency_order(migration_targets, candidate_sources) {
    Ok(value) => value
    Err(message) => {
      finalize_foreign_instances(candidate)
      return reload_failure("<reload>", message)
    }
  }
  let replacement_order = match
    reload_dependency_order(targets, candidate_sources) {
    Ok(value) => value
    Err(message) => {
      finalize_foreign_instances(candidate)
      return reload_failure("<reload>", message)
    }
  }
  // Initialize state-owning modules first so their complete graphs can be
  // restored before dependent modules capture imported values.
  for target in migration_order {
    let source = match find_module_source(candidate_sources, target) {
      Some(value) => value
      None => {
        finalize_foreign_instances(candidate)
        return reload_failure(
          target, "state migration module has no retained or replacement source",
        )
      }
    }
    match execute_module_source(target, source, candidate) {
      ModuleExecutionFailed(issues) => {
        finalize_foreign_instances(candidate)
        return ProgramFailed(issues, copy_output(candidate.output))
      }
      ModuleExecuted(_, value) => last = value
    }
  }
  for saved in archives {
    let migrated = match migrate(saved) {
      Ok(value) => value
      Err(message) => {
        finalize_foreign_instances(candidate)
        return reload_failure(
          saved.module_name,
          "state migration failed: " + message,
        )
      }
    }
    match restore_context_state(candidate, migrated) {
      VmStateRestored(_) => ()
      VmStateRestoreFailed(issue) => {
        finalize_foreign_instances(candidate)
        return ProgramFailed([issue], copy_output(candidate.output))
      }
    }
  }
  // Then initialize the remaining replacements against the migrated state.
  for target in replacement_order {
    if migration_targets.contains(target) {
      continue
    }
    let source = match find_module_source(candidate_sources, target) {
      Some(value) => value
      None => {
        finalize_foreign_instances(candidate)
        return reload_failure(target, "replacement source is unavailable")
      }
    }
    match execute_module_source(target, source, candidate) {
      ModuleExecutionFailed(issues) => {
        finalize_foreign_instances(candidate)
        return ProgramFailed(issues, copy_output(candidate.output))
      }
      ModuleExecuted(_, value) => last = value
    }
  }
  for root in self.roots {
    if targets.contains(root) || migration_targets.contains(root) {
      continue
    }
    let source = match find_module_source(candidate_sources, root) {
      Some(value) => value
      None => {
        finalize_foreign_instances(candidate)
        return reload_failure(root, "root module has no retained source")
      }
    }
    match execute_module_source(root, source, candidate) {
      ModuleExecutionFailed(issues) => {
        finalize_foreign_instances(candidate)
        return ProgramFailed(issues, copy_output(candidate.output))
      }
      ModuleExecuted(_, value) => last = value
    }
  }
  match object_limit_issue(candidate, "<reload>") {
    Some(issue) => {
      finalize_foreign_instances(candidate)
      return ProgramFailed([issue], copy_output(candidate.output))
    }
    None => ()
  }
  finalize_foreign_instances(current)
  invalidate_vm_handles(self)
  self.generation = self.generation + 1
  self.sources = candidate_sources
  persistent_vm_contexts[self.context_identifier] = Some(candidate)
  ProgramCompleted(last, copy_output(candidate.output))
}

///|
/// Atomically replace multiple modules and preserve complete selected state
/// graphs without transforming the MWS1 archives.
pub fn Vm::reload_modules(
  self : Vm,
  replacements : Array[ModuleSource],
  preserve : Array[ReloadStateSelection],
) -> ProgramRunResult {
  self.reload_modules_with_migration(replacements, preserve, fn(saved) {
    Ok(saved.archive)
  })
}
