///|
/// Cryptographic SHA-256 digest encoded as lowercase hexadecimal. Deployment
/// bundles use UTF-8 bytes so the result is stable across native and Wasm
/// targets.
pub fn sha256_hex(text : String) -> String {
  let source = @utf8.encode(text)
  let bytes = source.to_array()
  let bit_length = source.length().to_uint64() * 8UL
  bytes.push(b'\x80')
  while bytes.length() % 64 != 56 {
    bytes.push(b'\x00')
  }
  for shift = 56; shift >= 0; shift = shift - 8 {
    bytes.push((bit_length >> shift).to_byte())
  }
  let state : Array[UInt] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let constants : Array[UInt] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  for chunk = 0; chunk < bytes.length(); chunk = chunk + 64 {
    let words = Array::make(64, 0U)
    for index = 0; index < 16; index = index + 1 {
      let offset = chunk + index * 4
      words[index] = (bytes[offset].to_uint() << 24) |
        (bytes[offset + 1].to_uint() << 16) |
        (bytes[offset + 2].to_uint() << 8) |
        bytes[offset + 3].to_uint()
    }
    for index = 16; index < 64; index = index + 1 {
      let previous = words[index - 15]
      let s0 = rotate_right(previous, 7) ^
        rotate_right(previous, 18) ^
        (previous >> 3)
      let prior = words[index - 2]
      let s1 = rotate_right(prior, 17) ^ rotate_right(prior, 19) ^ (prior >> 10)
      words[index] = words[index - 16] + s0 + words[index - 7] + s1
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for index = 0; index < 64; index = index + 1 {
      let sum1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25)
      let choose = (e & f) ^ (e.lnot() & g)
      let temporary1 = h + sum1 + choose + constants[index] + words[index]
      let sum0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temporary2 = sum0 + majority
      h = g
      g = f
      f = e
      e = d + temporary1
      d = c
      c = b
      b = a
      a = temporary1 + temporary2
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
    state[4] = state[4] + e
    state[5] = state[5] + f
    state[6] = state[6] + g
    state[7] = state[7] + h
  }
  let mut digest = ""
  for word in state {
    let hex = word.to_string(radix=16)
    let mut padding = hex.length()
    while padding < 8 {
      digest = digest + "0"
      padding = padding + 1
    }
    digest = digest + hex
  }
  digest
}

///|
fn rotate_right(value : UInt, count : Int) -> UInt {
  (value >> count) | (value << (32 - count))
}

///|
/// Metadata for one source that was validated by the hybrid compiler before
/// packaging. It deliberately describes, rather than serializes, the current
/// in-memory instruction format so bundles remain portable across targets.
pub(all) struct CompiledModuleMetadata {
  name : String
  source_sha256 : String
  instruction_count : Int
  semantic_instruction_count : Int
} derive(Eq, Debug)

///|
pub extend CompiledModuleMetadata with Eq::{equal, not_equal}

///|
pub extend CompiledModuleMetadata with Debug::{to_repr}

///|
pub(all) struct DeploymentManifest {
  format_version : Int
  wren_version : String
  compiler_abi : String
  entry_module : String
  capabilities : Array[String]
  compiled_modules : Array[CompiledModuleMetadata]
}

///|
pub(all) struct SignedDeploymentBundle {
  manifest : DeploymentManifest
  modules : Array[VerifiedModule]
  payload_sha256 : String
  key_id : String
  signature : String
}

///|
pub(all) enum DeploymentBundleResult {
  DeploymentBundleReady(SignedDeploymentBundle)
  DeploymentBundleFailed(String)
}

///|
fn deployment_read_text(
  characters : Array[Char],
  start : Int,
) -> (String, Int)? {
  let (length, after_length) = match archive_read_number(characters, start) {
    Some(value) => value
    None => return None
  }
  archive_take_text(characters, after_length, length)
}

///|
fn sorted_unique_strings(values : Array[String]) -> Array[String]? {
  let result : Array[String] = []
  for value in values {
    if value.length() == 0 {
      return None
    }
    let mut index = 0
    while index < result.length() && result[index].lexical_compare(value) < 0 {
      index = index + 1
    }
    if index < result.length() && result[index] == value {
      return None
    }
    result.insert(index, value)
  }
  Some(result)
}

///|
fn deployment_manifest_text(manifest : DeploymentManifest) -> String {
  let mut text = "MWD1\n" +
    manifest.format_version.to_string() +
    "\n" +
    manifest.wren_version.length().to_string() +
    "\n" +
    manifest.wren_version +
    manifest.compiler_abi.length().to_string() +
    "\n" +
    manifest.compiler_abi +
    manifest.entry_module.length().to_string() +
    "\n" +
    manifest.entry_module +
    manifest.capabilities.length().to_string() +
    "\n"
  for capability in manifest.capabilities {
    text = text + capability.length().to_string() + "\n" + capability
  }
  text = text + manifest.compiled_modules.length().to_string() + "\n"
  for entry in manifest.compiled_modules {
    text = text +
      entry.name.length().to_string() +
      "\n" +
      entry.name +
      entry.source_sha256.length().to_string() +
      "\n" +
      entry.source_sha256 +
      entry.instruction_count.to_string() +
      "\n" +
      entry.semantic_instruction_count.to_string() +
      "\n"
  }
  text
}

///|
fn deployment_unsigned_payload(
  manifest : DeploymentManifest,
  modules : Array[VerifiedModule],
) -> String {
  let manifest_text = deployment_manifest_text(manifest)
  let archive = encode_module_archive(modules)
  manifest_text.length().to_string() +
  "\n" +
  manifest_text +
  archive.length().to_string() +
  "\n" +
  archive
}

///|
fn decode_deployment_manifest(text : String) -> DeploymentManifest? {
  let characters = text.to_array()
  let header = ['M', 'W', 'D', '1', '\n']
  if characters.length() < header.length() {
    return None
  }
  for index = 0; index < header.length(); index = index + 1 {
    if characters[index] != header[index] {
      return None
    }
  }
  let (format_version, after_version) = match
    archive_read_number(characters, header.length()) {
    Some(value) => value
    None => return None
  }
  let (wren_version, after_wren) = match
    deployment_read_text(characters, after_version) {
    Some(value) => value
    None => return None
  }
  let (compiler_abi, after_abi) = match
    deployment_read_text(characters, after_wren) {
    Some(value) => value
    None => return None
  }
  let (entry_module, after_entry) = match
    deployment_read_text(characters, after_abi) {
    Some(value) => value
    None => return None
  }
  let (capability_count, after_capability_count) = match
    archive_read_number(characters, after_entry) {
    Some(value) => value
    None => return None
  }
  let capabilities : Array[String] = []
  let mut cursor = after_capability_count
  for _index = 0; _index < capability_count; _index = _index + 1 {
    let (capability, next) = match deployment_read_text(characters, cursor) {
      Some(value) => value
      None => return None
    }
    capabilities.push(capability)
    cursor = next
  }
  let (module_count, after_module_count) = match
    archive_read_number(characters, cursor) {
    Some(value) => value
    None => return None
  }
  cursor = after_module_count
  let compiled_modules : Array[CompiledModuleMetadata] = []
  for _index = 0; _index < module_count; _index = _index + 1 {
    let (name, after_name) = match deployment_read_text(characters, cursor) {
      Some(value) => value
      None => return None
    }
    let (digest, after_digest) = match
      deployment_read_text(characters, after_name) {
      Some(value) => value
      None => return None
    }
    let (instruction_count, after_instruction_count) = match
      archive_read_number(characters, after_digest) {
      Some(value) => value
      None => return None
    }
    let (semantic_count, next) = match
      archive_read_number(characters, after_instruction_count) {
      Some(value) => value
      None => return None
    }
    compiled_modules.push({
      name,
      source_sha256: digest,
      instruction_count,
      semantic_instruction_count: semantic_count,
    })
    cursor = next
  }
  if cursor != characters.length() {
    return None
  }
  Some({
    format_version,
    wren_version,
    compiler_abi,
    entry_module,
    capabilities,
    compiled_modules,
  })
}

///|
/// Encode a signed bundle to the deterministic MWDS1 transport format.
pub fn encode_signed_deployment_bundle(
  bundle : SignedDeploymentBundle,
) -> String {
  let unsigned = deployment_unsigned_payload(bundle.manifest, bundle.modules)
  "MWDS1\n" +
  unsigned.length().to_string() +
  "\n" +
  unsigned +
  bundle.payload_sha256.length().to_string() +
  "\n" +
  bundle.payload_sha256 +
  bundle.key_id.length().to_string() +
  "\n" +
  bundle.key_id +
  bundle.signature.length().to_string() +
  "\n" +
  bundle.signature
}

///|
/// Decode and integrity-check MWDS1. Signature trust is intentionally a
/// separate verification step so the host selects keys.
pub fn decode_signed_deployment_bundle(
  encoded : String,
) -> DeploymentBundleResult {
  let characters = encoded.to_array()
  let header = ['M', 'W', 'D', 'S', '1', '\n']
  if characters.length() < header.length() {
    return DeploymentBundleFailed("signed bundle header is missing")
  }
  for index = 0; index < header.length(); index = index + 1 {
    if characters[index] != header[index] {
      return DeploymentBundleFailed("unsupported signed bundle format")
    }
  }
  let (unsigned, after_unsigned) = match
    deployment_read_text(characters, header.length()) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid signed bundle payload")
  }
  let (payload_digest, after_digest) = match
    deployment_read_text(characters, after_unsigned) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid signed bundle digest")
  }
  let (key_id, after_key) = match
    deployment_read_text(characters, after_digest) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid signed bundle key id")
  }
  let (signature, after_signature) = match
    deployment_read_text(characters, after_key) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid signed bundle signature")
  }
  if after_signature != characters.length() {
    return DeploymentBundleFailed("unexpected trailing signed bundle data")
  }
  if sha256_hex(unsigned) != payload_digest {
    return DeploymentBundleFailed("signed bundle payload digest mismatch")
  }
  let unsigned_characters = unsigned.to_array()
  let (manifest_text, after_manifest) = match
    deployment_read_text(unsigned_characters, 0) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid deployment manifest")
  }
  let (archive, after_archive) = match
    deployment_read_text(unsigned_characters, after_manifest) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid deployment module archive")
  }
  if after_archive != unsigned_characters.length() {
    return DeploymentBundleFailed("unexpected deployment payload data")
  }
  let manifest = match decode_deployment_manifest(manifest_text) {
    Some(value) => value
    None => return DeploymentBundleFailed("invalid deployment manifest")
  }
  let modules = match decode_module_archive(archive) {
    ModuleArchiveDecoded(value) => value
    ModuleArchiveFailed(message) => return DeploymentBundleFailed(message)
  }
  DeploymentBundleReady({
    manifest,
    modules,
    payload_sha256: payload_digest,
    key_id,
    signature,
  })
}

