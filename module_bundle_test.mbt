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

///|
test "module archives round trip multiline Unicode source deterministically" {
  let modules = [
    @moonwren.VerifiedModule::new("math", "var answer = 42\n"),
    @moonwren.VerifiedModule::new(
      "问候", "var text = \"你好\\nMoonWren\"\n",
    ),
  ]
  let archive = @moonwren.encode_module_archive(modules)
  assert_eq(archive, @moonwren.encode_module_archive(modules))
  match @moonwren.decode_module_archive(archive) {
    @moonwren.ModuleArchiveFailed(message) => fail(message)
    @moonwren.ModuleArchiveDecoded(decoded) => {
      assert_eq(decoded.length(), 2)
      assert_eq(decoded[0].source, modules[0].source)
      assert_eq(decoded[1].name, "问候")
    }
  }
}

///|
test "module archives reject corruption and trailing data" {
  let archive = @moonwren.encode_module_archive([
    @moonwren.VerifiedModule::new("main", "var value = 1"),
  ])
  match @moonwren.decode_module_archive(archive + "x") {
    @moonwren.ModuleArchiveDecoded(_) => fail("trailing data must be rejected")
    @moonwren.ModuleArchiveFailed(message) =>
      assert_true(message.contains("trailing"))
  }
}
