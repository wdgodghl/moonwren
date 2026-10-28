///|
/// Built-in source for Wren 0.4's optional `random` module. The public API and
/// algorithms follow the upstream optional module; host state is kept behind
/// MoonWren foreign-class handles so each VM owns an isolated generator.
let optional_random_source =
  #|foreign class Random {
  #|  construct new() { seed_() }
  #|  construct new(seed) {
  #|    if (seed is Num) {
  #|      seed_(seed)
  #|    } else if (seed is Sequence) {
  #|      if (seed.isEmpty) Fiber.abort("Sequence cannot be empty.")
  #|      var seeds = []
  #|      for (element in seed) {
  #|        if (!(element is Num)) Fiber.abort("Sequence elements must all be numbers.")
  #|        seeds.add(element)
  #|        if (seeds.count == 16) break
  #|      }
  #|      var i = 0
  #|      while (seeds.count < 16) {
  #|        seeds.add(seeds[i])
  #|        i = i + 1
  #|      }
  #|      seed_(seeds[0], seeds[1], seeds[2], seeds[3], seeds[4], seeds[5], seeds[6], seeds[7], seeds[8], seeds[9], seeds[10], seeds[11], seeds[12], seeds[13], seeds[14], seeds[15])
  #|    } else {
  #|      Fiber.abort("Seed must be a number or a sequence of numbers.")
  #|    }
  #|  }
  #|  foreign seed_()
  #|  foreign seed_(seed)
  #|  foreign seed_(n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n11, n12, n13, n14, n15, n16)
  #|  foreign float()
  #|  float(end) { float() * end }
  #|  float(start, end) { float() * (end - start) + start }
  #|  foreign int()
  #|  int(end) { (float() * end).floor }
  #|  int(start, end) { (float() * (end - start)).floor + start }
  #|  sample(list) {
  #|    if (list.count == 0) Fiber.abort("Not enough elements to sample.")
  #|    return list[int(list.count)]
  #|  }
  #|  sample(list, count) {
  #|    if (count > list.count) Fiber.abort("Not enough elements to sample.")
  #|    var result = []
  #|    var picked = List.filled(list.count, false)
  #|    for (i in list.count - count...list.count) {
  #|      var index = int(i + 1)
  #|      if (picked[index]) index = i
  #|      picked[index] = true
  #|      result.add(list[index])
  #|    }
  #|    return result
  #|  }
  #|  shuffle(list) {
  #|    if (list.isEmpty) return
  #|    for (i in 0...list.count - 1) {
  #|      var from = int(i, list.count)
  #|      var temp = list[from]
  #|      list[from] = list[i]
  #|      list[i] = temp
  #|    }
  #|  }
  #|}

///|
let optional_meta_source =
  #|class Meta {
  #|  foreign static getModuleVariables(module)
  #|  foreign static eval(source)
  #|  foreign static compileExpression(source)
  #|  foreign static compile(source)
  #|}

///|
fn optional_module_source(name : String) -> String? {
  match name {
    "random" => Some(optional_random_source)
    "meta" => Some(optional_meta_source)
    _ => None
  }
}

///|
priv struct BuiltinRandomState {
  state : Array[UInt]
  mut index : Int
  mut alive : Bool
}

///|
fn random_state_for_handle(
  states : Array[BuiltinRandomState],
  handle : Int,
) -> BuiltinRandomState? {
  if handle < 0 || handle >= states.length() || !states[handle].alive {
    None
  } else {
    Some(states[handle])
  }
}

///|
fn seed_random_number(state : BuiltinRandomState, seed : Double) -> Unit {
  let mut value = wren_u32(seed)
  for index = 0; index < 16; index = index + 1 {
    value = value * 1664525U + 1013904223U
    state.state[index] = value
  }
  state.index = 0
}

///|
fn seed_random_values(
  state : BuiltinRandomState,
  arguments : Array[Value],
) -> Bool {
  if arguments.length() != 16 {
    return false
  }
  for index = 0; index < 16; index = index + 1 {
    match arguments[index] {
      NumberValue(number) => state.state[index] = wren_u32(number)
      _ => return false
    }
  }
  state.index = 0
  true
}

