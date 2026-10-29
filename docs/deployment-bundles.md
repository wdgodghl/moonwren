# Signed deployment bundles

MoonWren's `MWDS1` deployment bundle is a deterministic, length-prefixed
transport for a complete application module graph. A manifest records the Wren
target (`0.4`), compiler ABI, entry module, required capabilities, and a
SHA-256 digest plus compiled instruction statistics for every source.

`build_signed_deployment_bundle` parses and compiles every module before asking
the host signer to sign the canonical payload SHA-256. The callback boundary is
intentional: production hosts can use Ed25519, a hardware-backed key, or a
remote signing service without placing secret-key code in the interpreter.

```moonbit
let result = build_signed_deployment_bundle(
  "main",
  [VerifiedModule::new("main", "System.print(42)\n")],
  ["console"],
  "moonwren-0.9",
  "release-2026",
  fn(digest) { signing_service.sign_ed25519(digest) },
)
```

Persist the result with `encode_signed_deployment_bundle`. At the deployment
boundary, call `decode_signed_deployment_bundle` first and then
`verify_signed_deployment_bundle` with a verifier that resolves the recorded
key id. Only construct `deployment_bundle_loader` from a verified result.

The current bytecode instruction graph contains runtime objects and is not
serialized directly. Instead, the portable bundle retains source and
cryptographically binds compiler-cache metadata. A host can reject an ABI
mismatch and rebuild the in-memory bytecode deterministically. This avoids
loading unsafe or target-specific object representations while preserving a
stable deployment artifact.
