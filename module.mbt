///|
/// Result returned by an embedding application's module loader.
pub(all) enum ModuleLoadResult {
  ModuleLoaded(String, String)
  ModuleLoadFailed(String)
} derive(Eq, Debug)

///|
pub extend ModuleLoadResult with Eq::{equal, not_equal}

///|
pub extend ModuleLoadResult with Debug::{to_repr}

///|
/// Named source used by the in-memory multi-module convenience API.
pub(all) struct ModuleSource {
  name : String
  source : String
} derive(Eq, Debug)

///|
pub extend ModuleSource with Eq::{equal, not_equal}

///|
pub extend ModuleSource with Debug::{to_repr}

///|
pub fn ModuleSource::new(name : String, source : String) -> ModuleSource {
  { name, source, }
}
