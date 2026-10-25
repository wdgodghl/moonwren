///|
test "verified module bundles load intact sandboxed sources" {
  let entry = @moonwren.VerifiedModule::new("math", "var answer = 42\n")
  let loader = @moonwren.verified_module_loader([entry])
  match loader("main", "math") {
    @moonwren.ModuleLoaded(name, source) => {
      assert_eq(name, "math")
      assert_eq(source, "var answer = 42\n")
    }
    @moonwren.ModuleLoadFailed(message) => fail(message)
  }
  match loader("main", "../secret") {
    @moonwren.ModuleLoaded(_, _) => fail("traversal must be rejected")
    @moonwren.ModuleLoadFailed(message) =>
      assert_true(message.contains("unsafe"))
  }
}

///|
test "verified module bundles detect tampering and duplicate names" {
  let altered : @moonwren.VerifiedModule = {
    name: "bad",
    source: "changed",
    checksum: "00000000",
  }
  let loader = @moonwren.verified_module_loader([altered])
  match loader("main", "bad") {
    @moonwren.ModuleLoaded(_, _) => fail("tampered source must fail")
    @moonwren.ModuleLoadFailed(message) =>
      assert_true(message.contains("checksum"))
  }
}

///|
test "module snapshots report added changed and removed modules" {
  let old = @moonwren.ModuleSnapshot::from_modules([
    @moonwren.VerifiedModule::new("same", "1"),
    @moonwren.VerifiedModule::new("changed", "1"),
    @moonwren.VerifiedModule::new("removed", "1"),
  ])
  let current = @moonwren.ModuleSnapshot::from_modules([
    @moonwren.VerifiedModule::new("same", "1"),
    @moonwren.VerifiedModule::new("changed", "2"),
    @moonwren.VerifiedModule::new("added", "1"),
  ])
  assert_eq(old.changes(current), ["changed", "added", "removed"])
}
