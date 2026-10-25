///|
#cfg(target="js")
extern "js" fn install_playground(run_source : (String) -> String) -> Unit =
  #| (runSource) => {
  #|   const run = document.getElementById("run");
  #|   const source = document.getElementById("source");
  #|   const output = document.getElementById("output");
  #|   run.addEventListener("click", () => { output.textContent = runSource(source.value); });
  #|   output.textContent = runSource(source.value);
  #| }

///|
#cfg(target="js")
fn render(source : String) -> String {
  match @moonwren.run_with_limit(source, 1000000) {
    @moonwren.ProgramCompleted(value, output) => {
      let lines : Array[String] = []
      for line in output {
        lines.push(line)
      }
      lines.push("=> " + value.to_text())
      lines.join("\n")
    }
    @moonwren.ProgramFailed(issues, output) => {
      let lines : Array[String] = []
      for line in output {
        lines.push(line)
      }
      for issue in issues {
        lines.push(issue.render("playground"))
      }
      lines.join("\n")
    }
  }
}

///|
#cfg(target="js")
fn main {
  install_playground(render)
}

///|
#cfg(not(target="js"))
fn main {
  ignore(@moonwren.run("null"))
  println("Build this package with --target js and open web/index.html.")
}
