///|
/// Policy for a filesystem-backed module loader.
pub(all) struct FileLoaderConfig {
  root : String
  extension : String
  max_source_characters : Int
}

///|
pub fn FileLoaderConfig::new(
  root : String,
  extension : String,
  max_source_characters : Int,
) -> FileLoaderConfig {
  { root, extension, max_source_characters, }
}

///|
fn canonical(path : String) -> String {
  let value : @path.Path = path
  value.resolve().to_string()
}

///|
fn has_extension(path : String) -> Bool {
  let value : @path.Path = path
  value.extname().length() > 0
}

///|
fn within_root(root : String, candidate : String) -> Bool {
  candidate == root ||
  candidate.has_prefix(root + "/") ||
  candidate.has_prefix(root + "\\")
}

///|
/// Create a loader that canonicalizes every request, confines it below one
/// root, applies a default extension and enforces a source-size limit.
pub fn file_module_loader(
  config : FileLoaderConfig,
) -> (String, String) -> @moonwren.ModuleLoadResult {
  let root = canonical(config.root)
  fn(_importer : String, specifier : String) {
    if specifier.contains("\u0000") {
      return @moonwren.ModuleLoadFailed("module path contains a NUL character")
    }
    let relative = if has_extension(specifier) {
      specifier
    } else {
      specifier + config.extension
    }
    let requested : @path.Path = relative
    if requested.is_absolute() {
      return @moonwren.ModuleLoadFailed("absolute module paths are disabled")
    }
    let root_path : @path.Path = root
    let resolved = root_path.join(requested).resolve().to_string()
    if !within_root(root, resolved) {
      return @moonwren.ModuleLoadFailed(
        "module path escapes configured root: '{specifier}'",
      )
    }
    let source = @fs.read_file_to_string(resolved) catch {
      _ => return @moonwren.ModuleLoadFailed("cannot read module '{specifier}'")
    }
    if source.length() > config.max_source_characters {
      @moonwren.ModuleLoadFailed(
        "module '{specifier}' exceeds source-size limit",
      )
    } else {
      @moonwren.ModuleLoaded(resolved, source)
    }
  }
}