///|
/// Validate every module with the compiler, canonicalize capabilities, and
/// create a signed deployment bundle. `signer` receives the canonical payload
/// SHA-256 and may use Ed25519, a hardware key, or a remote signing service.
pub fn build_signed_deployment_bundle(
  entry_module : String,
  modules : Array[VerifiedModule],
  capabilities : Array[String],
  compiler_abi : String,
  key_id : String,
  signer : (String) -> String,
) -> DeploymentBundleResult {
  if !safe_module_specifier(entry_module) {
    return DeploymentBundleFailed("unsafe entry module")
  }
  if compiler_abi.length() == 0 || key_id.length() == 0 {
    return DeploymentBundleFailed(
      "compiler ABI and signing key id are required",
    )
  }
  let canonical_capabilities = match sorted_unique_strings(capabilities) {
    Some(value) => value
    None =>
      return DeploymentBundleFailed(
        "capabilities must be non-empty and may not contain duplicates",
      )
  }
  let metadata : Array[CompiledModuleMetadata] = []
  let mut found_entry = false
  for entry in modules {
    if entry.name == entry_module {
      found_entry = true
    }
    if module_checksum(entry.source) != entry.checksum {
      return DeploymentBundleFailed("checksum mismatch for '\{entry.name}'")
    }
    let program = match compile_module_bytecode(entry.name, entry.source) {
      BytecodeCompiled(value) => value
      BytecodeCompileFailed(issues) =>
        return DeploymentBundleFailed(
          "module '\{entry.name}' does not compile: \{issues[0].message}",
        )
    }
    let mut semantic_count = 0
    for instruction in program.instructions {
      match instruction.op {
        EvaluateSemantic(_) | ExecuteSemantic(_) =>
          semantic_count = semantic_count + 1
        _ => ()
      }
    }
    metadata.push({
      name: entry.name,
      source_sha256: sha256_hex(entry.source),
      instruction_count: program.instructions.length(),
      semantic_instruction_count: semantic_count,
    })
  }
  if !found_entry {
    return DeploymentBundleFailed("entry module '\{entry_module}' is missing")
  }
  let manifest = {
    format_version: 1,
    wren_version: "0.4",
    compiler_abi,
    entry_module,
    capabilities: canonical_capabilities,
    compiled_modules: metadata,
  }
  let digest = sha256_hex(deployment_unsigned_payload(manifest, modules))
  DeploymentBundleReady({
    manifest,
    modules,
    payload_sha256: digest,
    key_id,
    signature: signer(digest),
  })
}

