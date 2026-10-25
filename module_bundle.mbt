///|
/// One integrity-checked source in an in-memory deployment bundle.
pub(all) struct VerifiedModule {
  name : String
  source : String
  checksum : String
}

///|
pub fn VerifiedModule::new(name : String, source : String) -> VerifiedModule {
  { name, source, checksum: module_checksum(source), }
}

///|
/// Stable FNV-1a checksum used to detect accidental bundle corruption. This is
/// not intended to replace a cryptographic signature at a trust boundary.
pub fn module_checksum(source : String) -> String {
  let mut hash = 2166136261U
  for character in source.to_array() {
    hash = (hash ^ character.to_int().reinterpret_as_uint()) * 16777619U
  }
  hash.to_string(radix=16)
}

///|
fn safe_module_specifier(name : String) -> Bool {
  name.length() > 0 &&
  !name.has_prefix("/") &&
  !name.has_prefix("\\") &&
  !name.contains("..") &&
  !name.contains(":")
}

///|
/// Build a sandboxed loader from a checked source bundle. Absolute paths and
/// traversal segments are rejected before lookup.
pub fn verified_module_loader(
  modules : Array[VerifiedModule],
) -> (String, String) -> ModuleLoadResult {
  fn(_importer : String, specifier : String) {
    if !safe_module_specifier(specifier) {
      return ModuleLoadFailed("unsafe module specifier '{specifier}'")
    }
    let mut found : VerifiedModule? = None
    for entry in modules {
      if entry.name == specifier {
        if found is Some(_) {
          return ModuleLoadFailed("duplicate bundled module '{specifier}'")
        }
        found = Some(entry)
      }
    }
    match found {
      None => ModuleLoadFailed("bundled module '{specifier}' was not found")
      Some(entry) =>
        if module_checksum(entry.source) != entry.checksum {
          ModuleLoadFailed("checksum mismatch for bundled module '{specifier}'")
        } else {
          ModuleLoaded(entry.name, entry.source)
        }
    }
  }
}

///|
/// Content snapshot used by polling file watchers and hot-reload hosts.
pub(all) struct ModuleSnapshot {
  names : Array[String]
  checksums : Array[String]
}

///|
pub fn ModuleSnapshot::from_modules(
  modules : Array[VerifiedModule],
) -> ModuleSnapshot {
  let names : Array[String] = []
  let checksums : Array[String] = []
  for entry in modules {
    names.push(entry.name)
    checksums.push(module_checksum(entry.source))
  }
  { names, checksums, }
}

///|
/// Return added, changed and removed names between two snapshots.
pub fn ModuleSnapshot::changes(
  self : ModuleSnapshot,
  newer : ModuleSnapshot,
) -> Array[String] {
  let changed : Array[String] = []
  for index = 0; index < newer.names.length(); index = index + 1 {
    let name = newer.names[index]
    let mut previous = -1
    for old_index = 0
        old_index < self.names.length()
        old_index = old_index + 1 {
      if self.names[old_index] == name {
        previous = old_index
      }
    }
    if previous < 0 || self.checksums[previous] != newer.checksums[index] {
      changed.push(name)
    }
  }
  for name in self.names {
    let mut remains = false
    for current in newer.names {
      if current == name {
        remains = true
      }
    }
    if !remains {
      changed.push(name)
    }
  }
  changed
}
