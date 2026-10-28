///|
/// One explicit environment value exposed to Wren. Values are supplied by the
/// embedder rather than read from the ambient process, preventing accidental
/// disclosure of secrets outside the allowlist.
pub(all) struct HostEnvironmentValue {
  name : String
  value : String
}

///|
pub fn HostEnvironmentValue::new(
  name : String,
  value : String,
) -> HostEnvironmentValue {
  { name, value, }
}

///|
/// Capabilities granted to the `moon/io` and `moon/env` host modules.
pub(all) struct HostAccessPolicy {
  root : String
  allow_read : Bool
  allow_write : Bool
  max_read_bytes : Int
  max_write_bytes : Int
  environment : Array[HostEnvironmentValue]
}

///|
pub fn HostAccessPolicy::new(
  root : String,
  allow_read : Bool,
  allow_write : Bool,
  max_read_bytes : Int,
  max_write_bytes : Int,
  environment : Array[HostEnvironmentValue],
) -> HostAccessPolicy {
  {
    root,
    allow_read,
    allow_write,
    max_read_bytes: if max_read_bytes >= 0 {
      max_read_bytes
    } else {
      0
    },
    max_write_bytes: if max_write_bytes >= 0 {
      max_write_bytes
    } else {
      0
    },
    environment: environment.copy(),
  }
}

///|
/// A deny-by-default policy rooted at `root`.
pub fn HostAccessPolicy::deny_all(root : String) -> HostAccessPolicy {
  HostAccessPolicy::new(root, false, false, 0, 0, [])
}

///|
/// Ready-to-install host modules and their foreign bindings.
pub struct HostModuleKit {
  policy : HostAccessPolicy
  methods : Array[@moonwren.ForeignMethodBinding]
}

///|
let host_io_source =
  #|class FileSystem {
  #|  foreign static readText(path)
  #|  foreign static writeText(path, text)
  #|  foreign static exists(path)
  #|}

///|
let host_environment_source =
  #|class Environment {
  #|  foreign static get(name)
  #|  foreign static has(name)
  #|}

///|
fn canonical(path : String) -> String {
  let value : @path.Path = path
  value.resolve().to_string()
}

///|
fn within_root(root : String, candidate : String) -> Bool {
  candidate == root ||
  candidate.has_prefix(root + "/") ||
  candidate.has_prefix(root + "\\")
}

///|
fn resolve_host_path(root : String, requested : String) -> String? {
  if requested.is_empty() || requested.contains("\u0000") {
    return None
  }
  let relative : @path.Path = requested
  if relative.is_absolute() {
    return None
  }
  let root_path : @path.Path = root
  let resolved = root_path.join(relative).resolve().to_string()
  if within_root(root, resolved) {
    Some(resolved)
  } else {
    None
  }
}

///|
fn utf8_byte_length(text : String) -> Int {
  let mut bytes = 0
  for character in text {
    let code = character.to_int()
    let width = if code <= 0x7f {
      1
    } else if code <= 0x7ff {
      2
    } else if code <= 0xffff {
      3
    } else {
      4
    }
    bytes = bytes + width
  }
  bytes
}

///|
fn string_argument(
  arguments : Array[@moonwren.Value],
  index : Int,
  label : String,
) -> Result[String, String] {
  if index < 0 || index >= arguments.length() {
    return Err("missing \{label}")
  }
  match arguments[index].as_string() {
    @moonwren.ValueConverted(value) => Ok(value)
    @moonwren.ValueConversionFailed(_, received) =>
      Err("\{label} must be a String, received \{received}")
  }
}

///|
fn host_environment_lookup(policy : HostAccessPolicy, name : String) -> String? {
  for entry in policy.environment {
    if entry.name == name {
      return Some(entry.value)
    }
  }
  None
}

///|
fn host_read_binding(
  policy : HostAccessPolicy,
) -> @moonwren.ForeignMethodBinding {
  @moonwren.ForeignMethodBinding::new(
    "moon/io",
    "FileSystem",
    true,
    "readText(_)",
    fn(_, arguments) {
      if !policy.allow_read {
        return @moonwren.ForeignCallFailed(
          "filesystem read capability is disabled",
        )
      }
      let requested = match string_argument(arguments, 0, "path") {
        Ok(value) => value
        Err(message) => return @moonwren.ForeignCallFailed(message)
      }
      let resolved = match
        resolve_host_path(canonical(policy.root), requested) {
        Some(value) => value
        None =>
          return @moonwren.ForeignCallFailed(
            "path must remain below the configured root",
          )
      }
      let content = @fs.read_file_to_string(resolved) catch {
        _ => return @moonwren.ForeignCallFailed("file cannot be read")
      }
      if utf8_byte_length(content) > policy.max_read_bytes {
        return @moonwren.ForeignCallFailed("file exceeds the read byte limit")
      }
      @moonwren.ForeignCallSucceeded(@moonwren.Value::string(content))
    },
  )
}

