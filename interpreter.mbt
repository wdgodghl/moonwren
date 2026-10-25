///|
pub(all) enum ProgramRunResult {
  ProgramCompleted(Value, Array[String])
  ProgramFailed(Array[Diagnostic], Array[String])
}

///|
/// Per-operation resource limits for a persistent `Vm`.
pub(all) struct VmLimits {
  max_steps : Int
  max_call_depth : Int
  max_output_characters : Int
  max_modules : Int
  max_objects : Int
  max_source_characters : Int
}

///|
/// Automatic collection policy evaluated between host operations. Collection
/// never interrupts a running Wren call, so temporary host return values remain
/// valid until the next VM operation unless retained with a handle.
pub(all) struct VmGcPolicy {
  minimum_objects : Int
  growth_percent : Int
}

///|
pub fn VmGcPolicy::new(
  minimum_objects : Int,
  growth_percent : Int,
) -> VmGcPolicy {
  { minimum_objects, growth_percent, }
}

///|
pub fn VmLimits::new(
  max_steps : Int,
  max_call_depth : Int,
  max_output_characters : Int,
  max_modules : Int,
  max_objects : Int,
  max_source_characters : Int,
) -> VmLimits {
  {
    max_steps,
    max_call_depth,
    max_output_characters,
    max_modules,
    max_objects,
    max_source_characters,
  }
}

///|
/// Limits suitable for ordinary embedded scripts.
pub fn VmLimits::standard(max_steps : Int) -> VmLimits {
  VmLimits::new(max_steps, 64, 1000000, 1024, 1000000, 10000000)
}

///|
/// An opaque strong root owned by a persistent VM.
pub struct VmHandle {
  vm_identity : Int
  identifier : Int
  generation : Int
}

///|
pub(all) enum VmHandleResult {
  VmHandleCreated(VmHandle)
  VmHandleFailed(Diagnostic)
}

///|
/// Internal strong-root entry retained by a `Vm`.
pub struct VmHandleEntry {
  value : Value
  generation : Int
  mut alive : Bool
}

///|
/// Persistent contexts are hidden behind integer identities so the public VM
/// API does not expose evaluator implementation types.
let persistent_vm_contexts : Array[RuntimeContext?] = []

///|
/// Append-only identity tokens prevent handles from being accepted by another
/// VM even when a closed runtime slot is reused.
let persistent_vm_identities : Array[Unit] = []

///|
priv struct PreservedBinding {
  name : String
  value : Value
}

///|
/// A long-lived Wren runtime. Modules, globals, classes, closures, Fibers and
/// foreign objects remain alive across host calls until `close` or a successful
/// transactional reload replaces the runtime generation.
pub struct Vm {
  identity : Int
  context_identifier : Int
  mut sources : Array[ModuleSource]
  roots : Array[String]
  handles : Array[VmHandleEntry]
  mut generation : Int
  mut closed : Bool
  limits : VmLimits
  fallback_loader : (String, String) -> ModuleLoadResult
  foreign_methods : Array[ForeignMethodBinding]
  foreign_classes : Array[ForeignClassBinding]
  should_cancel : () -> Bool
  mut automatic_gc : Bool
  mut gc_minimum_objects : Int
  mut gc_growth_percent : Int
  mut next_gc_objects : Int
  mut last_gc_stats : VmGcStats?
}

///|
fn Vm::runtime(self : Vm) -> RuntimeContext {
  match persistent_vm_contexts[self.context_identifier] {
    Some(context) => context
    None => abort("closed VM has no runtime context")
  }
}

///|
fn copy_output(output : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for line in output {
    copied.push(line)
  }
  copied
}

///|
fn copy_sources(sources : Array[ModuleSource]) -> Array[ModuleSource] {
  let copied : Array[ModuleSource] = []
  for source in sources {
    copied.push(ModuleSource::new(source.name, source.source))
  }
  copied
}

