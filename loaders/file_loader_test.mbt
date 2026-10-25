///|
test "filesystem loader adds extension and confines requests to root" {
  let loader = @loaders.file_module_loader(
    @loaders.FileLoaderConfig::new("loaders/testdata", ".wren", 1000),
  )
  match loader("main", "answer") {
    @moonwren.ModuleLoaded(name, source) => {
      assert_true(name.contains("answer.wren"))
      assert_true(source.contains("42"))
    }
    @moonwren.ModuleLoadFailed(message) => fail(message)
  }
  match loader("main", "../README.md") {
    @moonwren.ModuleLoaded(_, _) => fail("escaping root must fail")
    @moonwren.ModuleLoadFailed(message) =>
      assert_true(message.contains("escapes"))
  }
}

///|
test "filesystem loader enforces source size" {
  let loader = @loaders.file_module_loader(
    @loaders.FileLoaderConfig::new("loaders/testdata", ".wren", 3),
  )
  match loader("main", "answer") {
    @moonwren.ModuleLoaded(_, _) => fail("oversized source must fail")
    @moonwren.ModuleLoadFailed(message) =>
      assert_true(message.contains("source-size"))
  }
}
