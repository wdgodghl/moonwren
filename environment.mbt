///|
pub(all) struct Binding {
  name : String
  value : Ref[Value]
}

///|
struct Scope {
  bindings : Array[Binding]
}

///|
/// Stack of lexical scopes used by the interpreter and embedding API.
pub struct Environment {
  scopes : Array[Scope]
}

///|
pub fn Environment::new() -> Environment {
  { scopes: [{ bindings: [], }], }
}

///|
pub fn Environment::depth(self : Environment) -> Int {
  self.scopes.length()
}

///|
pub fn Environment::push_scope(self : Environment) -> Unit {
  self.scopes.push({ bindings: [], })
}

///|
pub fn Environment::pop_scope(self : Environment) -> Bool {
  if self.scopes.length() <= 1 {
    false
  } else {
    ignore(self.scopes.pop())
    true
  }
}

///|
/// Define a name in the innermost scope. Returns false for a duplicate.
pub fn Environment::bind(
  self : Environment,
  name : String,
  value : Value,
) -> Bool {
  let scope = self.scopes[self.scopes.length() - 1]
  for binding in scope.bindings {
    if binding.name == name {
      return false
    }
  }
  scope.bindings.push({ name, value: Ref(value), })
  true
}

///|
pub fn Environment::get(self : Environment, name : String) -> Value? {
  let mut scope_index = self.scopes.length() - 1
  while scope_index >= 0 {
    for binding in self.scopes[scope_index].bindings {
      if binding.name == name {
        return Some(binding.value.val)
      }
    }
    scope_index = scope_index - 1
  }
  None
}

///|
/// Replace the nearest visible binding. Returns false when the name is absent.
pub fn Environment::assign(
  self : Environment,
  name : String,
  value : Value,
) -> Bool {
  let mut scope_index = self.scopes.length() - 1
  while scope_index >= 0 {
    for binding in self.scopes[scope_index].bindings {
      if binding.name == name {
        binding.value.val = value
        return true
      }
    }
    scope_index = scope_index - 1
  }
  false
}

///|
/// Snapshot visible scopes while retaining shared variable cells.
pub fn Environment::capture(self : Environment) -> Environment {
  let scopes : Array[Scope] = []
  for scope in self.scopes {
    let bindings : Array[Binding] = []
    for binding in scope.bindings {
      bindings.push({ name: binding.name, value: binding.value, })
    }
    scopes.push({ bindings, })
  }
  { scopes, }
}