///|
fn copy_foreign_methods(
  bindings : Array[ForeignMethodBinding],
) -> Array[ForeignMethodBinding] {
  let copied : Array[ForeignMethodBinding] = []
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn copy_foreign_classes(
  bindings : Array[ForeignClassBinding],
) -> Array[ForeignClassBinding] {
  let copied : Array[ForeignClassBinding] = []
  for binding in bindings {
    copied.push(binding)
  }
  copied
}

///|
fn find_source_index(sources : Array[ModuleSource], name : String) -> Int? {
  for index = 0; index < sources.length(); index = index + 1 {
    if sources[index].name == name {
      return Some(index)
    }
  }
  None
}

///|
fn make_vm_context(
  sources : Array[ModuleSource],
  limits : VmLimits,
  fallback_loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
  should_cancel : () -> Bool,
) -> RuntimeContext {
  let loader = fn(importer : String, specifier : String) {
    match find_module_source(sources, specifier) {
      Some(source) => ModuleLoaded(specifier, source)
      None => fallback_loader(importer, specifier)
    }
  }
  RuntimeContext::new_with_limits(
    limits.max_steps,
    limits.max_call_depth,
    limits.max_output_characters,
    limits.max_modules,
    limits.max_objects,
    limits.max_source_characters,
    "<host>",
    loader,
    foreign_methods,
    foreign_classes,
    should_cancel,
  )
}

///|
pub fn Vm::new(
  limits : VmLimits,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
) -> Vm {
  Vm::new_cancellable(limits, loader, foreign_methods, foreign_classes, fn() {
    false
  })
}

///|
pub fn Vm::new_cancellable(
  limits : VmLimits,
  loader : (String, String) -> ModuleLoadResult,
  foreign_methods : Array[ForeignMethodBinding],
  foreign_classes : Array[ForeignClassBinding],
  should_cancel : () -> Bool,
) -> Vm {
  let sources : Array[ModuleSource] = []
  let methods = copy_foreign_methods(foreign_methods)
  let classes = copy_foreign_classes(foreign_classes)
  let context = make_vm_context(
    sources, limits, loader, methods, classes, should_cancel,
  )
  let mut context_identifier = -1
  for index = 0; index < persistent_vm_contexts.length(); index = index + 1 {
    if context_identifier < 0 {
      match persistent_vm_contexts[index] {
        None => context_identifier = index
        Some(_) => ()
      }
    }
  }
  if context_identifier < 0 {
    context_identifier = persistent_vm_contexts.length()
    persistent_vm_contexts.push(Some(context))
  } else {
    persistent_vm_contexts[context_identifier] = Some(context)
  }
  let identity = persistent_vm_identities.length()
  persistent_vm_identities.push(())
  {
    identity,
    context_identifier,
    sources,
    roots: [],
    handles: [],
    generation: 0,
    closed: false,
    limits,
    fallback_loader: loader,
    foreign_methods: methods,
    foreign_classes: classes,
    should_cancel,
    automatic_gc: true,
    gc_minimum_objects: 10000,
    gc_growth_percent: 100,
    next_gc_objects: 10000,
    last_gc_stats: None,
  }
}

///|
fn Vm::root_values(self : Vm) -> Array[Value] {
  let roots : Array[Value] = []
  for handle in self.handles {
    if handle.alive && handle.generation == self.generation {
      roots.push(handle.value)
    }
  }
  roots
}

///|
fn Vm::record_collection(self : Vm, stats : VmGcStats) -> Unit {
  self.last_gc_stats = Some(stats)
  let grown = stats.reachable_objects * (100 + self.gc_growth_percent) / 100 + 1
  self.next_gc_objects = if grown < self.gc_minimum_objects {
    self.gc_minimum_objects
  } else {
    grown
  }
}

///|
fn Vm::prepare_operation(self : Vm) -> Unit {
  if self.closed {
    return
  }
  let context = self.runtime()
  if context.gc_requested ||
    (self.automatic_gc && context.allocated_objects() >= self.next_gc_objects) {
    let stats = collect_runtime_garbage(context, self.root_values())
    context.gc_requested = false
    self.record_collection(stats)
  }
}

///|
/// Enable automatic collection between host operations. Invalid policies are
/// rejected without changing the active configuration.
pub fn Vm::configure_automatic_gc(self : Vm, policy : VmGcPolicy) -> Bool {
  if policy.minimum_objects <= 0 || policy.growth_percent < 0 {
    return false
  }
  self.automatic_gc = true
  self.gc_minimum_objects = policy.minimum_objects
  self.gc_growth_percent = policy.growth_percent
  self.next_gc_objects = policy.minimum_objects
  true
}

///|
pub fn Vm::disable_automatic_gc(self : Vm) -> Unit {
  self.automatic_gc = false
}

///|
pub fn Vm::last_automatic_gc(self : Vm) -> VmGcStats? {
  self.last_gc_stats
}

///|
fn invalid_vm_state(message : String, source_name : String) -> Diagnostic {
  Diagnostic::new(Runtime, ExecutionLimit, message, SourceSpan::empty()).with_source(
    source_name,
  )
}

///|
fn validate_vm_limits(limits : VmLimits, source_name : String) -> Diagnostic? {
  if limits.max_steps <= 0 ||
    limits.max_call_depth <= 0 ||
    limits.max_output_characters <= 0 ||
    limits.max_modules <= 0 ||
    limits.max_objects <= 0 ||
    limits.max_source_characters <= 0 {
    Some(invalid_vm_state("all VM limits must be positive", source_name))
  } else {
    None
  }
}

///|
fn Vm::operation_failure(
  self : Vm,
  diagnostic : Diagnostic,
) -> ProgramRunResult {
  ProgramFailed([diagnostic], copy_output(self.runtime().output))
}

///|
fn object_limit_issue(
  context : RuntimeContext,
  source_name : String,
) -> Diagnostic? {
  if context.allocated_objects() > context.max_objects {
    Some(
      Diagnostic::new(
        Runtime,
        ExecutionLimit,
        "runtime object limit exceeded",
        SourceSpan::empty(),
      ).with_source(source_name),
    )
  } else {
    None
  }
}

///|
/// Interpret and retain one named root module. Reusing an existing name is an
/// explicit reload operation so accidental cache hits cannot hide new source.
pub fn Vm::interpret(
  self : Vm,
  source_name : String,
  source : String,
) -> ProgramRunResult {
  if self.closed {
    return ProgramFailed([invalid_vm_state("VM is closed", source_name)], [])
  }
  self.prepare_operation()
  let context = self.runtime()
  context.begin_operation()
  match validate_vm_limits(self.limits, source_name) {
    Some(issue) => return self.operation_failure(issue)
    None => ()
  }
  if find_source_index(self.sources, source_name) is Some(_) {
    return self.operation_failure(
      invalid_vm_state(
        "module '\{source_name}' already exists; use reload_module",
        source_name,
      ),
    )
  }
  self.sources.push(ModuleSource::new(source_name, source))
  match execute_module_source(source_name, source, context) {
    ModuleExecutionFailed(issues) =>
      ProgramFailed(issues, copy_output(context.output))
    ModuleExecuted(_, value) => {
      match object_limit_issue(context, source_name) {
        Some(issue) =>
          return ProgramFailed([issue], copy_output(context.output))
        None => ()
      }
      self.roots.push(source_name)
      ProgramCompleted(value, copy_output(context.output))
    }
  }
}

///|
fn Vm::module_value(
  self : Vm,
  module_name : String,
  variable : String,
) -> VmHandleResult {
  if self.closed {
    return VmHandleFailed(invalid_vm_state("VM is closed", module_name))
  }
  let context = self.runtime()
  match find_runtime_module(context, module_name) {
    None =>
      VmHandleFailed(
        Diagnostic::new(
          Runtime,
          ModuleNotFound,
          "module '\{module_name}' is not loaded",
          SourceSpan::empty(),
        ).with_source(module_name),
      )
    Some(index) =>
      match context.modules[index].environment.get(variable) {
        None =>
          VmHandleFailed(
            Diagnostic::new(
              Runtime,
              UndefinedExport,
              "module '\{module_name}' does not define '\{variable}'",
              SourceSpan::empty(),
            ).with_source(module_name),
          )
        Some(value) => {
          let identifier = self.handles.length()
          self.handles.push({ value, generation: self.generation, alive: true, })
          VmHandleCreated({
            vm_identity: self.identity,
            identifier,
            generation: self.generation,
          })
        }
      }
  }
}

///|
/// Create a strong host root for a module variable.
pub fn Vm::capture(
  self : Vm,
  module_name : String,
  variable : String,
) -> VmHandleResult {
  self.module_value(module_name, variable)
}

///|
/// Read a module variable without creating a strong host root. Runtime-backed
/// values should be passed to `retain` before an explicit collection pass.
pub fn Vm::read(
  self : Vm,
  module_name : String,
  variable : String,
) -> ProgramRunResult {
  if self.closed {
    return ProgramFailed([invalid_vm_state("VM is closed", module_name)], [])
  }
  self.prepare_operation()
  let context = self.runtime()
  context.begin_operation()
  match self.module_value(module_name, variable) {
    VmHandleFailed(issue) => ProgramFailed([issue], copy_output(context.output))
    VmHandleCreated(handle) => {
      let value = match self.resolve_handle(handle) {
        Some(value) => value
        None =>
          return self.operation_failure(
            invalid_vm_state("VM handle is invalid", module_name),
          )
      }
      ignore(self.release(handle))
      ProgramCompleted(value, copy_output(context.output))
    }
  }
}

///|
/// Retain a value returned by a VM call as a strong host root. Values that
/// refer to runtime objects must be retained before the next explicit GC pass.
pub fn Vm::retain(self : Vm, value : Value) -> VmHandleResult {
  if self.closed {
    return VmHandleFailed(invalid_vm_state("VM is closed", "<host>"))
  }
  let identifier = self.handles.length()
  self.handles.push({ value, generation: self.generation, alive: true, })
  VmHandleCreated({
    vm_identity: self.identity,
    identifier,
    generation: self.generation,
  })
}

///|
fn Vm::resolve_handle(self : Vm, handle : VmHandle) -> Value? {
  if self.closed ||
    handle.vm_identity != self.identity ||
    handle.generation != self.generation ||
    handle.identifier < 0 ||
    handle.identifier >= self.handles.length() {
    return None
  }
  let entry = self.handles[handle.identifier]
  if !entry.alive || entry.generation != self.generation {
    None
  } else {
    Some(entry.value)
  }
}

///|
/// Release a strong host root. Released and pre-reload handles cannot be used.
pub fn Vm::release(self : Vm, handle : VmHandle) -> Bool {
  if handle.vm_identity != self.identity ||
    handle.generation != self.generation ||
    handle.identifier < 0 ||
    handle.identifier >= self.handles.length() {
    return false
  }
  let entry = self.handles[handle.identifier]
  if !entry.alive {
    false
  } else {
    entry.alive = false
    true
  }
}

///|
fn Vm::invoke_host(
  self : Vm,
  handle : VmHandle,
  method_name : String,
  arguments : Array[Value],
) -> ProgramRunResult {
  if self.closed {
    return ProgramFailed([invalid_vm_state("VM is closed", "<host>")], [])
  }
  self.prepare_operation()
  let context = self.runtime()
  context.begin_operation()
  let receiver = match self.resolve_handle(handle) {
    Some(value) => value
    None =>
      return self.operation_failure(
        invalid_vm_state("VM handle is invalid or released", "<host>"),
      )
  }
  context.current_source = "<host>"
  match
    invoke_method(
      receiver,
      method_name,
      arguments,
      SourceSpan::empty(),
      context,
    ) {
    EvaluationSucceeded(value) =>
      match object_limit_issue(context, "<host>") {
        Some(issue) => ProgramFailed([issue], copy_output(context.output))
        None => ProgramCompleted(value, copy_output(context.output))
      }
    EvaluationFailed(issue) =>
      ProgramFailed([issue.with_source("<host>")], copy_output(context.output))
  }
}

///|
/// Call a captured Wren function from MoonBit.
pub fn Vm::call(
  self : Vm,
  handle : VmHandle,
  arguments : Array[Value],
) -> ProgramRunResult {
  self.invoke_host(handle, "call", arguments)
}

///|
/// Call a method or getter on a captured Wren value from MoonBit.
pub fn Vm::call_method(
  self : Vm,
  handle : VmHandle,
  method_name : String,
  arguments : Array[Value],
) -> ProgramRunResult {
  self.invoke_host(handle, method_name, arguments)
}

///|
/// Read a Wren getter or built-in property from a captured value.
pub fn Vm::get(
  self : Vm,
  handle : VmHandle,
  property_name : String,
) -> ProgramRunResult {
  if self.closed {
    return ProgramFailed([invalid_vm_state("VM is closed", "<host>")], [])
  }
  self.prepare_operation()
  let context = self.runtime()
  context.begin_operation()
  let receiver = match self.resolve_handle(handle) {
    Some(value) => value
    None =>
      return self.operation_failure(
        invalid_vm_state("VM handle is invalid or released", "<host>"),
      )
  }
  context.current_source = "<host>"
  match read_property(receiver, property_name, SourceSpan::empty(), context) {
    EvaluationSucceeded(value) =>
      match object_limit_issue(context, "<host>") {
        Some(issue) => ProgramFailed([issue], copy_output(context.output))
        None => ProgramCompleted(value, copy_output(context.output))
      }
    EvaluationFailed(issue) =>
      ProgramFailed([issue.with_source("<host>")], copy_output(context.output))
  }
}

///|
fn portable_reload_value(value : Value) -> Bool {
  match value {
    NullValue
    | BoolValue(_)
    | NumberValue(_)
    | StringValue(_)
    | RawStringValue(_)
    | RangeValue(_, _, _) => true
    _ => false
  }
}

///|
fn invalidate_vm_handles(vm : Vm) -> Unit {
  for handle in vm.handles {
    handle.alive = false
  }
}

///|
/// Transactionally rebuild the VM from its root modules using a replacement
/// source. Selected primitive globals are migrated after the replacement
/// module initializes and before dependent roots execute. A failed rebuild
/// leaves the current VM and all handles unchanged.
pub fn Vm::reload_module(
  self : Vm,
  module_name : String,
  source : String,
  preserve : Array[String],
) -> ProgramRunResult {
  if self.closed {
    return ProgramFailed([invalid_vm_state("VM is closed", module_name)], [])
  }
  self.prepare_operation()
  let context = self.runtime()
  context.begin_operation()
  if source.length() > self.limits.max_source_characters {
    return self.operation_failure(
      invalid_vm_state(
        "replacement source exceeds the source size limit", module_name,
      ),
    )
  }
  let preserved : Array[PreservedBinding] = []
  match find_runtime_module(context, module_name) {
    Some(module_index) =>
      for name in preserve {
        match context.modules[module_index].environment.get(name) {
          None =>
            return self.operation_failure(
              Diagnostic::new(
                Runtime,
                UndefinedExport,
                "module '\{module_name}' does not define preserved global '\{name}'",
                SourceSpan::empty(),
              ).with_source(module_name),
            )
          Some(value) =>
            if portable_reload_value(value) {
              preserved.push({ name, value, })
            } else {
              return self.operation_failure(
                invalid_vm_state(
                  "preserved global '\{name}' is not a portable primitive value",
                  module_name,
                ),
              )
            }
        }
      }
    None =>
      if !preserve.is_empty() {
        return self.operation_failure(
          invalid_vm_state("module is not loaded", module_name),
        )
      }
  }
  let candidate_sources = copy_sources(self.sources)
  match find_source_index(candidate_sources, module_name) {
    Some(index) =>
      candidate_sources[index] = ModuleSource::new(module_name, source)
    None => candidate_sources.push(ModuleSource::new(module_name, source))
  }
  let candidate_methods = copy_foreign_methods(self.foreign_methods)
  let candidate_classes = copy_foreign_classes(self.foreign_classes)
  let candidate = make_vm_context(
    candidate_sources,
    self.limits,
    self.fallback_loader,
    candidate_methods,
    candidate_classes,
    self.should_cancel,
  )
  candidate.begin_operation()
  let target_result = execute_module_source(module_name, source, candidate)
  match target_result {
    ModuleExecutionFailed(issues) => {
      finalize_foreign_instances(candidate)
      return ProgramFailed(issues, copy_output(candidate.output))
    }
    ModuleExecuted(environment, _) =>
      for binding in preserved {
        ignore(environment.assign(binding.name, binding.value))
      }
  }
  let mut last = Value::null()
  for root in self.roots {
    if root == module_name {
      continue
    }
    let root_source = match find_module_source(candidate_sources, root) {
      Some(root_source) => root_source
      None => {
        finalize_foreign_instances(candidate)
        return ProgramFailed(
          [
            invalid_vm_state(
              "root module '\{root}' has no retained source",
              root,
            ),
          ],
          copy_output(candidate.output),
        )
      }
    }
    match execute_module_source(root, root_source, candidate) {
      ModuleExecutionFailed(issues) => {
        finalize_foreign_instances(candidate)
        return ProgramFailed(issues, copy_output(candidate.output))
      }
      ModuleExecuted(_, value) => last = value
    }
  }
  match object_limit_issue(candidate, module_name) {
    Some(issue) => {
      finalize_foreign_instances(candidate)
      return ProgramFailed([issue], copy_output(candidate.output))
    }
    None => ()
  }
  finalize_foreign_instances(context)
  invalidate_vm_handles(self)
  self.generation = self.generation + 1
  self.sources = candidate_sources
  persistent_vm_contexts[self.context_identifier] = Some(candidate)
  ProgramCompleted(last, copy_output(candidate.output))
}

///|
/// Trace VM roots and release unreachable instances. Suspended opaque
/// continuations conservatively retain instances until the Fiber resumes.
pub fn Vm::collect_garbage(self : Vm) -> VmGcStats {
  if self.closed {
    return {
      before_objects: 0,
      reachable_objects: 0,
      reclaimed_objects: 0,
      before_instances: 0,
      reachable_instances: 0,
      reclaimed_instances: 0,
      finalized_foreign_instances: 0,
    }
  }
  let context = self.runtime()
  let stats = collect_runtime_garbage(context, self.root_values())
  context.gc_requested = false
  self.record_collection(stats)
  stats
}

///|
/// Finalize remaining foreign instances and permanently close the VM.
pub fn Vm::close(self : Vm) -> Unit {
  if self.closed {
    return
  }
  finalize_foreign_instances(self.runtime())
  invalidate_vm_handles(self)
  self.closed = true
  persistent_vm_contexts[self.context_identifier] = None
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
