///|
/// Result produced by a MoonBit callback that implements a Wren foreign method.
pub(all) enum ForeignCallResult {
  ForeignCallSucceeded(Value)
  ForeignCallFailed(String)
}

///|
/// One host implementation identified using Wren's binding tuple.
pub struct ForeignMethodBinding {
  module_name : String
  class_name : String
  is_static : Bool
  signature : String
  callback : (Value, Array[Value]) -> ForeignCallResult
}

///|
pub fn ForeignMethodBinding::new(
  module_name : String,
  class_name : String,
  is_static : Bool,
  signature : String,
  callback : (Value, Array[Value]) -> ForeignCallResult,
) -> ForeignMethodBinding {
  { module_name, class_name, is_static, signature, callback, }
}

///|
fn ForeignMethodBinding::matches(
  self : ForeignMethodBinding,
  module_name : String,
  class_name : String,
  is_static : Bool,
  signature : String,
) -> Bool {
  self.module_name == module_name &&
  self.class_name == class_name &&
  self.is_static == is_static &&
  self.signature == signature
}

///|
fn ForeignMethodBinding::call(
  self : ForeignMethodBinding,
  receiver : Value,
  arguments : Array[Value],
) -> ForeignCallResult {
  (self.callback)(receiver, arguments)
}
