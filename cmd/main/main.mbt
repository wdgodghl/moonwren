///|
fn demo_source() -> String {
  "var current = 1\n" +
  "var total = 0\n" +
  "while (current <= 10) {\n" +
  "  total = total + current\n" +
  "  current = current + 1\n" +
  "}\n" +
  "total\n"
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
    ProgramCompleted(value) => println(value.to_text())
    ProgramFailed(diagnostics) =>
      for diagnostic in diagnostics {
        println(diagnostic.render("<source>"))
      }
  }
}
