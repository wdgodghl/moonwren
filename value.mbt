///|
/// Runtime values available before object and class support is introduced.
pub(all) enum Value {
  NullValue
  BoolValue(Bool)
  NumberValue(Double)
  StringValue(String)
  RangeValue(Double, Double, Bool)
  SystemValue
} derive(Eq, Debug)

///|
pub extend Value with Eq::{equal, not_equal}

///|
pub extend Value with Debug::{to_repr}

///|
pub fn Value::null() -> Value {
  NullValue
}

///|
pub fn Value::bool(value : Bool) -> Value {
  BoolValue(value)
}

///|
pub fn Value::number(value : Double) -> Value {
  NumberValue(value)
}

///|
pub fn Value::string(value : String) -> Value {
  StringValue(value)
}

///|
pub fn Value::range(from : Double, to : Double, inclusive : Bool) -> Value {
  RangeValue(from, to, inclusive)
}

///|
fn Value::system() -> Value {
  SystemValue
}

///|
/// Wren considers `false` and `null` falsey; every other value is truthy.
pub fn Value::is_truthy(self : Value) -> Bool {
  match self {
    NullValue | BoolValue(false) => false
    _ => true
  }
}

///|
pub fn Value::type_name(self : Value) -> String {
  match self {
    NullValue => "Null"
    BoolValue(_) => "Bool"
    NumberValue(_) => "Num"
    StringValue(_) => "String"
    RangeValue(_, _, _) => "Range"
    SystemValue => "System"
  }
}

///|
/// Convert a primitive value to its Wren-facing textual representation.
pub fn Value::to_text(self : Value) -> String {
  match self {
    NullValue => "null"
    BoolValue(true) => "true"
    BoolValue(false) => "false"
    NumberValue(number) => "\{number}"
    StringValue(text) => text
    RangeValue(from, to, true) => "\{from}..\{to}"
    RangeValue(from, to, false) => "\{from}...\{to}"
    SystemValue => "System"
  }
}
