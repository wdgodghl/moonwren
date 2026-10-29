# Atomic multi-module hot reload

`reload_modules` replaces a batch of `ModuleSource` values in one transaction.
The candidate graph is parsed and ordered by imports; duplicate replacements
and dependency cycles fail before commit. State-owning modules initialize
first, selected globals are restored, and dependent replacements and retained
roots then initialize against the migrated state.

`ReloadStateSelection` uses the existing portable `MWS1` format, so null,
Boolean, number, Range, valid and raw String, List, and Map values migrate with
shared identity and cycles intact. Functions, classes, instances, Fibers, and
foreign handles are intentionally not serialized. New code should recreate
those resources from migrated data.

`reload_modules_with_migration` passes each `ReloadStateArchive` through a host
callback before restore. The callback can reject an unsupported schema or
return a transformed `MWS1` archive produced by an application migration tool.
If parsing, initialization, migration, restore, a dependent root, cancellation,
or a resource limit fails, the candidate is finalized and discarded. Sources,
state, generation, and existing handles in the active VM remain unchanged.

On success, old foreign instances are finalized, all old handles are
invalidated, the generation advances once, and the complete candidate graph is
committed. The original `reload_module` API remains available for simple
single-module primitive migration.
