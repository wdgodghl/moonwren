///|
/// Result produced by a MoonBit callback that implements a Wren foreign method.
pub(all) enum ForeignCallResult {
  ForeignCallSucceeded(Value)
  ForeignCallFailed(String)
}

///|
/// Runtime-independent value tree returned by a context-aware foreign method.
/// Lists and maps are materialized inside the receiving VM after the callback
/// returns, so host packages never need access to runtime object identifiers.
pub(all) enum ForeignOwnedValue {
  ForeignNull
  ForeignBool(Bool)
  ForeignNumber(Double)
  ForeignString(String)
  ForeignBytes(Array[Int32])
  ForeignRange(Double, Double, Bool)
  ForeignList(Array[ForeignOwnedValue])
  ForeignMap(Array[ForeignOwnedMapEntry])
  ForeignExisting(Value)
}

///|
pub(all) struct ForeignOwnedMapEntry {
  key : ForeignOwnedValue
  value : ForeignOwnedValue
}

///|
pub fn ForeignOwnedMapEntry::new(
  key : ForeignOwnedValue,
  value : ForeignOwnedValue,
) -> ForeignOwnedMapEntry {
  { key, value, }
}

///|
/// Arguments visible to a context-aware foreign method. The context is valid
/// only for the duration of its callback and cannot re-enter the VM.
pub struct ForeignCallContext {
  receiver : Value
  arguments : Array[Value]
}

///|
pub fn ForeignCallContext::receiver(self : ForeignCallContext) -> Value {
  self.receiver
}

///|
pub fn ForeignCallContext::argument_count(self : ForeignCallContext) -> Int32 {
  self.arguments.length()
}

///|
pub fn ForeignCallContext::argument(
  self : ForeignCallContext,
  index : Int32,
) -> Value? {
  if index < 0 || index >= self.arguments.length() {
    None
  } else {
    Some(self.arguments[index])
  }
}

///|
pub fn ForeignCallContext::arguments(self : ForeignCallContext) -> Array[Value] {
  self.arguments.copy()
}

///|
pub(all) enum ForeignContextResult {
  ForeignContextReturned(ForeignOwnedValue)
  ForeignContextAborted(String)
}

///|
/// Result returned while allocating the host-owned state of a foreign object.
/// The integer is an opaque handle chosen and managed by the embedding host.
pub(all) enum ForeignAllocationResult {
  ForeignAllocationSucceeded(Int32)
  ForeignAllocationFailed(String)
}

///|
/// Host lifecycle callbacks associated with one Wren `foreign class`.
pub struct ForeignClassBinding {
  module_name : String
  class_name : String
  allocate : (Array[Value]) -> ForeignAllocationResult
  finalize : (Int32) -> Unit
}

///|
pub fn ForeignClassBinding::new(
  module_name : String,
  class_name : String,
  allocate : (Array[Value]) -> ForeignAllocationResult,
  finalize : (Int32) -> Unit,
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
  handle : Int32,
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
  handle_callback : ((Int32, Array[Value]) -> ForeignCallResult)?
  context_callback : ((ForeignCallContext) -> ForeignContextResult)?
  handle_context_callback : ((Int32, ForeignCallContext) -> ForeignContextResult)?
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
    context_callback: None,
    handle_context_callback: None,
  }
}

///|
/// Bind an instance method that receives the opaque handle allocated for a
/// foreign class instead of the Wren receiver value.
pub fn ForeignMethodBinding::new_for_foreign_class(
  module_name : String,
  class_name : String,
  signature : String,
  callback : (Int32, Array[Value]) -> ForeignCallResult,
) -> ForeignMethodBinding {
  {
    module_name,
    class_name,
    is_static: false,
    signature,
    callback: None,
    handle_callback: Some(callback),
    context_callback: None,
    handle_context_callback: None,
  }
}

///|
/// Bind a method through the richer VM-independent context API. The callback
/// may return nested Lists and Maps, arbitrary String bytes, or pass through an
/// existing argument value without depending on private runtime identifiers.
pub fn ForeignMethodBinding::new_context(
  module_name : String,
  class_name : String,
  is_static : Bool,
  signature : String,
  callback : (ForeignCallContext) -> ForeignContextResult,
) -> ForeignMethodBinding {
  {
    module_name,
    class_name,
    is_static,
    signature,
    callback: None,
    handle_callback: None,
    context_callback: Some(callback),
    handle_context_callback: None,
  }
}

///|
/// Context-aware variant for an instance of a `foreign class`.
pub fn ForeignMethodBinding::new_context_for_foreign_class(
  module_name : String,
  class_name : String,
  signature : String,
  callback : (Int32, ForeignCallContext) -> ForeignContextResult,
) -> ForeignMethodBinding {
  {
    module_name,
    class_name,
    is_static: false,
    signature,
    callback: None,
    handle_callback: None,
    context_callback: None,
    handle_context_callback: Some(callback),
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
  handle : Int32,
  arguments : Array[Value],
) -> ForeignCallResult {
  match self.handle_callback {
    Some(callback) => callback(handle, arguments)
    None => ForeignCallFailed("binding does not accept a foreign class handle")
  }
}

///|
fn ForeignMethodBinding::accepts_handle(self : ForeignMethodBinding) -> Bool {
  self.handle_callback is Some(_) || self.handle_context_callback is Some(_)
}

///|
fn ForeignMethodBinding::accepts_context(self : ForeignMethodBinding) -> Bool {
  self.context_callback is Some(_) || self.handle_context_callback is Some(_)
}

///|
fn ForeignMethodBinding::call_context(
  self : ForeignMethodBinding,
  receiver : Value,
  arguments : Array[Value],
) -> ForeignContextResult {
  match self.context_callback {
    Some(callback) => callback({ receiver, arguments, })
    None => ForeignContextAborted("binding requires a foreign class receiver")
  }
}

///|
fn ForeignMethodBinding::call_handle_context(
  self : ForeignMethodBinding,
  handle : Int32,
  receiver : Value,
  arguments : Array[Value],
) -> ForeignContextResult {
  match self.handle_context_callback {
    Some(callback) => callback(handle, { receiver, arguments, })
    None =>
      ForeignContextAborted("binding does not accept a foreign class handle")
  }
}
