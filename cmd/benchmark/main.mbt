///|
fn procedural_workload() -> String {
  "var total = 0\n" +
  "var n = 0\n" +
  "while (n < 250) { total = total + n\n n = n + 1 }\n" +
  "total\n"
}

///|
fn collection_workload() -> String {
  "var values = []\n" +
  "var n = 0\n" +
  "while (n < 100) { values.add(n * 2)\n n = n + 1 }\n" +
  "values[50] + values.count\n"
}

///|
fn fiber_workload() -> String {
  "var worker = Fiber.new {\n" +
  "  var n = 0\n" +
  "  while (n < 30) { Fiber.yield(n)\n n = n + 1 }\n" +
  "}\n" +
  "while (!worker.isDone) worker.call()\n"
}

///|
fn main {
  let source = procedural_workload()
  let iterations = 40
  let parse_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations * 5; iteration = iteration + 1 {
    ignore(@moonwren.parse_program(source))
  }
  let parse_ms = @bench.monotonic_clock_end(parse_start) / 1000.0
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
  let collections = collection_workload()
  let collections_ast_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    ignore(@moonwren.run_with_limit(collections, 100000))
  }
  let collections_ast_ms = @bench.monotonic_clock_end(collections_ast_start) /
    1000.0
  let collection_program = match @moonwren.compile_bytecode(collections) {
    @moonwren.BytecodeCompiled(value) => value
    @moonwren.BytecodeCompileFailed(issues) => abort(issues[0].message)
  }
  let collections_bytecode_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    ignore(@moonwren.run_bytecode(collection_program, 100000))
  }
  let collections_bytecode_ms = @bench.monotonic_clock_end(
      collections_bytecode_start,
    ) /
    1000.0
  let fiber_start = @bench.monotonic_clock_start()
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    ignore(@moonwren.run_with_limit(fiber_workload(), 100000))
  }
  let fiber_ms = @bench.monotonic_clock_end(fiber_start) / 1000.0
  println("iterations=\{iterations}")
  println("parse_ms=\{parse_ms}")
  println("ast_ms=\{ast_ms}")
  println("bytecode_ms=\{bytecode_ms}")
  println("collections_ast_ms=\{collections_ast_ms}")
  println("collections_bytecode_ms=\{collections_bytecode_ms}")
  println("fiber_ms=\{fiber_ms}")
}
