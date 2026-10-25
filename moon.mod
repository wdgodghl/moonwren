// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "wdgodghl/moonwren"

version = "0.5.0"

readme = "README.md"

repository = "https://github.com/wdgodghl/moonwren"

license = "Apache-2.0"

keywords = [ "wren", "interpreter", "scripting", "language" ]

preferred_target = "wasm"

description = "A Wren-compatible scripting language implementation in MoonBit"

import {
  "moonbitlang/x@0.5.5",
}
