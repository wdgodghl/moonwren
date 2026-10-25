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

///|
test "filesystem watcher reports only newly observed content" {
  let watcher = @loaders.FileModuleWatcher::new(
    @loaders.FileLoaderConfig::new("loaders/testdata", ".wren", 1000),
    ["answer"],
  )
  match watcher.poll() {
    @loaders.FileWatchFailed(message) => fail(message)
    @loaders.FileWatchReady(changed, modules) => {
      assert_eq(changed, ["answer"])
      assert_eq(modules.length(), 1)
    }
  }
  match watcher.poll() {
    @loaders.FileWatchFailed(message) => fail(message)
    @loaders.FileWatchReady(changed, _) => assert_true(changed.is_empty())
  }
}
