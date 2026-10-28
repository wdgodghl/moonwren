///|
fn main {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(500000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing module \{name}") },
    [],
    [],
  )
  let source =
    #|import "task" for Task
    #|import "timer" for Timer
    #|var worker = Fn.new {
    #|  var left = Task.run(Fn.new {
    #|    Timer.sleep(20)
    #|    return 20
    #|  })
    #|  var right = Task.run(Fn.new {
    #|    Timer.sleep(5)
    #|    return 22
    #|  })
    #|  return Task.all([left, right]).reduce { |sum, value| sum + value }
    #|}
  match vm.interpret("main", source) {
    @moonwren.ProgramFailed(issues, _) => {
      println(issues[0].render(source))
      return
    }
    _ => ()
  }
  let worker = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => {
      println(issue.message)
      return
    }
  }
  let scheduler = vm.new_scheduler(16)
  ignore(scheduler.spawn(worker))
  ignore(scheduler.poll())
  ignore(scheduler.advance(5.0))
  ignore(scheduler.poll())
  ignore(scheduler.advance(15.0))
  ignore(scheduler.poll())
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(0, value, _) =>
      println("joined result: \{value.to_text()}")
    @moonwren.VmSchedulerTaskFailed(_, issues, _) => println(issues[0].message)
    _ => println("root task is still waiting")
  }
  scheduler.close()
  ignore(vm.release(worker))
  vm.close()
}
