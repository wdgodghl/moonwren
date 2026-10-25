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

///|
/// Result of decoding a deterministic MoonWren module archive.
pub(all) enum ModuleArchiveResult {
  ModuleArchiveDecoded(Array[VerifiedModule])
  ModuleArchiveFailed(String)
}

///|
fn archive_character_length(value : String) -> Int {
  value.to_array().length()
}

///|
fn archive_read_number(characters : Array[Char], start : Int) -> (Int, Int)? {
  if start < 0 || start >= characters.length() {
    return None
  }
  let mut cursor = start
  let mut value = 0
  let mut digits = 0
  while cursor < characters.length() && characters[cursor].to_int() != 10 {
    let code = characters[cursor].to_int()
    if code < 48 || code > 57 {
      return None
    }
    value = value * 10 + code - 48
    digits = digits + 1
    cursor = cursor + 1
  }
  if digits == 0 || cursor >= characters.length() {
    None
  } else {
    Some((value, cursor + 1))
  }
}

///|
fn archive_take_text(
  characters : Array[Char],
  start : Int,
  count : Int,
) -> (String, Int)? {
  if count < 0 || start < 0 || start + count > characters.length() {
    return None
  }
  let result : Array[Char] = []
  for index = start; index < start + count; index = index + 1 {
    result.push(characters[index])
  }
  Some((String::from_array(result), start + count))
}

///|
/// Encode modules into the deterministic `MWA1` archive format. Lengths count
/// Unicode characters, so sources may contain newlines, NULs and non-ASCII
/// text without escaping or platform-dependent byte conversions.
pub fn encode_module_archive(modules : Array[VerifiedModule]) -> String {
  let mut result = "MWA1\n" + modules.length().to_string() + "\n"
  for entry in modules {
    result = result +
      archive_character_length(entry.name).to_string() +
      "\n" +
      entry.name +
      archive_character_length(entry.source).to_string() +
      "\n" +
      entry.source +
      archive_character_length(entry.checksum).to_string() +
      "\n" +
      entry.checksum
  }
  result
}

///|
/// Decode an `MWA1` archive and reject malformed lengths, unsafe or duplicate
/// module names, trailing data, and checksum mismatches.
pub fn decode_module_archive(archive : String) -> ModuleArchiveResult {
  let characters = archive.to_array()
  let header = ['M', 'W', 'A', '1', '\n']
  if characters.length() < header.length() {
    return ModuleArchiveFailed("module archive header is missing")
  }
  for index = 0; index < header.length(); index = index + 1 {
    if characters[index] != header[index] {
      return ModuleArchiveFailed("unsupported module archive format")
    }
  }
  let (count, after_count) = match archive_read_number(characters, 5) {
    Some(value) => value
    None => return ModuleArchiveFailed("invalid module count")
  }
  let modules : Array[VerifiedModule] = []
  let mut cursor = after_count
  for _entry_index = 0; _entry_index < count; _entry_index = _entry_index + 1 {
    let (name_length, after_name_length) = match
      archive_read_number(characters, cursor) {
      Some(value) => value
      None => return ModuleArchiveFailed("invalid module name length")
    }
    let (name, after_name) = match
      archive_take_text(characters, after_name_length, name_length) {
      Some(value) => value
      None => return ModuleArchiveFailed("truncated module name")
    }
    if !safe_module_specifier(name) {
      return ModuleArchiveFailed("unsafe module name '\{name}'")
    }
    for existing in modules {
      if existing.name == name {
        return ModuleArchiveFailed("duplicate module name '\{name}'")
      }
    }
    let (source_length, after_source_length) = match
      archive_read_number(characters, after_name) {
      Some(value) => value
      None => return ModuleArchiveFailed("invalid source length for '\{name}'")
    }
    let (source, after_source) = match
      archive_take_text(characters, after_source_length, source_length) {
      Some(value) => value
      None => return ModuleArchiveFailed("truncated source for '\{name}'")
    }
    let (checksum_length, after_checksum_length) = match
      archive_read_number(characters, after_source) {
      Some(value) => value
      None =>
        return ModuleArchiveFailed("invalid checksum length for '\{name}'")
    }
    let (checksum, after_checksum) = match
      archive_take_text(characters, after_checksum_length, checksum_length) {
      Some(value) => value
      None => return ModuleArchiveFailed("truncated checksum for '\{name}'")
    }
    if module_checksum(source) != checksum {
      return ModuleArchiveFailed("checksum mismatch for '\{name}'")
    }
    modules.push({ name, source, checksum, })
    cursor = after_checksum
  }
  if cursor != characters.length() {
    ModuleArchiveFailed("unexpected trailing module archive data")
  } else {
    ModuleArchiveDecoded(modules)
  }
}
