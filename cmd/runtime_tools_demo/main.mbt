///|
fn main {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing module \{name}") },
    [],
    [],
  )
  ignore(
    vm.attach_debugger([@moonwren.DebugBreakpoint::new("main", 2)], false, fn(
      snapshot,
    ) {
      println(
        "debug stop \{snapshot.source_name}:\{snapshot.span.line()} with \{snapshot.variables.length()} visible variable(s)",
      )
      @moonwren.DebugContinue
    }),
  )
  let source =
    #|var counter = 40
    #|var state = {"counter": counter}
    #|var worker = Fiber.new {
    #|  var reply = Fiber.yield("load:counter")
    #|  return reply + 2
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramFailed(issues, _) => {
      println(issues[0].render("main"))
      return
    }
    _ => ()
  }
  let archive = match vm.save_state("main", ["state"]) {
    @moonwren.VmStateSaved(archive) => archive
    @moonwren.VmStateSaveFailed(issue) => {
      println(issue.render("main"))
      return
    }
  }
  let fiber = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => {
      println(issue.render("main"))
      return
    }
  }
  let task = match vm.new_async_task(fiber) {
    @moonwren.VmAsyncTaskCreated(task) => task
    @moonwren.VmAsyncTaskCreateFailed(issue) => {
      println(issue.render("main"))
      return
    }
  }
  match vm.start_async(task, None) {
    @moonwren.VmAsyncYielded(request, _) => {
      println("host request: \{request.value().to_text()}")
      match vm.resume_async(task, request, @moonwren.Value::number(40.0)) {
        @moonwren.VmAsyncCompleted(value, _) =>
          println("async result: \{value.to_text()}")
        @moonwren.VmAsyncFailed(issues, _) => println(issues[0].render("main"))
        _ => println("worker yielded again")
      }
    }
    _ => println("worker did not yield")
  }
  match vm.restore_state(archive) {
    @moonwren.VmStateRestored(count) =>
      println("restored \{count} state root(s)")
    @moonwren.VmStateRestoreFailed(issue) => println(issue.render("main"))
  }
  vm.close()
}
