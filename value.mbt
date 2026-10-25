///|
/// Runtime values available before object and class support is introduced.
pub(all) enum CoreClass {
  ObjectClass
  BoolClass
  ClassClass
  FiberClass
  FnClass
  ListClass
  MapClass
  MapEntryClass
  MapKeySequenceClass
  MapValueSequenceClass
  NullClass
  NumClass
  RangeClass
  SequenceClass
  StringClass
  StringByteSequenceClass
  StringCodePointSequenceClass
} derive(Eq, Debug)

///|
pub extend CoreClass with Eq::{equal, not_equal}

///|
pub extend CoreClass with Debug::{to_repr}

///|
pub fn CoreClass::name(self : CoreClass) -> String {
  match self {
    ObjectClass => "Object"
    BoolClass => "Bool"
    ClassClass => "Class"
    FiberClass => "Fiber"
    FnClass => "Fn"
    ListClass => "List"
    MapClass => "Map"
    MapEntryClass => "MapEntry"
    MapKeySequenceClass => "MapKeySequence"
    MapValueSequenceClass => "MapValueSequence"
    NullClass => "Null"
    NumClass => "Num"
    RangeClass => "Range"
    SequenceClass => "Sequence"
    StringClass => "String"
    StringByteSequenceClass => "StringByteSequence"
    StringCodePointSequenceClass => "StringCodePointSequence"
  }
}

///|
pub(all) enum Value {
  NullValue
  BoolValue(Bool)
  NumberValue(Double)
  StringValue(String)
  RawStringValue(Array[Int])
  RangeValue(Double, Double, Bool)
  ListValue(Int)
  MapValue(Int)
  SequenceValue(Int)
  FunctionValue(Int)
  FiberValue(Int)
  ClassValue(Int)
  MetaClassValue(String)
  ClassAttributesValue(Int, Int)
  InstanceValue(Int)
  SuperValue(Int, Int, String, Bool)
  SuperClassValue(Int, Int)
  CoreClassValue(CoreClass)
  IteratorValue(Int)
  MapEntryValue(Int)
  SystemValue
} derive(Eq, Debug)

///|
/// Result of converting a dynamically typed Wren value at the host boundary.
pub(all) enum ValueConversionResult[T] {
  ValueConverted(T)
  ValueConversionFailed(String, String)
}

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
/// Construct a String from bytes that are not required to be valid UTF-8.
/// This is used by Wren's byte-oriented String primitives.
fn Value::raw_string(bytes : Array[Int]) -> Value {
  RawStringValue(bytes)
}

///|
pub fn Value::range(from : Double, to : Double, inclusive : Bool) -> Value {
  RangeValue(from, to, inclusive)
}

///|
pub fn Value::as_bool(self : Value) -> ValueConversionResult[Bool] {
  match self {
    BoolValue(value) => ValueConverted(value)
    _ => ValueConversionFailed("Bool", self.type_name())
  }
}

///|
pub fn Value::as_number(self : Value) -> ValueConversionResult[Double] {
  match self {
    NumberValue(value) => ValueConverted(value)
    _ => ValueConversionFailed("Num", self.type_name())
  }
}

///|
pub fn Value::as_string(self : Value) -> ValueConversionResult[String] {
  match self {
    StringValue(value) => ValueConverted(value)
    RawStringValue(_) => ValueConversionFailed("valid UTF-8 String", "String")
    _ => ValueConversionFailed("String", self.type_name())
  }
}

