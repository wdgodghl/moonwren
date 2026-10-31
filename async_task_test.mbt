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

///|
test "async task API rejects invalid stale repeated and completed operations" {
  let vm = async_test_vm(
    (
      #|var function = Fn.new { 42 }
      #|var worker = Fiber.new {
      #|  var value = Fiber.yield("request")
      #|  return value
      #|}
    ),
  )
  let function = match vm.capture("main", "function") {
    @moonwren.VmHandleCreated(value) => value
    _ => abort("missing function")
  }
  match vm.new_async_task(function) {
    @moonwren.VmAsyncTaskCreated(_) => abort("function is not a Fiber")
    @moonwren.VmAsyncTaskCreateFailed(issue) =>
      assert_true(issue.message.contains("expected Fiber"))
  }
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(value) => value
    _ => abort("missing Fiber")
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(value) => value
    _ => abort("could not create task")
  }
  let request = match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(value, _) => value
    _ => abort("task must yield")
  }
  assert_eq(request.sequence(), 1)
  match vm.start_async(task, None) {
    @moonwren.VmAsyncFailed(issues, _) =>
      assert_true(issues[0].message.contains("already started"))
    _ => abort("repeated start must fail")
  }
  let other_task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(value) => value
    _ => abort("could not create second task")
  }
  match vm.resume_async(other_task, request, @moonwren.Value::null()) {
    @moonwren.VmAsyncFailed(issues, _) =>
      assert_true(issues[0].message.contains("not waiting"))
    _ => abort("unstarted task must fail")
  }
  match vm.resume_async(task, request, @moonwren.Value::number(42.0)) {
    @moonwren.VmAsyncCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => abort("task must complete")
  }
  match vm.resume_async(task, request, @moonwren.Value::null()) {
    @moonwren.VmAsyncFailed(issues, _) =>
      assert_true(issues[0].message.contains("already complete"))
    _ => abort("completed task must fail")
  }
  assert_false(vm.cancel_async(task))
  assert_true(vm.cancel_async(other_task))
  assert_false(vm.cancel_async(other_task))
  let released = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(value) => value
    _ => abort("missing Fiber")
  }
  assert_true(vm.release(released))
  match vm.new_async_task(released) {
    @moonwren.VmAsyncTaskCreated(_) => abort("released Fiber must fail")
    @moonwren.VmAsyncTaskCreateFailed(issue) =>
      assert_true(issue.message.contains("invalid"))
  }
  vm.close()
  match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(_) => abort("closed VM must fail")
    @moonwren.VmAsyncTaskCreateFailed(issue) =>
      assert_true(issue.message.contains("closed"))
  }
}
