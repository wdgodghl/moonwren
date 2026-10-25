# Embedding host methods and classes

MoonWren can bind Wren `foreign` declarations to MoonBit callbacks. A binding
uses the canonical module name returned by the module loader, the Wren class
name, whether the method is static, and its Wren signature.

```wren
class HostMath {
  foreign static add(left, right)
}

System.print(HostMath.add(20, 22))
```

The host registers the implementation before running the entry module:

```moonbit
let add = ForeignMethodBinding::new(
  "main.wren",
  "HostMath",
  true,
  "add(_,_)",
  fn(_receiver, arguments) {
    match (arguments[0], arguments[1]) {
      (NumberValue(left), NumberValue(right)) =>
        ForeignCallSucceeded(Value::number(left + right))
      _ => ForeignCallFailed("expected two numbers")
    }
  },
)

let result = run_with_foreign_methods(
  "main.wren",
  source,
  100000,
  loader,
  [add],
)
```

The receiver is passed separately from the argument array. Static callbacks
receive the class value; instance callbacks receive the instance. Getters use
their bare name as the signature, while methods use Wren placeholders such as
`add(_,_)`.

`ForeignCallSucceeded` returns a value to Wren. `ForeignCallFailed` stops the
call with a structured `ForeignCallFailed` runtime diagnostic. If a declaration
has no exact binding, execution produces `ForeignBindingMissing` and includes
the complete lookup tuple in the message. A callback cannot re-enter the same
runtime, matching Wren's non-reentrant foreign-call model.

## Host-backed classes

A Wren foreign class is declared separately from its methods. Its constructor
body is still Wren code, while allocation gives the host an opportunity to
create state from the constructor arguments:

```wren
foreign class Counter {
  construct new(start) {}
  foreign increment(amount)
  foreign value
}
```

The host chooses an opaque integer handle. It may be an index into a host-owned
array, a table key, or another stable identifier:

```moonbit
let values : Array[Double] = []
let counter_class = ForeignClassBinding::new(
  "main.wren",
  "Counter",
  fn(arguments) {
    match arguments[0] {
      NumberValue(start) => {
        let handle = values.length()
        values.push(start)
        ForeignAllocationSucceeded(handle)
      }
      _ => ForeignAllocationFailed("start must be a number")
    }
  },
  fn(handle) { values[handle] = 0.0 },
)

let increment = ForeignMethodBinding::new_for_foreign_class(
  "main.wren",
  "Counter",
  "increment(_)",
  fn(handle, arguments) {
    match arguments[0] {
      NumberValue(amount) => {
        values[handle] = values[handle] + amount
        ForeignCallSucceeded(Value::number(values[handle]))
      }
      _ => ForeignCallFailed("amount must be a number")
    }
  },
)

let result = run_with_foreign_bindings(
  "main.wren",
  source,
  100000,
  loader,
  [increment],
  [counter_class],
)
```

`ForeignClassBindingMissing` is reported while executing an unbound foreign
class declaration. `ForeignObjectAllocationFailed` reports a rejected
constructor allocation. Handles stay opaque to Wren and are delivered only to
bindings created with `new_for_foreign_class`.

Every successfully allocated handle is finalized exactly once when a one-shot
interpreter run ends, including failed runs. Persistent VMs additionally expose
an explicit reachability pass, described below.

## Persistent VM

`Vm` is the long-lived embedding surface. Unlike `run`, it retains loaded
modules, globals, closures, Fibers, classes, instances, and foreign objects
between calls:

```moonbit
let limits = VmLimits::new(
  100000,   // statements per operation
  64,       // Wren call depth
  1000000,  // captured output characters
  1024,     // loaded modules
  1000000,  // runtime registry objects
  10000000, // source characters per module
)
let vm = Vm::new(limits, loader, foreign_methods, foreign_classes)
```

`interpret(name, source)` loads a root module once. `read` returns a module
variable without retaining it. `capture` creates a strong `VmHandle`, and
`retain` turns a value returned by a host call into another strong handle.
`call`, `call_method`, and `get` invoke functions, methods, and getters through
those handles. `release` removes a host root. A released handle, a handle from a
successful pre-reload generation, and every handle after `close` are rejected.

`bind_method` creates a generation-checked `VmMethodHandle` for repeated calls;
`call_bound` also validates arity before entering Wren. Hosts can inspect and
mutate retained Lists and Maps with the typed `list_*` and `map_*` operations.
Those helpers return `VmHostResult` and copy snapshots, keeping runtime storage
encapsulated. `has_module` and `has_variable` provide non-throwing probes.

Runtime-indexed `Value` variants are meaningful only inside the VM that created
them. If such a value must survive an explicit collection pass, call `retain`
before collecting. Primitive null, Boolean, number, String, and Range values are
self-contained.

`Vm::new_cancellable` accepts an additional zero-argument callback. Returning
`true` stops the current operation with an `ExecutionLimit` diagnostic. The
callback is evaluated at interpreter checkpoints; it is intended for deadlines,
request cancellation, and application shutdown, not asynchronous re-entry into
the same VM.

## Transactional module reload

`reload_module(name, source, preserve)` constructs a fresh candidate runtime,
executes the replacement module, and then rebuilds every retained root. Only a
fully successful candidate replaces the current generation. Parse, resolution,
import, resource-limit, or runtime failures discard the candidate and preserve
the active runtime and all existing handles.

Names in `preserve` migrate their old values after the replacement module has
initialized and before dependent roots execute. Migration is deliberately
limited to portable primitives: null, Boolean, number, String, raw String, and
Range. Closures, classes, instances, collections, iterators, and Fibers contain
runtime-local identities and must be reconstructed by the new source.

A successful reload invalidates every old handle, so the host must capture the
new generation's entry points. Reload is transactional for MoonWren state.
Foreign allocators, finalizers, method callbacks, module loaders, and other host
callbacks may have external side effects that the VM cannot roll back; hosts
should make those callbacks idempotent when reload failure is possible.

## Reachability and foreign lifetimes

Automatic collection is enabled by default and runs only at safe host-operation
boundaries. `VmGcPolicy::new(minimum_objects, growth_percent)` controls the
first threshold and subsequent heap-growth threshold;
`configure_automatic_gc`, `disable_automatic_gc`, and `last_automatic_gc`
control and inspect it. Wren's `System.gc()` sets a request that is honored at
the next boundary rather than collecting through active MoonBit frames.

`collect_garbage()` traces module environments, class and closure environments,
the main Fiber, nested collections and sequences, and live host handles. It
logically reclaims unreachable runtime objects and immediately invokes foreign
finalizers once. `VmGcStats` reports object totals, reachable and reclaimed
objects, instance counts, and finalized foreign instances.

MoonBit closures used for suspended Fiber continuations are opaque to the
runtime. While such a continuation exists, instance collection is conservative:
all live instances are retained until the Fiber resumes or completes. Live
instance identities remain stable, while retired instance slots may be reused
by later allocations. The pass does not yet compact the other runtime
registries. `close` finalizes every still-live foreign instance exactly once
and invalidates all handles.
