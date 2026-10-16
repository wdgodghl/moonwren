///|
test "environment resolves innermost bindings first" {
  let environment = @moonwren.Environment::new()
  assert_true(environment.bind("value", @moonwren.Value::number(1.0)))
  environment.push_scope()
  assert_true(environment.bind("value", @moonwren.Value::number(2.0)))
  assert_eq(environment.get("value"), Some(@moonwren.Value::number(2.0)))
  assert_true(environment.pop_scope())
  assert_eq(environment.get("value"), Some(@moonwren.Value::number(1.0)))
}

///|
test "environment rejects duplicates in the same scope" {
  let environment = @moonwren.Environment::new()
  assert_true(environment.bind("item", @moonwren.Value::null()))
  assert_false(environment.bind("item", @moonwren.Value::bool(true)))
}

///|
test "assignment updates nearest visible binding" {
  let environment = @moonwren.Environment::new()
  assert_true(environment.bind("count", @moonwren.Value::number(1.0)))
  environment.push_scope()
  assert_true(environment.assign("count", @moonwren.Value::number(3.0)))
  assert_eq(environment.get("count"), Some(@moonwren.Value::number(3.0)))
  assert_false(environment.assign("missing", @moonwren.Value::null()))
}

///|
test "global scope cannot be removed" {
  let environment = @moonwren.Environment::new()
  assert_false(environment.pop_scope())
  assert_eq(environment.depth(), 1)
}

///|
test "captured environments retain shared variable cells" {
  let environment = @moonwren.Environment::new()
  assert_true(environment.bind("count", @moonwren.Value::number(0.0)))
  let captured = environment.capture()
  assert_true(captured.assign("count", @moonwren.Value::number(1.0)))
  assert_eq(environment.get("count"), Some(@moonwren.Value::number(1.0)))
}

///|
test "captured scope structure survives later scope removal" {
  let environment = @moonwren.Environment::new()
  environment.push_scope()
  assert_true(environment.bind("local", @moonwren.Value::string("kept")))
  let captured = environment.capture()
  assert_true(environment.pop_scope())
  assert_eq(environment.get("local"), None)
  assert_eq(captured.get("local"), Some(@moonwren.Value::string("kept")))
}
