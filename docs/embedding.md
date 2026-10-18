# Embedding host methods

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

The current boundary supports foreign methods and getters. Foreign classes and
host-owned instance storage remain separate future work.