///|
fn advance_random(state : BuiltinRandomState) -> UInt {
  let a = state.state[state.index]
  let mut c = state.state[(state.index + 13) & 15]
  let b = a ^ c ^ (a << 16) ^ (c << 15)
  c = state.state[(state.index + 9) & 15]
  c = c ^ (c >> 11)
  let next = b ^ c
  state.state[state.index] = next
  let d = next ^ ((next << 5) & 0xda442d24U)
  state.index = (state.index + 15) & 15
  let tail = state.state[state.index]
  state.state[state.index] = tail ^ b ^ d ^ (tail << 2) ^ (b << 18) ^ (c << 28)
  state.state[state.index]
}

///|
fn append_optional_bindings(
  methods : Array[ForeignMethodBinding],
  classes : Array[ForeignClassBinding],
) -> Unit {
  for
    signature in [
      "getModuleVariables(_)", "eval(_)", "compileExpression(_)", "compile(_)",
    ] {
    methods.push(
      ForeignMethodBinding::new("meta", "Meta", true, signature, fn(_, _) {
        ForeignCallFailed("built-in Meta dispatch was not available")
      }),
    )
  }
  let states : Array[BuiltinRandomState] = []
  let nonce = Ref(0)
  classes.push(
    ForeignClassBinding::new(
      "random",
      "Random",
      fn(_) {
        let values = Array::make(16, 0U)
        let handle = states.length()
        states.push({ state: values, index: 0, alive: true, })
        ForeignAllocationSucceeded(handle)
      },
      fn(handle) {
        match random_state_for_handle(states, handle) {
          Some(state) => state.alive = false
          None => ()
        }
      },
    ),
  )
  methods.push(
    ForeignMethodBinding::new_for_foreign_class("random", "Random", "seed_()", fn(
      handle,
      _,
    ) {
      match random_state_for_handle(states, handle) {
        None => ForeignCallFailed("random generator is no longer available")
        Some(state) => {
          nonce.val = nonce.val + 1
          seed_random_number(state, nonce.val.to_double() * 2654435761.0)
          ForeignCallSucceeded(Value::null())
        }
      }
    }),
  )
  methods.push(
    ForeignMethodBinding::new_for_foreign_class(
      "random",
      "Random",
      "seed_(_)",
      fn(handle, arguments) {
        match random_state_for_handle(states, handle) {
          None => ForeignCallFailed("random generator is no longer available")
          Some(state) =>
            match arguments[0] {
              NumberValue(seed) => {
                seed_random_number(state, seed)
                ForeignCallSucceeded(Value::null())
              }
              _ => ForeignCallFailed("seed must be a number")
            }
        }
      },
    ),
  )
  methods.push(
    ForeignMethodBinding::new_for_foreign_class(
      "random",
      "Random",
      "seed_(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)",
      fn(handle, arguments) {
        match random_state_for_handle(states, handle) {
          None => ForeignCallFailed("random generator is no longer available")
          Some(state) =>
            if seed_random_values(state, arguments) {
              ForeignCallSucceeded(Value::null())
            } else {
              ForeignCallFailed("all seed values must be numbers")
            }
        }
      },
    ),
  )
  methods.push(
    ForeignMethodBinding::new_for_foreign_class("random", "Random", "int()", fn(
      handle,
      _,
    ) {
      match random_state_for_handle(states, handle) {
        None => ForeignCallFailed("random generator is no longer available")
        Some(state) =>
          ForeignCallSucceeded(Value::number(advance_random(state).to_double()))
      }
    }),
  )
  methods.push(
    ForeignMethodBinding::new_for_foreign_class("random", "Random", "float()", fn(
      handle,
      _,
    ) {
      match random_state_for_handle(states, handle) {
        None => ForeignCallFailed("random generator is no longer available")
        Some(state) => {
          let high = advance_random(state).to_double() * 2097152.0
          let low = (advance_random(state) & 0x1fffffU).to_double()
          ForeignCallSucceeded(Value::number((high + low) / 9007199254740992.0))
        }
      }
    }),
  )
}
