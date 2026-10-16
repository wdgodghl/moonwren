///|
test "only false and null are falsey" {
  assert_false(@moonwren.Value::null().is_truthy())
  assert_false(@moonwren.Value::bool(false).is_truthy())
  assert_true(@moonwren.Value::bool(true).is_truthy())
  assert_true(@moonwren.Value::number(0.0).is_truthy())
  assert_true(@moonwren.Value::string("").is_truthy())
}

///|
test "primitive values expose Wren type names" {
  assert_eq(@moonwren.Value::null().type_name(), "Null")
  assert_eq(@moonwren.Value::bool(true).type_name(), "Bool")
  assert_eq(@moonwren.Value::number(1.0).type_name(), "Num")
  assert_eq(@moonwren.Value::string("text").type_name(), "String")
  assert_eq(@moonwren.Value::range(1.0, 3.0, true).type_name(), "Range")
}

///|
test "primitive values render as source-facing text" {
  assert_eq(@moonwren.Value::null().to_text(), "null")
  assert_eq(@moonwren.Value::bool(false).to_text(), "false")
  assert_eq(@moonwren.Value::number(12.5).to_text(), "12.5")
  assert_eq(@moonwren.Value::string("hello").to_text(), "hello")
  assert_eq(@moonwren.Value::range(1.0, 3.0, true).to_text(), "1..3")
  assert_eq(@moonwren.Value::range(3.0, 1.0, false).to_text(), "3...1")
}
