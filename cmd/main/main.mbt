///|
fn demo_source() -> String {
  "var total = 0\n" +
  "for (current in 1..10) {\n" +
  "  total = total + current\n" +
  "}\n" +
  "System.print(total)\n"
}

///|
fn selected_source() -> String {
  let arguments = @env.args()
  if arguments.length() > 1 {
    arguments[arguments.length() - 1]
  } else {
    demo_source()
  }
}

///|
fn main {
  match @moonwren.run(selected_source()) {
    ProgramCompleted(_, output) =>
      for line in output {
        println(line)
      }
    ProgramFailed(diagnostics, output) => {
      for line in output {
        println(line)
      }
      for diagnostic in diagnostics {
        println(diagnostic.render("<source>"))
      }
    }
  }
}
