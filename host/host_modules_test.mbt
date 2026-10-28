///|
fn missing_host_module(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn host_test_vm(policy : @host.HostAccessPolicy) -> @moonwren.Vm {
  let kit = @host.HostModuleKit::new(policy)
  @moonwren.Vm::new(
    @moonwren.VmLimits::standard(200000),
    kit.loader(missing_host_module),
    kit.foreign_methods(),
    [],
  )
}

///|
test "host modules expose only granted filesystem and environment values" {
  let policy = @host.HostAccessPolicy::new(
    "host/testdata",
    true,
    true,
    1024,
    1024,
    [@host.HostEnvironmentValue::new("MODE", "test")],
  )
  let vm = host_test_vm(policy)
  let source =
    #|import "moon/io" for FileSystem
    #|import "moon/env" for Environment
    #|System.print(FileSystem.readText("input.txt").contains("MoonWren"))
    #|System.print(FileSystem.exists("input.txt"))
    #|System.print(FileSystem.writeText("write_target.txt", "updated\n"))
    #|System.print(Environment.get("MODE"))
    #|System.print(Environment.has("SECRET"))
    #|System.print(Environment.get("SECRET") == null)
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, output) =>
      assert_eq(output, ["true", "true", "true", "test", "false", "true"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  vm.close()
}

///|
test "host filesystem is deny by default" {
  let vm = host_test_vm(@host.HostAccessPolicy::deny_all("host/testdata"))
  let source =
    #|import "moon/io" for FileSystem
    #|FileSystem.readText("input.txt")
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, _) => fail("read should be denied")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("disabled"))
  }
  vm.close()
}

///|
test "host filesystem rejects traversal and byte-limit violations" {
  let policy = @host.HostAccessPolicy::new("host/testdata", true, false, 4, 0, [])
  let traversal_vm = host_test_vm(policy)
  let traversal_source =
    #|import "moon/io" for FileSystem
    #|FileSystem.readText("../../README.md")
  match traversal_vm.interpret("main", traversal_source) {
    @moonwren.ProgramCompleted(_, _) => fail("traversal should be rejected")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("configured root"))
  }
  traversal_vm.close()
  let limit_vm = host_test_vm(policy)
  let limit_source =
    #|import "moon/io" for FileSystem
    #|FileSystem.readText("input.txt")
  match limit_vm.interpret("main", limit_source) {
    @moonwren.ProgramCompleted(_, _) => fail("oversized read should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("byte limit"))
  }
  limit_vm.close()
}

///|
test "host kit does not grant process or network modules" {
  let kit = @host.HostModuleKit::new(
    @host.HostAccessPolicy::deny_all("host/testdata"),
  )
  let loader = kit.loader(missing_host_module)
  match loader("main", "moon/process") {
    @moonwren.ModuleLoaded(_, _) => fail("process module must not be exposed")
    @moonwren.ModuleLoadFailed(_) => ()
  }
  match loader("main", "moon/network") {
    @moonwren.ModuleLoaded(_, _) => fail("network module must not be exposed")
    @moonwren.ModuleLoadFailed(_) => ()
  }
}
