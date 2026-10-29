///|
fn replay_test_scheduler(
  request_text : String,
) -> (@moonwren.Vm, @moonwren.VmScheduler) raise {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  let source = "var worker = Fn.new {\n" +
    " var response = Fiber.yield(\"" +
    request_text +
    "\")\n" +
    " return response + 1\n" +
    "}\n"
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => ()
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let handle = match vm.capture("main", "worker") {
    @moonwren.VmHandleCreated(value) => value
    @moonwren.VmHandleFailed(issue) => fail(issue.message)
  }
  let scheduler = vm.new_scheduler(2)
  match scheduler.spawn(handle) {
    @moonwren.VmSchedulerSpawned(_) => ()
    @moonwren.VmSchedulerSpawnFailed(issue) => fail(issue.message)
  }
  ignore(vm.release(handle))
  (vm, scheduler)
}

///|
test "scheduler record serialize decode and replay are deterministic" {
  let (first_vm, first_scheduler) = replay_test_scheduler("load:answer")
  let recorder = @moonwren.VmSchedulerRecorder::new(
    first_scheduler,
    @moonwren.sha256_hex("workload-v1"),
  )
  match recorder.poll() {
    @moonwren.VmSchedulerExternalRequest(0, _, _) => ()
    _ => fail("first run should yield a request")
  }
  assert_true(recorder.deliver(0, @moonwren.ForeignNumber(41.0)))
  match recorder.poll() {
    @moonwren.VmSchedulerTaskCompleted(0, value, _) =>
      assert_eq(value, @moonwren.Value::number(42.0))
    _ => fail("first run should complete")
  }
  let encoded = @moonwren.encode_scheduler_replay_log(recorder.log()).unwrap()
  let log = match @moonwren.decode_scheduler_replay_log(encoded) {
    @moonwren.SchedulerReplayDecoded(value) => value
    @moonwren.SchedulerReplayDecodeFailed(message) => fail(message)
  }
  let (second_vm, second_scheduler) = replay_test_scheduler("load:answer")
  match
    @moonwren.replay_scheduler_log(
      second_scheduler,
      log,
      @moonwren.sha256_hex("workload-v1"),
    ) {
    @moonwren.SchedulerReplayCompleted(events) => assert_eq(events, 3)
    @moonwren.SchedulerReplayDiverged(index, _, _) =>
      fail("unexpected divergence at \{index}")
    @moonwren.SchedulerReplayInvalid(message) => fail(message)
  }
  first_scheduler.close()
  second_scheduler.close()
  first_vm.close()
  second_vm.close()
}

///|
test "scheduler replay reports the first observable divergence" {
  let (first_vm, first_scheduler) = replay_test_scheduler("expected")
  let recorder = @moonwren.VmSchedulerRecorder::new(first_scheduler, "digest")
  ignore(recorder.poll())
  let log = recorder.log()
  let (second_vm, second_scheduler) = replay_test_scheduler("different")
  match @moonwren.replay_scheduler_log(second_scheduler, log, "digest") {
    @moonwren.SchedulerReplayDiverged(0, expected, actual) => {
      assert_true(expected.contains("expected"))
      assert_true(actual.contains("different"))
    }
    _ => fail("different host request must diverge")
  }
  match @moonwren.replay_scheduler_log(second_scheduler, log, "wrong") {
    @moonwren.SchedulerReplayInvalid(message) =>
      assert_true(message.contains("digest"))
    _ => fail("wrong workload must be rejected")
  }
  first_scheduler.close()
  second_scheduler.close()
  first_vm.close()
  second_vm.close()
}
