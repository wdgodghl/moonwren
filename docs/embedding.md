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

Every successfully allocated handle is finalized exactly once when the
interpreter run ends, including failed runs. MoonWren does not yet perform a
reachability garbage collection pass, so finalizers do not run early when an
object becomes unreachable. Explicit `close()`-style foreign methods are still
recommended for resources that should be released before shutdown.