///|
fn host_write_binding(
  policy : HostAccessPolicy,
) -> @moonwren.ForeignMethodBinding {
  @moonwren.ForeignMethodBinding::new(
    "moon/io",
    "FileSystem",
    true,
    "writeText(_,_)",
    fn(_, arguments) {
      if !policy.allow_write {
        return @moonwren.ForeignCallFailed(
          "filesystem write capability is disabled",
        )
      }
      let requested = match string_argument(arguments, 0, "path") {
        Ok(value) => value
        Err(message) => return @moonwren.ForeignCallFailed(message)
      }
      let content = match string_argument(arguments, 1, "text") {
        Ok(value) => value
        Err(message) => return @moonwren.ForeignCallFailed(message)
      }
      if utf8_byte_length(content) > policy.max_write_bytes {
        return @moonwren.ForeignCallFailed("text exceeds the write byte limit")
      }
      let resolved = match
        resolve_host_path(canonical(policy.root), requested) {
        Some(value) => value
        None =>
          return @moonwren.ForeignCallFailed(
            "path must remain below the configured root",
          )
      }
      @fs.write_string_to_file(resolved, content) catch {
        _ => return @moonwren.ForeignCallFailed("file cannot be written")
      }
      @moonwren.ForeignCallSucceeded(@moonwren.Value::bool(true))
    },
  )
}

///|
fn host_exists_binding(
  policy : HostAccessPolicy,
) -> @moonwren.ForeignMethodBinding {
  @moonwren.ForeignMethodBinding::new(
    "moon/io",
    "FileSystem",
    true,
    "exists(_)",
    fn(_, arguments) {
      if !policy.allow_read {
        return @moonwren.ForeignCallFailed(
          "filesystem read capability is disabled",
        )
      }
      let requested = match string_argument(arguments, 0, "path") {
        Ok(value) => value
        Err(message) => return @moonwren.ForeignCallFailed(message)
      }
      let resolved = match
        resolve_host_path(canonical(policy.root), requested) {
        Some(value) => value
        None =>
          return @moonwren.ForeignCallFailed(
            "path must remain below the configured root",
          )
      }
      let exists = @fs.is_file(resolved) catch { _ => false }
      @moonwren.ForeignCallSucceeded(@moonwren.Value::bool(exists))
    },
  )
}

///|
fn host_environment_binding(
  policy : HostAccessPolicy,
  signature : String,
) -> @moonwren.ForeignMethodBinding {
  @moonwren.ForeignMethodBinding::new(
    "moon/env",
    "Environment",
    true,
    signature,
    fn(_, arguments) {
      let name = match string_argument(arguments, 0, "environment name") {
        Ok(value) => value
        Err(message) => return @moonwren.ForeignCallFailed(message)
      }
      match host_environment_lookup(policy, name) {
        Some(value) =>
          if signature == "has(_)" {
            @moonwren.ForeignCallSucceeded(@moonwren.Value::bool(true))
          } else {
            @moonwren.ForeignCallSucceeded(@moonwren.Value::string(value))
          }
        None =>
          if signature == "has(_)" {
            @moonwren.ForeignCallSucceeded(@moonwren.Value::bool(false))
          } else {
            @moonwren.ForeignCallSucceeded(@moonwren.Value::null())
          }
      }
    },
  )
}

///|
pub fn HostModuleKit::new(policy : HostAccessPolicy) -> HostModuleKit {
  let methods = [
    host_read_binding(policy),
    host_write_binding(policy),
    host_exists_binding(policy),
    host_environment_binding(policy, "get(_)"),
    host_environment_binding(policy, "has(_)"),
  ]
  { policy, methods, }
}

///|
/// Return a copy of the foreign bindings to pass to `Vm::new`.
pub fn HostModuleKit::foreign_methods(
  self : HostModuleKit,
) -> Array[@moonwren.ForeignMethodBinding] {
  self.methods.copy()
}

///|
/// Serve the safe host modules and delegate all other names to `fallback`.
pub fn HostModuleKit::loader(
  self : HostModuleKit,
  fallback : (String, String) -> @moonwren.ModuleLoadResult,
) -> (String, String) -> @moonwren.ModuleLoadResult {
  ignore(self.policy.root)
  fn(importer : String, specifier : String) {
    match specifier {
      "moon/io" => @moonwren.ModuleLoaded("moon/io", host_io_source)
      "moon/env" => @moonwren.ModuleLoaded("moon/env", host_environment_source)
      _ => fallback(importer, specifier)
    }
  }
}
