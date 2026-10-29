# MoonWren

MoonWren is a Wren 0.4.0-compatible scripting language implementation written in
MoonBit. It is designed as an embeddable interpreter with a small public API, a
standalone command-line runner, and behavior-focused compatibility tests.

The project is under active development. The current milestone covers source
locations, lexical analysis, primitive expressions, variables, lexical block
scope, assignment, conditionals, `while` loops, protocol-based `for` loops,
method and getter calls, captured program output, the core class model,
universal `toString`, range metadata getters, multiline functions with lexical closures,
early `return`, classes, constructors, instances, fields, methods, getters, and
`this`, inheritance, method overriding, `super`, class relationship checks,
static members, and structured `break`/`continue` control flow. Core values
include mutable List and Map collections, Unicode-aware String operations,
negative indexes, range slices, MapEntry iteration, eager sequence aggregations,
and composable lazy `map`/`where`/`skip`/`take` pipelines. Named modules,
explicit imports, loader callbacks, module caching,
cross-module stack traces, multi-file CLI execution, cooperative Fiber values,
host-bound foreign methods, and host-backed foreign classes are also available.
Fibers preserve block and loop state across suspension and can suspend through
functions, methods, callbacks, constructors, and imported modules. Runtime
class and method attributes, raw strings, cyclic modules, and the complete
32-bit numeric operator surface are supported as well. A persistent embedding
VM retains script state across host calls and provides transactional module
reload, strong host handles, configurable resource limits, host cancellation,
and explicit full-heap reachability collection. An optional stack-bytecode
backend, instruction profiler/trace, transactional REPL session, verified
module bundles, sandboxed filesystem loader, and browser playground support
runtime development and production embedding without replacing the compatible
tree-walking execution path. Resumable host tasks, live statement debugging,
and portable cyclic state snapshots cover long-running service and tool hosts.
The official Wren 0.4 `random` and `meta` optional modules are built in and do
not require a host loader.

## Installation

Add the published package to a MoonBit project:

```text
moon add wdgodghl/moonwren@0.8.0
```

Then import `wdgodghl/moonwren` from the consuming package's `moon.pkg` and use
the library as `@moonwren`. The optional root-confined filesystem loader is in
`wdgodghl/moonwren/loaders`; capability-limited script I/O is in
`wdgodghl/moonwren/host`.

## Goals

- implement the language runtime primarily in MoonBit;
- keep the interpreter portable across MoonBit targets;
- provide useful diagnostics with source locations;
- make embedding scripts straightforward through a small API;
- track compatibility explicitly instead of silently accepting unsupported
  syntax.

The compatibility endpoint is the official Wren `0.4.0` release at tag commit
`4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb`. It includes byte-accurate String
behavior (including invalid UTF-8) and Fiber suspension through arbitrary Wren
calls and callbacks. The precise definition of done, exclusions, and official
input/output comparison cases are recorded in
[`docs/wren-0.4-conformance.md`](docs/wren-0.4-conformance.md).

## Optional Wren modules

`random` implements the Wren 0.4 `Random` API, including deterministic numeric
and sequence seeds, uniform numbers, sampling, and in-place shuffling. `meta`
compiles or evaluates source in the importing module and can enumerate its
visible variables:

```wren
import "random" for Random
import "meta" for Meta

var random = Random.new(2026)
System.print(random.sample(["moon", "wren", "bit"]))
System.print(Meta.compileExpression("20 + 22").call())
```

## Development

The project requires MoonBit `0.10.14` or newer.

```text
moon check
moon test
moon run cmd/main
moon run cmd/runtime_tools_demo
moon run cmd/benchmark --target native
./tools/build-web-demo.ps1
./tools/check-conformance.ps1
./tools/check-official-suite.ps1 -WrenRoot /path/to/wren-0.4.0
```

Running the command without arguments executes the bundled summation example
and prints `55`. Use `--eval` to execute a source string directly:

```text
moon run cmd/main -- --eval "var value = 40\nSystem.print(value + 2)"
```

Functions are values and capture surrounding variables by reference:

```text
moon run cmd/main -- --eval "var count = 0\nvar next = Fn.new { count = count + 1 }\nSystem.print(next.call())\nSystem.print(next.call())"
```

Function bodies may contain declarations and control flow. A `return` exits
through nested blocks and loops, while a bare `return` produces `null`:

```wren
var makeCounter = Fn.new {
  var count = 0
  return Fn.new {
    count = count + 1
    return count
  }
}

var counter = makeCounter.call()
System.print(counter.call()) // 1
System.print(counter.call()) // 2
```

Classes combine persistent instance fields with constructor, method, and getter
dispatch:

```wren
class Point {
  construct new(x, y) {
    _x = x
    _y = y
  }

  move(dx, dy) {
    _x = _x + dx
    _y = _y + dy
  }

  sum { return _x + _y }
}

var point = Point.new(10, 20)
point.move(5, 7)
System.print(point.sum) // 42
```

The complete version is available in
[`examples/classes.wren`](examples/classes.wren).

Subclass lookup supports inherited methods and getters, explicit superclass
constructor calls, overriding, and `super` dispatch:

```wren
class NamedPoint is Point {
  construct new(x, y) { super(x, y) }

  sum {
    return super.sum + 2
  }
}

var point = NamedPoint.new(19, 21)
System.print(point.sum)       // 42
System.print(point is Point)  // true
```

See [`examples/inheritance.wren`](examples/inheritance.wren) for a complete
multi-level example.

Static methods and getters share class-owned `__fields` and support dynamic
`this` plus declaring-class `super` dispatch. As in Wren 0.4.0, static methods
are not inherited by subclasses.
See [`examples/static_members.wren`](examples/static_members.wren).

Both `while` and range `for` loops support `break` and `continue`. Loop control
can cross nested blocks and conditionals, but a called function or method cannot
accidentally break or continue its caller's loop. See
[`examples/loop_control.wren`](examples/loop_control.wren).

Lists and maps are mutable reference values. Lists support positive and negative
indexes, range slices, construction and filling, `add`, `addAll`, `insert`,
`remove`, `removeAt`, `contains`, `indexOf`, `swap`, `sort`, concatenation,
repetition, `clear`, `count`, and stable `for` iteration. Maps accept immutable
keys and provide indexed lookup and update, `containsKey`, `remove`, `clear`,
`count`, snapshot `keys` and `values` views, and entry iteration:

```wren
var scores = {"Ada": 38, "Lin": 40}
scores["Ada"] = scores["Ada"] + 4

var values = [scores["Ada"], scores["Lin"]]
values.add(0)

var total = 0
for (value in values) total = total + value
System.print(total) // 82
```

See [`examples/collections.wren`](examples/collections.wren) for a complete
example including nested collections and removal.

Strings use Wren's UTF-8 byte-offset rules, including range slicing and
operations that preserve invalid bytes created by `String.fromByte`. The
checked-in Wren 0.4.0 differential suite locks these behaviors down. Core methods
include `contains`, `startsWith`, `endsWith`, `indexOf`, `split`, `replace`,
trimming, UTF-8 byte views, and code-point views. `Num` provides parsing,
constants, predicates, rounding, trigonometry, logarithms, powers, and clamping.
Any class can participate in a `for` loop by implementing `iterate(iterator)`
and `iteratorValue(iterator)`. See
[`examples/iterables.wren`](examples/iterables.wren).

Every built-in iterable supports `all`, `any`, `contains`, `count`, `each`,
`join`, and seeded or unseeded `reduce`. Transformations are lazy and can be
composed before materializing with `toList`; short-circuiting operations only
consume as much input as needed:

```wren
var selected = (1..20).where(Fn.new { |n| n % 2 == 0 })
selected = selected.map(Fn.new { |n| n * n }).skip(2).take(3)

System.print(selected.toList) // [36, 64, 100]
```

