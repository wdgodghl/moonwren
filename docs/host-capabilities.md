# Capability-limited host modules

MoonWren's core runtime performs no filesystem, environment, process, or
network access. Applications may opt into the separate
`wdgodghl/moonwren/host` package when a script needs narrowly scoped host data.

`HostAccessPolicy` starts from explicit capabilities:

- `moon/io` reads and writes only relative paths that resolve below one root;
- reads and writes have independent switches and UTF-8 byte limits;
- `moon/env` sees only name/value pairs supplied by the embedder;
- process execution and networking are not provided;
- every VM receives its own policy and bindings.

The environment API deliberately does not read the ambient process
environment. This makes it impossible to expose an undeclared token merely by
guessing its name. The host decides which values are safe to copy into the
policy.

```moonbit
let policy = HostAccessPolicy::new(
  "workspace/data",
  true,  // read
  false, // write
  1024 * 1024,
  0,
  [HostEnvironmentValue::new("APP_MODE", "production")],
)
let kit = HostModuleKit::new(policy)
let vm = Vm::new(
  limits,
  kit.loader(application_loader),
  kit.foreign_methods(),
  [],
)
```

The synchronous `moonbitlang/x/fs` API normalizes `.` and `..` but does not
expose a portable real-path/symlink inspection operation. The configured root
must therefore be owned by the embedding application and must not contain
attacker-created symbolic links. For mutually untrusted local users, place the
process in an operating-system sandbox as well.

Timer and task execution stay in the root package's `VmScheduler`. This keeps
filesystem callbacks synchronous and makes asynchronous I/O an explicit host
request handled by the application's event loop.
