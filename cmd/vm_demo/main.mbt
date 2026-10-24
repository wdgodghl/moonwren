///|
fn no_modules(_importer : String, name : String) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn show(result : @moonwren.ProgramRunResult) -> Unit {
  match result {
    @moonwren.ProgramCompleted(value, output) => {
      for line in output {
        println(line)
      }
      println("host received: \{value.to_text()}")
    }
    @moonwren.ProgramFailed(issues, output) => {
      for line in output {
        println(line)
      }
      for issue in issues {
        println(issue.render("<host>"))
      }
    }
  }
}

///|
fn main {
  let vm = @moonwren.Vm::new(
    @moonwren.VmLimits::standard(100000),
    no_modules,
    [],
    [],
  )
  let source = "var count = 40\n" + "var next = Fn.new { count = count + 1 }\n"
  show(vm.interpret("main", source))
  match vm.capture("main", "next") {
    @moonwren.VmHandleFailed(issue) => println(issue.render("main"))
    @moonwren.VmHandleCreated(next) => {
      show(vm.call(next, []))
      show(vm.call(next, []))
      let replacement = "var count = 0\n" +
        "var next = Fn.new { count = count + 2 }\n"
      show(vm.reload_module("main", replacement, ["count"]))
      match vm.capture("main", "next") {
        @moonwren.VmHandleFailed(issue) => println(issue.render("main"))
        @moonwren.VmHandleCreated(reloaded_next) =>
          show(vm.call(reloaded_next, []))
      }
    }
  }
  let stats = vm.collect_garbage()
  println("reclaimed instances: \{stats.reclaimed_instances}")
  vm.close()
}
