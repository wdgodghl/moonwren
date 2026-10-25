///|
test "typed value conversions reject mismatched runtime values" {
  match @moonwren.Value::number(2.5).as_number() {
    @moonwren.ValueConverted(value) => assert_eq(value, 2.5)
    @moonwren.ValueConversionFailed(_, _) => fail("number should convert")
  }
  match @moonwren.Value::bool(true).as_string() {
    @moonwren.ValueConverted(_) => fail("bool must not convert to string")
    @moonwren.ValueConversionFailed(expected, actual) => {
      assert_eq(expected, "String")
      assert_eq(actual, "Bool")
    }
  }
}

///|
test "host object handles detect release and slot reuse" {
  let table : @moonwren.HostObjectTable[String] = @moonwren.HostObjectTable::new()
  let first = table.insert("first")
  assert_eq(table.get(first), Some("first"))
  assert_true(table.release(first))
  assert_eq(table.get(first), None)
  let second = table.insert("second")
  assert_eq(second.slot, first.slot)
  assert_true(second.generation > first.generation)
  assert_eq(table.get(first), None)
  assert_eq(table.get(second), Some("second"))
  assert_eq(table.live_count(), 1)
}
