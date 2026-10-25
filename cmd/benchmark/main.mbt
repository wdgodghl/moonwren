///|
fn workload() -> String {
  "var total = 0\n" +
  "var n = 0\n" +
  "while (n < 250) { total = total + n\n n = n + 1 }\n" +
  "total\n"
}

///|
fn main {
  let source = workload()
  let iterations = 40
  let ast_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    ignore(@moonwren.run_with_limit(source, 100000))
  }
  let ast_ms = @bench.monotonic_clock_end(ast_start) / 1000.0
  let program = match @moonwren.compile_bytecode(source) {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => abort(issues[0].message)
  }
  let bytecode_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    ignore(@moonwren.run_bytecode(program, 100000))
  }
  let bytecode_ms = @bench.monotonic_clock_end(bytecode_start) / 1000.0
  println("iterations=\{iterations}")
  println("ast_ms=\{ast_ms}")
  println("bytecode_ms=\{bytecode_ms}")
}
