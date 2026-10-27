///|
fn state_test_vm() -> @moonwren.Vm {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    fn(_, name) { @moonwren.ModuleLoadFailed("missing \{name}") },
    [],
    [],
  )
  match
    vm.interpret(
      "main",
      (
        #|var shared = [1, 2]
        #|var state = {"left": shared, "right": shared}
        #|shared.add(shared)
        #|var label = "ready"
        #|var verify = Fn.new {
        #|  return state["left"] == state["right"] && state["left"][2] == state["left"]
        #|}
      ),
    ) {
    @moonwren.ProgramCompleted(_, _) => vm
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
}

///|
test "portable state snapshot preserves cycles and shared identity" {
  let source = state_test_vm()
  let archive = match source.save_state("main", ["state", "label"]) {
    @moonwren.VmStateSaved(archive) => archive
    @moonwren.VmStateSaveFailed(issue) => abort(issue.message)
  }
  let restored = state_test_vm()
  match restored.restore_state(archive) {
    @moonwren.VmStateRestored(count) => assert_eq(count, 2)
    @moonwren.VmStateRestoreFailed(issue) => abort(issue.message)
  }
  let verify = match restored.capture("main", "verify") {
    @moonwren.VmHandleCreated(handle) => handle
    _ => abort("missing verifier")
  }
  match restored.call(verify, []) {
    @moonwren.ProgramCompleted(value, _) =>
      assert_eq(value, @moonwren.Value::bool(true))
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
}

///|
test "portable state snapshot rejects corruption and unsupported closures" {
  let vm = state_test_vm()
  match vm.save_state("main", ["verify"]) {
    @moonwren.VmStateSaveFailed(issue) =>
      assert_eq(issue.code, @moonwren.UnsupportedFeature)
    _ => abort("closure snapshots must be rejected")
  }
  let archive = match vm.save_state("main", ["label"]) {
    @moonwren.VmStateSaved(archive) => archive
    _ => abort("expected state archive")
  }
  match vm.restore_state(archive + "x") {
    @moonwren.VmStateRestoreFailed(issue) =>
      assert_eq(issue.code, @moonwren.UnsupportedFeature)
    _ => abort("corrupted archive must fail")
  }
}