///|
/// Verify module checksums, compiler metadata, canonical payload digest, and
/// the external signature before returning a loader.
pub fn verify_signed_deployment_bundle(
  bundle : SignedDeploymentBundle,
  verifier : (String, String, String) -> Bool,
) -> DeploymentBundleResult {
  let rebuilt = match
    build_signed_deployment_bundle(
      bundle.manifest.entry_module,
      bundle.modules,
      bundle.manifest.capabilities,
      bundle.manifest.compiler_abi,
      bundle.key_id,
      fn(_) { bundle.signature },
    ) {
    DeploymentBundleReady(value) => value
    DeploymentBundleFailed(message) => return DeploymentBundleFailed(message)
  }
  if rebuilt.manifest.compiled_modules != bundle.manifest.compiled_modules {
    return DeploymentBundleFailed("compiled module metadata mismatch")
  }
  if rebuilt.payload_sha256 != bundle.payload_sha256 {
    return DeploymentBundleFailed("deployment payload digest mismatch")
  }
  if !verifier(bundle.key_id, bundle.payload_sha256, bundle.signature) {
    return DeploymentBundleFailed("deployment signature was rejected")
  }
  DeploymentBundleReady(bundle)
}

///|
pub fn deployment_bundle_loader(
  bundle : SignedDeploymentBundle,
) -> (String, String) -> ModuleLoadResult {
  verified_module_loader(bundle.modules)
}