See [`examples/core_library.wren`](examples/core_library.wren) for a runnable
tour of the expanded core library.

Fibers retain their local environment between calls and exchange values at
cooperative suspension points. Errors can either propagate through `call` or be
captured through `try`:

```wren
var worker = Fiber.new { |request|
  System.print(request)
  var response = Fiber.yield("waiting")
  return response
}

System.print(worker.call("start")) // waiting
System.print(worker.call("done"))  // done
```

See [`examples/fibers.wren`](examples/fibers.wren) for calls, transfers, nested
control flow, completion state, and captured aborts. Worker-to-worker transfer
chains preserve each suspended continuation until control returns to it.

Multi-file programs use explicit imports. The CLI resolves relative module
names from the importing file, automatically adds `.wren` when omitted, and
executes every canonical module once:

```wren
import "math" for Calculator
System.print(Calculator.double(21))
```

```text
moon run cmd/main -- examples/modules/main.wren
```

See [`examples/modules`](examples/modules) for the complete project.

For deployments, `verified_module_loader` rejects traversal names and verifies
each bundled source before execution. `encode_module_archive` and
`decode_module_archive` provide a deterministic, versioned, length-delimited
archive with per-module integrity checks. The `wdgodghl/moonwren/loaders`
package adds a filesystem loader confined to one canonical root with extension
and source-size policies. `FileModuleWatcher::poll` supplies verified modules
and only the names changed since its last successful poll, ready to feed into
transactional `reload_module`.

The library API exposes the same pipeline:

```moonbit
match @moonwren.run("var answer = 6 * 7\nanswer\n") {
  ProgramCompleted(value, output) => {
    for line in output {
      println(line)
    }
    println("result: \{value.to_text()}")
  }
  ProgramFailed(diagnostics, _) =>
    for diagnostic in diagnostics {
      println(diagnostic.render("example.wren"))
    }
}
```

`System.print` output is returned as an array of lines instead of being written
directly by the library. Embedders can route those lines to a console, log,
editor pane, or another host-provided destination.
`ProgramRunResult::deliver` is a convenience adapter for separate output and
diagnostic callbacks.

For long-lived applications, `Vm` owns a persistent runtime. The host can load
root modules, capture values, call Wren functions and methods, read getters,
and retain returned runtime values across later calls:

```moonbit
let vm = Vm::new(VmLimits::standard(100000), loader, [], [])
ignore(vm.interpret(
  "main",
  "var count = 40\nvar next = Fn.new { count = count + 1 }\n",
))

match vm.capture("main", "next") {
  VmHandleCreated(next) => {
    ignore(vm.call(next, [])) // 41
    ignore(vm.call(next, [])) // 42
  }
  VmHandleFailed(issue) => println(issue.message)
}
vm.close()
```

Repeated calls can cache lookup intent with `bind_method` and `call_bound`.
Typed host collection operations (`list_snapshot`, `list_set`, `list_add`,
`map_snapshot`, `map_get`, `map_set`, and `map_remove`) avoid reaching into
runtime identities directly. `has_module` and `has_variable` support cheap host
capability checks.

Long-running hosts can turn a Wren Fiber into a retained asynchronous task.
The script yields a request descriptor, the host performs I/O without entering
the VM, and a later event-loop turn resumes the exact suspended continuation:

```moonbit
let fiber = match vm.capture("main", "worker") {
  VmHandleCreated(handle) => handle
  VmHandleFailed(issue) => abort(issue.message)
}
let task = match vm.new_async_task(fiber) {
  VmAsyncTaskCreated(task) => task
  VmAsyncTaskCreateFailed(issue) => abort(issue.message)
}
match vm.start_async(task, None) {
  VmAsyncYielded(request, _) =>
    ignore(vm.resume_async(task, request, Value::string("host response")))
  _ => ()
}
```

