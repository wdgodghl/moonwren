///|
fn main {
  let policy = @host.HostAccessPolicy::new(
    "host/testdata",
    true,
    false,
    4096,
    0,
    [@host.HostEnvironmentValue::new("APP_MODE", "demo")],
  )
  let kit = @host.HostModuleKit::new(policy)
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    kit.loader(fn(_, name) {
      @moonwren.ModuleLoadFailed("missing module \{name}")
    }),
    kit.foreign_methods(),
    [],
  )
  let source =
    #|import "moon/io" for FileSystem
    #|import "moon/env" for Environment
    #|System.print(FileSystem.readText("input.txt"))
    #|System.print("mode: %(Environment.get("APP_MODE"))")
    #|System.print("secret exposed: %(Environment.has("SECRET"))")
  match vm.interpret("main", source) {
    @moonwren.ProgramCompleted(_, output) =>
      for line in output {
        println(line)
      }
    @moonwren.ProgramFailed(issues, _) => println(issues[0].render(source))
  }
  vm.close()
}
