# Wren 0.4.0 conformance target

MoonWren targets the language and embedding semantics of the official Wren
0.4.0 release. The reference baseline is `wren-lang/wren` tag `0.4.0`, commit
`4a18fc489f9ea3d253b20dd40f02c6097a8e2508`.

## Definition of done

The compatibility milestone is complete only when all of the following are
true:

1. Wren 0.4.0 lexical grammar, expressions, statements, functions, classes,
   modules, core classes, and error categories used by the official language
   test suite are implemented or listed in the exclusions below.
2. String values preserve arbitrary bytes. Indexes and search results are
   UTF-8 byte offsets, `.bytes` exposes every stored byte, `.codePoints`
   reports `-1` for an invalid UTF-8 byte, and slicing can preserve invalid
   byte sequences.
3. A fiber may suspend from any depth in its active Wren call stack, including
   a function, instance/static method, getter, operator method, and a callback
   invoked by a sequence operation. Calling or transferring back resumes the
   same stack without replaying completed side effects.
4. Modules and foreign method/class bindings reproduce the documented Wren
   VM behavior at the source-language boundary.
5. Every adopted official case passes MoonWren's automated conformance suite.
   Differential fixtures compare standard output, final value where exposed,
   and normalized compile/runtime error category against the official CLI.

This is a fixed compatibility endpoint, not an open-ended promise to add
features gradually. The feature matrix in `compatibility.md` records current
progress separately from this endpoint.

## Included edge cases

### UTF-8 byte semantics

The conformance suite includes multibyte code points and invalid bytes:

```wren
var text = "Aé𐍈"
System.print(text.count)          // 3
System.print(text.bytes.count)    // 7
System.print(text.indexOf("𐍈"))  // 3
System.print(text[1])             // é
System.print(text.codePoints[2])  // -1 (continuation byte)

var invalid = String.fromByte(255)
System.print(invalid.bytes[0])     // 255
System.print(invalid.codePoints[0])// -1
```

### Suspension across calls

The conformance suite includes suspension inside callbacks and methods:

```wren
var worker = Fiber.new {
  (1..3).each { |number| Fiber.yield(number * 2) }
  return "done"
}
System.print(worker.call()) // 2
System.print(worker.call()) // 4
System.print(worker.call()) // 6
System.print(worker.call()) // done
```

The final suite also covers a yield reached through an instance method and a
getter, and verifies that locals and side effects before the yield are not
recreated on resume.

## Explicit exclusions

The compatibility claim does not include the separate `wren_cli` application's
filesystem/process/terminal modules, the C API's binary ABI, the official VM's
garbage collector timing, bytecode format, object layout, performance, or
memory usage. MoonWren provides a MoonBit embedding API in place of the C ABI.
These exclusions do not remove any Wren 0.4.0 language or core-library
semantics from the target.

## Differential fixtures

Cases under `conformance/wren-0.4.0` contain a Wren input and the output
captured from the official 0.4.0 CLI. `tools/check-conformance.ps1` runs the
same inputs through MoonWren and compares their output byte-for-byte. When an
official `wren` executable is supplied, `tools/refresh-reference.ps1` can
independently reproduce the reference output and rejects a different Wren
version.

