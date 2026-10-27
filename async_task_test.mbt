///|
fn async_test_vm(source : String) -> @moonwren.Vm {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing module \{name}") },
    [],
    [],
  )
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => vm
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
}

///|
test "host async task preserves and resumes a Fiber" {
  let vm = async_test_vm(
    (
      #|var worker = Fiber.new {
      #|  var first = Fiber.yield("read:settings")
      #|  var second = Fiber.yield(first + 1)
      #|  return second * 2
      #|}
    ),
  )
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => abort(issue.message)
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(task) => task
    @moonwren.VmAsyncTaskCreateFailed(issue) => abort(issue.message)
  }
  let first = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(request, _) => {
      assert_eq(request.value(), @moonwren.Value::string("read:settings"))
      request
    }
    _ => abort("expected first host request")
  }
  ignore(vm.collect_garbage())
  let second = match
    vm.resume_async(task, first, @moonwren.Value::number(20.0)) {
    @moonwren.VmAsyncYielded(request, _) => {
      assert_eq(request.value(), @moonwren.Value::number(21.0))
      request
    }
    _ => abort("expected second host request")
  }
  match vm.resume_async(task, second, @moonwren.Value::number(7.0)) {
    @moonwren.VmAsyncCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(14.0))
    _ => abort("expected task completion")
  }
}

///|
test "host async requests are one-shot and cancellable" {
  let vm = async_test_vm(
    (
      #|var worker = Fiber.new {
      #|  return Fiber.yield("request")
      #|}
    ),
  )
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    _ => abort("missing Fiber")
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(task) => task
    _ => abort("could not create task")
  }
  let request = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(request, _) => request
    _ => abort("expected request")
  }
  assert_true(vm.cancel_async(task))
  match vm.resume_async(task, request, @moonwren.Value::null()) {
    @moonwren.VmAsyncFailed(issues, _) =>
      assert_eq(issues[0].code, @moonwren.InvalidFiberState)
    _ => abort("cancelled task must not resume")
  }
}