Each request is one-shot and bound to its task and VM generation. The task owns
strong roots for both its Fiber and current request; `cancel_async` releases
them. This cooperative design preserves Wren semantics and never re-enters a
running VM from a foreign callback.

For multiple concurrent Fibers, `VmScheduler` consumes the built-in `timer`,
`task`, and `scheduler` module protocols. It supports virtual-time sleeps,
child spawning, `Task.await`, ordered `Task.all`, first-completion `Task.race`,
host requests, cancellation, task limits, and retained results. Virtual time
keeps tests deterministic; a real event loop calls `advance` from its monotonic
timer and `deliver` when an I/O result arrives. Run the complete example with:

```text
moon run cmd/scheduler_demo
```

The scheduler never performs I/O itself. Any yielded value that is not one of
its reserved request maps is surfaced as `VmSchedulerExternalRequest`, keeping
networking, databases, and UI work under host control.

Scripts that genuinely need local data can opt into the separate host package.
`HostModuleKit` installs `moon/io` and `moon/env` with a per-VM policy: a single
filesystem root, independent read/write grants, UTF-8 byte limits, and an
explicit environment-value allowlist. The default policy grants nothing, and
no process or network module exists. See
[`docs/host-capabilities.md`](docs/host-capabilities.md) for the security model
or run `moon run cmd/host_demo` for a complete example.

`attach_debugger` observes the live interpreter immediately before statements
execute. Source breakpoints and pause-on-entry can return `DebugContinue`,
`DebugStepInto`, `DebugStepOver`, `DebugStepOut`, or `DebugTerminate`. Each
`DebugSnapshot` includes the source span, call depth, and visible variables.
The hook is synchronous so a desktop or terminal frontend may wait for a user
command, but it must not re-enter the same VM.

`save_state(module, names)` exports selected globals to an integrity-checked
`MWS1` archive. `restore_state` validates the complete archive before changing
bindings. Null, Boolean, Num, String (including arbitrary bytes), Range, List,
and Map values are supported; shared references and cycles are preserved.
Functions, Fibers, classes, instances, iterators, and foreign objects are
rejected because their identities cannot be moved safely between runtimes.

Automatic collection runs only between host operations, never midway through a
Wren call. Configure its minimum object count and growth percentage with
`configure_automatic_gc(VmGcPolicy::new(...))`, inspect the last pass through
`last_automatic_gc`, or disable it for latency-sensitive hosts. `System.gc()`
requests a safe collection at the next host boundary. `collect_garbage` traces
the complete runtime heap: instances, closures,
classes, lists, maps, sequence views, iterators, map entries, and Fibers. Its
statistics report total reachable and reclaimed objects as well as foreign
finalizers. Host-owned resources can use `HostObjectTable[T]`, whose
generation-checked handles reject stale identifiers after a slot is reused.

The optional hybrid bytecode backend accepts the complete MoonWren Wren 0.4
surface. Procedural control flow, collections, subscripts, properties, and
calls lower to stack instructions; classes, closures, modules, Fibers, and
structured loop control currently lower to explicit semantic instructions
executed against the same environment and resource limits. This makes compiled
programs deployable without a syntax-dependent fallback decision while keeping
the optimization boundary measurable through `semantic_fallbacks`. The
Wren 0.4-compatible interpreter remains the default:

```moonbit
match compile_bytecode("var n = 6\n n * 7\n") {
  BytecodeCompiled(program) => {
    let profile = profile_bytecode(program, 10000)
    let trace = trace_bytecode(program, 10000)
    let listing = disassemble_bytecode(program)
    let debugger = BytecodeTraceDebugger::new(trace, [1])
    ignore(debugger.step())
    ignore(debugger.continue_execution())
  }
  BytecodeCompileFailed(issues) => println(issues[0].message)
}
```

