///|
fn no_optional_test_modules(
  _importer : String,
  name : String,
) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

///|
fn run_optional_test(source : String) -> @moonwren.ProgramRunResult {
  @moonwren.run_with_loader("main", source, 500000, no_optional_test_modules)
}

///|
test "random optional module is deterministic for equal seeds" {
  let source =
    #|import "random" for Random
    #|var left = Random.new(12345)
    #|var right = Random.new(12345)
    #|var equal = true
    #|for (i in 0...100) {
    #|  if (left.int() != right.int()) equal = false
    #|}
    #|System.print(equal)
  match run_optional_test(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["true"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "random optional module supports ranges samples and shuffling" {
  let source =
    #|import "random" for Random
    #|var random = Random.new([1, 2, 3, 4])
    #|var inRange = true
    #|for (i in 0...100) {
    #|  var value = random.float(-2, 3)
    #|  if (value < -2 || value >= 3) inRange = false
    #|}
    #|var values = [1, 2, 3, 4, 5]
    #|var picked = random.sample(values, 3)
    #|random.shuffle(values)
    #|System.print(inRange)
    #|System.print(picked.count)
    #|System.print(values.count)
  match run_optional_test(source) {
    @moonwren.ProgramCompleted(_, output) =>
      assert_eq(output, ["true", "3", "5"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "meta optional module evaluates and compiles in the caller module" {
  let source =
    #|import "meta" for Meta
    #|var value = 40
    #|Meta.eval("value = value + 1")
    #|var expression = Meta.compileExpression("value + 1")
    #|System.print(expression.call())
    #|System.print(Meta.getModuleVariables("main").contains("value"))
  match run_optional_test(source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["42", "true"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
}

///|
test "meta compile failures return null and eval failures are structured" {
  let compile_source =
    #|import "meta" for Meta
    #|System.print(Meta.compileExpression("1 +") == null)
  match run_optional_test(compile_source) {
    @moonwren.ProgramCompleted(_, output) => assert_eq(output, ["true"])
    @moonwren.ProgramFailed(issues, _) => fail(issues[0].message)
  }
  let eval_source =
    #|import "meta" for Meta
    #|Meta.eval("var =")
  match run_optional_test(eval_source) {
    @moonwren.ProgramCompleted(_, _) => fail("invalid eval source should fail")
    @moonwren.ProgramFailed(issues, _) =>
      assert_true(issues[0].message.contains("Could not compile"))
  }
}