///|
pub fn Value::as_range(
  self : Value,
) -> ValueConversionResult[(Double, Double, Bool)] {
  match self {
    RangeValue(from, to, inclusive) => ValueConverted((from, to, inclusive))
    _ => ValueConversionFailed("Range", self.type_name())
  }
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
fn Value::fiber(identifier : Int) -> Value {
  FiberValue(identifier)
}

///|
fn Value::class_value(identifier : Int) -> Value {
  ClassValue(identifier)
}

///|
fn Value::meta_class(name : String) -> Value {
  MetaClassValue(name)
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
fn Value::core_class(value : CoreClass) -> Value {
  CoreClassValue(value)
}

///|
fn Value::iterator(identifier : Int) -> Value {
  IteratorValue(identifier)
}

///|
fn Value::map_entry(identifier : Int) -> Value {
  MapEntryValue(identifier)
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
/// Wren 0.4 formats numbers with 14 significant decimal digits. MoonBit's
/// default formatter intentionally preserves more precision, so normalize its
/// shortest round-trippable spelling to Wren's public representation.
fn wren_number_to_text(number : Double) -> String {
  if number.is_nan() {
    return "nan"
  }
  if number.is_pos_inf() {
    return "infinity"
  }
  if number.is_neg_inf() {
    return "-infinity"
  }
  let raw = number.to_string().to_array()
  let mut index = 0
  let mut negative = false
  if raw.length() > 0 && raw[0].to_int() == 45 {
    negative = true
    index = 1
  }
  let digits : Array[Int] = []
  let mut decimal_position = -1
  let mut exponent_sign = 1
  let mut exponent_value = 0
  let mut reading_exponent = false
  while index < raw.length() {
    let code = raw[index].to_int()
    if code == 46 {
      decimal_position = digits.length()
    } else if code == 69 || code == 101 {
      reading_exponent = true
      if decimal_position < 0 {
        decimal_position = digits.length()
      }
    } else if reading_exponent && code == 45 {
      exponent_sign = -1
    } else if reading_exponent && code == 43 {
      exponent_sign = 1
    } else if code >= 48 && code <= 57 {
      if reading_exponent {
        exponent_value = exponent_value * 10 + code - 48
      } else {
        digits.push(code - 48)
      }
    }
    index = index + 1
  }
  if decimal_position < 0 {
    decimal_position = digits.length()
  }
  decimal_position = decimal_position + exponent_sign * exponent_value
  let mut leading = 0
  while leading < digits.length() && digits[leading] == 0 {
    leading = leading + 1
  }
  if leading == digits.length() {
    return if negative ||
      number.reinterpret_as_uint64() == 0x8000_0000_0000_0000UL {
      "-0"
    } else {
      "0"
    }
  }
  decimal_position = decimal_position - leading
  let significant : Array[Int] = []
  for digit_index = leading
      digit_index < digits.length() && significant.length() < 14
      digit_index = digit_index + 1 {
    significant.push(digits[digit_index])
  }
  let mut scientific_exponent = decimal_position - 1
  if leading + significant.length() < digits.length() &&
    digits[leading + significant.length()] >= 5 {
    let mut carry_index = significant.length() - 1
    let mut carry = true
    while carry && carry_index >= 0 {
      if significant[carry_index] == 9 {
        significant[carry_index] = 0
        carry_index = carry_index - 1
      } else {
        significant[carry_index] = significant[carry_index] + 1
        carry = false
      }
    }
    if carry {
      significant[0] = 1
      for reset_index = 1
          reset_index < significant.length()
          reset_index = reset_index + 1 {
        significant[reset_index] = 0
      }
      scientific_exponent = scientific_exponent + 1
    }
  }
  while significant.length() > 1 && significant[significant.length() - 1] == 0 {
    ignore(significant.pop())
  }
  let mut text = if negative { "-" } else { "" }
  let digit_text = fn(digit : Int) -> String {
    (digit + 48).unsafe_to_char().to_string()
  }
  if scientific_exponent < -4 || scientific_exponent >= 14 {
    text = text + digit_text(significant[0])
    if significant.length() > 1 {
      text = text + "."
      for digit_index = 1
          digit_index < significant.length()
          digit_index = digit_index + 1 {
        text = text + digit_text(significant[digit_index])
      }
    }
    let exponent_sign_text = if scientific_exponent >= 0 { "+" } else { "-" }
    text = text + "e" + exponent_sign_text
    let magnitude = if scientific_exponent >= 0 {
      scientific_exponent
    } else {
      -scientific_exponent
    }
    return text + magnitude.to_string()
  }
  let fixed_position = scientific_exponent + 1
  if fixed_position <= 0 {
    text = text + "0."
    for zero_index = fixed_position; zero_index < 0; zero_index = zero_index + 1 {
      text = text + "0"
    }
    for digit in significant {
      text = text + digit_text(digit)
    }
    return text
  }
  for digit_index = 0
      digit_index < fixed_position
      digit_index = digit_index + 1 {
    if digit_index < significant.length() {
      text = text + digit_text(significant[digit_index])
    } else {
      text = text + "0"
    }
  }
  if fixed_position < significant.length() {
    text = text + "."
    for digit_index = fixed_position
        digit_index < significant.length()
        digit_index = digit_index + 1 {
      text = text + digit_text(significant[digit_index])
    }
  }
  text
}

///|
pub fn Value::type_name(self : Value) -> String {
  match self {
    NullValue => "Null"
    BoolValue(_) => "Bool"
    NumberValue(_) => "Num"
    StringValue(_) | RawStringValue(_) => "String"
    RangeValue(_, _, _) => "Range"
    ListValue(_) => "List"
    MapValue(_) => "Map"
    SequenceValue(_) => "Sequence"
    FunctionValue(_) => "Fn"
    FiberValue(_) => "Fiber"
    ClassValue(_) => "Class"
    MetaClassValue(_) => "Class"
    ClassAttributesValue(_, _) => "ClassAttributes"
    InstanceValue(_) => "Instance"
    SuperValue(_, _, _, _) => "Super"
    SuperClassValue(_, _) => "SuperClass"
    CoreClassValue(_) => "Class"
    IteratorValue(_) => "Iterator"
    MapEntryValue(_) => "MapEntry"
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
    NumberValue(number) => wren_number_to_text(number)
    StringValue(text) => text
    RawStringValue(_) => "�"
    RangeValue(from, to, true) =>
      wren_number_to_text(from) + ".." + wren_number_to_text(to)
    RangeValue(from, to, false) =>
      wren_number_to_text(from) + "..." + wren_number_to_text(to)
    ListValue(_) => "<list>"
    MapValue(_) => "<map>"
    SequenceValue(_) => "<sequence>"
    FunctionValue(_) => "<fn>"
    FiberValue(_) => "<fiber>"
    ClassValue(_) => "<class>"
    MetaClassValue(name) => name
    ClassAttributesValue(_, _) => "<class attributes>"
    InstanceValue(_) => "<instance>"
    SuperValue(_, _, _, _) => "<super>"
    SuperClassValue(_, _) => "<superclass>"
    CoreClassValue(class_value) => class_value.name()
    IteratorValue(_) => "<iterator>"
    MapEntryValue(_) => "<map entry>"
    SystemValue => "System"
  }
}