`BytecodeTraceDebugger` remains useful for deterministic trace replay, while
the `Vm` live debugger observes real interpreter state and can control the
running operation. `ReplSession` retains accepted declarations by deterministic replay and rolls
back rejected submissions. `Value::as_bool`, `as_number`, `as_string`, and
`as_range` provide checked conversions at the host boundary.

Development tools are described in [`docs/tooling.md`](docs/tooling.md),
including deterministic differential fuzzing against official Wren, repeatable
performance baselines, bytecode inspection, and the local/shareable browser
playground. The manual `Playground Pages` workflow can deploy the static build
to GitHub Pages after Pages is enabled for the repository.

Production module graphs can be packaged as deterministic, signed `MWDS1`
deployment bundles. Bundles cryptographically bind the Wren target, compiler
ABI, entry module, capability declaration, sources, and compiled metadata with
SHA-256; caller-supplied sign/verify callbacks support Ed25519 or managed keys.
See [`docs/deployment-bundles.md`](docs/deployment-bundles.md).

`reload_module` builds a candidate runtime, reloads every retained root module,
and commits only after the whole graph succeeds. Selected primitive globals can
be migrated by name. A successful reload starts a new generation and
invalidates old handles; a failed reload leaves the current runtime and handles
untouched. See [`docs/embedding.md`](docs/embedding.md) and run the complete
examples with `moon run cmd/vm_demo` and `moon run cmd/runtime_tools_demo`.

Embedders can provide modules from memory, a database, an archive, or another
source through `run_with_loader`. `run_modules` is a convenience API for a
fixed in-memory collection:

```moonbit
let modules = [
  ModuleSource::new("main", "import \"answer\" for value\nvalue\n"),
  ModuleSource::new("answer", "var value = 42\n"),
]
let result = run_modules("main", modules, 100000)
```

Wren classes may declare foreign instance methods, static methods, and getters.
`run_with_foreign_methods` binds those declarations to typed MoonBit callbacks;
callbacks receive the receiver and argument array, then return either a Wren
value or a structured host failure. `run_with_foreign_bindings` additionally
binds `foreign class` declarations. The host allocator returns an opaque integer
handle, handle-aware instance methods operate on it, and the finalizer releases
it once when the interpreter run shuts down. See
[`docs/embedding.md`](docs/embedding.md) and
[`examples/foreign_methods.wren`](examples/foreign_methods.wren) or
[`examples/foreign_classes.wren`](examples/foreign_classes.wren).

## Project status

MoonWren now passes all 779 runnable language and core-library cases in the
official Wren 0.4.0 test tree; the remaining 22 files are marked `skip` or
`nontest` by that upstream suite. The method dispatcher supports constructor
signatures, overloaded instance methods by arity, user-defined getters,
setters, operators and subscripts, core class metadata and constructors, captured
`System.print`/`write` output, and the standard `from`, `to`, `min`, `max`, and
`isInclusive` range properties. Collection and
String subscripts produce structured invalid-index and bounds diagnostics, and
Map keys are checked before lookup or mutation. Inherited
lookup advances from each method's declaring class, so multi-level `super`
calls remain correct. See [`docs/compatibility.md`](docs/compatibility.md) for
the completed source-language feature matrix and the explicitly excluded C ABI,
VM layout, and garbage-collector timing details.

Persistent VM operations enforce configurable statement, call-depth, captured
output, loaded-module, runtime-object, and source-size limits. A host callback
can also cancel work at interpreter checkpoints. These controls turn unbounded
loops, runaway recursion, output floods, module fan-out, and allocation spikes
into structured diagnostics instead of allowing them to consume host resources.
Diagnostics retain their defining module and accumulate function, instance,
static-method, and import frames while unwinding.

The implementation pipeline and package boundaries are documented in
[`docs/architecture.md`](docs/architecture.md).

## License and references

MoonWren is licensed under Apache-2.0. The implementation uses the public Wren
language documentation as a behavioral reference. See [`NOTICE`](NOTICE) for
attribution and project-boundary details.
