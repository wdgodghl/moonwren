///|
test "sha256 matches published vectors including Unicode UTF-8" {
  assert_eq(
    @moonwren.sha256_hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @moonwren.sha256_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    @moonwren.sha256_hex("月"),
    "1625179badc027f0d0a26df9da3d4ae1be4483cc0a9365e54faab22fbe250055",
  )
}

///|
test "signed deployment bundles compile, canonicalize, and verify" {
  let modules = [
    @moonwren.VerifiedModule::new(
      "main", "import \"math\" for answer\nanswer\n",
    ),
    @moonwren.VerifiedModule::new("math", "var answer = 42\n"),
  ]
  let bundle = match
    @moonwren.build_signed_deployment_bundle(
      "main",
      modules,
      ["timer", "filesystem.read"],
      "moonwren-0.9",
      "release-key",
      fn(digest) { "signed:" + digest },
    ) {
    @moonwren.DeploymentBundleReady(value) => value
    @moonwren.DeploymentBundleFailed(message) => fail(message)
  }
  assert_eq(bundle.manifest.wren_version, "0.4")
  assert_eq(bundle.manifest.capabilities, ["filesystem.read", "timer"])
  assert_eq(bundle.manifest.compiled_modules.length(), 2)
  assert_true(bundle.manifest.compiled_modules[0].instruction_count > 0)
  let encoded = @moonwren.encode_signed_deployment_bundle(bundle)
  let decoded = match @moonwren.decode_signed_deployment_bundle(encoded) {
    @moonwren.DeploymentBundleReady(value) => value
    @moonwren.DeploymentBundleFailed(message) => fail(message)
  }
  assert_eq(decoded.payload_sha256, bundle.payload_sha256)
  assert_eq(decoded.manifest.compiled_modules, bundle.manifest.compiled_modules)
  match
    @moonwren.verify_signed_deployment_bundle(decoded, fn(
      key,
      digest,
      signature,
    ) {
      key == "release-key" && signature == "signed:" + digest
    }) {
    @moonwren.DeploymentBundleReady(_) => ()
    @moonwren.DeploymentBundleFailed(message) => fail(message)
  }
}

///|
test "signed deployment bundles reject tampering and signatures" {
  let bundle = match
    @moonwren.build_signed_deployment_bundle(
      "main",
      [@moonwren.VerifiedModule::new("main", "42\n")],
      [],
      "moonwren-0.9",
      "key",
      fn(digest) { digest },
    ) {
    @moonwren.DeploymentBundleReady(value) => value
    @moonwren.DeploymentBundleFailed(message) => fail(message)
  }
  let tampered = {
    ..bundle,
    modules: [@moonwren.VerifiedModule::new("main", "43\n")],
  }
  match
    @moonwren.verify_signed_deployment_bundle(tampered, fn(_, _, _) { true }) {
    @moonwren.DeploymentBundleReady(_) => fail("tampering must fail")
    @moonwren.DeploymentBundleFailed(message) =>
      assert_true(message.contains("metadata") || message.contains("digest"))
  }
  match
    @moonwren.verify_signed_deployment_bundle(bundle, fn(_, _, _) { false }) {
    @moonwren.DeploymentBundleReady(_) => fail("signature must fail")
    @moonwren.DeploymentBundleFailed(message) =>
      assert_true(message.contains("signature"))
  }
}
