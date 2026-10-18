///|
/// Result produced by a MoonBit callback that implements a Wren foreign method.
pub(all) enum ForeignCallResult {
  ForeignCallSucceeded(Value)
  ForeignCallFailed(String)
}

///|
/// Result returned while allocating the host-owned state of a foreign object.
/// The integer is an opaque handle chosen and managed by the embedding host.
pub(all) enum ForeignAllocationResult {
  ForeignAllocationSucceeded(Int)
  ForeignAllocationFailed(String)
}

///|
/// Host lifecycle callbacks associated with one Wren `foreign class`.
pub struct ForeignClassBinding {
  module_name : String
  class_name : String
  allocate : (Array[Value]) -> ForeignAllocationResult
  finalize : (Int) -> Unit
}

///|
pub fn ForeignClassBinding::new(
  module_name : String,
  class_name : String,
  allocate : (Array[Value]) -> ForeignAllocationResult,
  finalize : (Int) -> Unit,
) -> ForeignClassBinding {
  { module_name, class_name, allocate, finalize, }
}

///|
fn ForeignClassBinding::matches(
  self : ForeignClassBinding,
  module_name : String,
  class_name : String,
) -> Bool {
  self.module_name == module_name && self.class_name == class_name
}

///|
fn ForeignClassBinding::allocate(
  self : ForeignClassBinding,
  arguments : Array[Value],
) -> ForeignAllocationResult {
  (self.allocate)(arguments)
}

///|
fn ForeignClassBinding::finalize(
  self : ForeignClassBinding,
  handle : Int,
) -> Unit {
  (self.finalize)(handle)
}

///|
/// One host implementation identified using Wren's binding tuple.
pub struct ForeignMethodBinding {
  module_name : String
  class_name : String
  is_static : Bool
  signature : String
  callback : ((Value, Array[Value]) -> ForeignCallResult)?
  handle_callback : ((Int, Array[Value]) -> ForeignCallResult)?
}

///|
pub fn ForeignMethodBinding::new(
  module_name : String,
  class_name : String,
  is_static : Bool,
  signature : String,
  callback : (Value, Array[Value]) -> ForeignCallResult,
) -> ForeignMethodBinding {
  {
    module_name,
    class_name,
    is_static,
    signature,
    callback: Some(callback),
    handle_callback: None,
  }
}

///|
/// Bind an instance method that receives the opaque handle allocated for a
/// foreign class instead of the Wren receiver value.
pub fn ForeignMethodBinding::new_for_foreign_class(
  module_name : String,
  class_name : String,
  signature : String,
  callback : (Int, Array[Value]) -> ForeignCallResult,
) -> ForeignMethodBinding {
  {
    module_name,
    class_name,
    is_static: false,
    signature,
    callback: None,
    handle_callback: Some(callback),
  }
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
  match self.callback {
    Some(callback) => callback(receiver, arguments)
    None => ForeignCallFailed("binding requires a foreign class receiver")
  }
}

///|
fn ForeignMethodBinding::call_handle(
  self : ForeignMethodBinding,
  handle : Int,
  arguments : Array[Value],
) -> ForeignCallResult {
  match self.handle_callback {
    Some(callback) => callback(handle, arguments)
    None => ForeignCallFailed("binding does not accept a foreign class handle")
  }
}

///|
fn ForeignMethodBinding::accepts_handle(self : ForeignMethodBinding) -> Bool {
  self.handle_callback is Some(_)
}
