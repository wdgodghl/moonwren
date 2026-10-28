///|
fn scheduler_test_vm() -> @moonwren.Vm {
  @moonwren.Vm::new(
    @moonwren.VmLimits::standard(500000),
    fn(_, name) {
      @moonwren.ModuleLoadFailed("module '\{name}' is not available")
    },
    [],
    [],
  )
}

///|
fn scheduler_worker(
  vm : @moonwren.Vm,
  source : String,
) -> @moonwren.VmHandle raise {
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(handle) => handle
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
}

///|
test "scheduler drives virtual timer requests deterministically" {
  let vm = scheduler_test_vm()
  let worker = scheduler_worker(
    vm,
    (
      #|import "timer" for Timer
      #|var worker = Fn.new {
      #|  System.print("started")
      #|  Timer.sleep(10)
      #|  return 42
      #|}
    ),
  )
  let scheduler = vm.new_scheduler(8)
  match scheduler.spawn(worker) {
    @moonwren.VmSchedulerSpawned(0) => ()
    @moonwren.VmSchedulerSpawned(_) => fail("unexpected task identifier")
    @moonwren.VmSchedulerSpawnFailed(issue) => fail(issue.message)
  }
  match scheduler.poll() {
    @moonwren.VmSchedulerIdle => ()
    _ => fail("scheduler should wait for virtual time")
  }
  assert_eq(scheduler.status(0), Some(@moonwren.ScheduledSleeping))
  assert_true(scheduler.advance(9.0))
  match scheduler.poll() {
    @moonwren.VmSchedulerIdle => ()
    _ => fail("timer should not wake early")
  }
  assert_true(scheduler.advance(1.0))
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(0, value, output) => {
      assert_eq(value, @moonwren.Value::number(42.0))
      assert_eq(output, ["started"])
    }
    _ => fail("timer task should complete")
  }
  scheduler.close()
  ignore(vm.release(worker))
  vm.close()
}

///|
test "scheduler runs child tasks and joins all results" {
  let vm = scheduler_test_vm()
  let worker = scheduler_worker(
    vm,
    (
      #|import "task" for Task
      #|import "timer" for Timer
      #|var worker = Fn.new {
      #|  var slow = Task.run(Fn.new {
      #|    Timer.sleep(20)
      #|    return 20
      #|  })
      #|  var fast = Task.run(Fn.new {
      #|    Timer.sleep(5)
      #|    return 22
      #|  })
      #|  var values = Task.all([slow, fast])
      #|  return values[0] + values[1]
      #|}
    ),
  )
  let scheduler = vm.new_scheduler(8)
  ignore(scheduler.spawn(worker))
  match scheduler.poll() {
    @moonwren.VmSchedulerIdle => ()
    _ => fail("children should be sleeping")
  }
  assert_true(scheduler.advance(5.0))
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(2, value, _) =>
      assert_eq(value, @moonwren.Value::number(22.0))
    _ => fail("fast child should complete first")
  }
  assert_true(scheduler.advance(15.0))
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(1, value, _) =>
      assert_eq(value, @moonwren.Value::number(20.0))
    _ => fail("slow child should complete")
  }
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(0, value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("parent should receive joined values")
  }
  scheduler.close()
  ignore(vm.release(worker))
  vm.close()
}

///|
test "scheduler exposes arbitrary host requests and accepts responses" {
  let vm = scheduler_test_vm()
  let worker = scheduler_worker(
    vm,
    (
      #|var worker = Fn.new {
      #|  var response = Fiber.yield("load:answer")
      #|  return response + 1
      #|}
    ),
  )
  let scheduler = vm.new_scheduler(2)
  ignore(scheduler.spawn(worker))
  match scheduler.poll() {
    @moonwren.VmSchedulerExternalRequest(0, request, _) =>
      assert_eq(request.value(), @moonwren.Value::string("load:answer"))
    _ => fail("host request should be visible")
  }
  assert_true(scheduler.deliver(0, @moonwren.Value::number(41.0)))
  match scheduler.poll() {
    @moonwren.VmSchedulerTaskCompleted(0, value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("resumed task should complete")
  }
  scheduler.close()
  ignore(vm.release(worker))
  vm.close()
}

///|
test "scheduler enforces task limits and cancellation" {
  let vm = scheduler_test_vm()
  let worker = scheduler_worker(vm, "var worker = Fn.new { Fiber.yield(1) }")
  let scheduler = vm.new_scheduler(1)
  ignore(scheduler.spawn(worker))
  match scheduler.spawn(worker) {
    @moonwren.VmSchedulerSpawnFailed(issue) =>
      assert_true(issue.message.contains("limit"))
    _ => fail("task limit should reject a second task")
  }
  assert_true(scheduler.cancel(0))
  assert_eq(scheduler.status(0), Some(@moonwren.ScheduledCancelled))
  scheduler.close()
  ignore(vm.release(worker))
  vm.close()
}
