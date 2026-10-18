///|
/// Runtime values available before object and class support is introduced.
pub(all) enum Value {
  NullValue
  BoolValue(Bool)
  NumberValue(Double)
  StringValue(String)
  RangeValue(Double, Double, Bool)
  ListValue(Int)
  MapValue(Int)
  SequenceValue(Int)
  FunctionValue(Int)
  ClassValue(Int)
  InstanceValue(Int)
  SuperValue(Int, Int, String)
  SuperClassValue(Int, Int)
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
fn Value::list(identifier : Int) -> Value {
  ListValue(identifier)
}

///|
fn Value::map(identifier : Int) -> Value {
  MapValue(identifier)
}

///|
fn Value::sequence(identifier : Int) -> Value {
  SequenceValue(identifier)
}

///|
fn Value::function(identifier : Int) -> Value {
  FunctionValue(identifier)
}

///|
fn Value::class_value(identifier : Int) -> Value {
  ClassValue(identifier)
}

///|
fn Value::instance(identifier : Int) -> Value {
  InstanceValue(identifier)
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
    ListValue(_) => "List"
    MapValue(_) => "Map"
    SequenceValue(_) => "Sequence"
    FunctionValue(_) => "Fn"
    ClassValue(_) => "Class"
    InstanceValue(_) => "Instance"
    SuperValue(_, _, _) => "Super"
    SuperClassValue(_, _) => "SuperClass"
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
    ListValue(_) => "<list>"
    MapValue(_) => "<map>"
    SequenceValue(_) => "<sequence>"
    FunctionValue(_) => "<fn>"
    ClassValue(_) => "<class>"
    InstanceValue(_) => "<instance>"
    SuperValue(_, _, _) => "<super>"
    SuperClassValue(_, _) => "<superclass>"
    SystemValue => "System"
  }
}
