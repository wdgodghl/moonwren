///|
/// A generation-checked handle for host-owned objects referenced by foreign
/// Wren instances. It prevents stale identifiers from observing reused slots.
pub(all) struct HostObjectHandle {
  slot : Int
  generation : Int
} derive(Eq, Debug)

///|
pub extend HostObjectHandle with Eq::{equal, not_equal}

///|
pub extend HostObjectHandle with Debug::{to_repr}

///|
pub struct HostObjectSlot[T] {
  mut value : T?
  mut generation : Int
}

///|
/// Small host-side arena useful when implementing `ForeignClassBinding`.
pub struct HostObjectTable[T] {
  slots : Array[HostObjectSlot[T]]
}

///|
pub fn[T] HostObjectTable::new() -> HostObjectTable[T] {
  { slots: [], }
}

///|
pub fn[T] HostObjectTable::insert(
  self : HostObjectTable[T],
  value : T,
) -> HostObjectHandle {
  for index = 0; index < self.slots.length(); index = index + 1 {
    if self.slots[index].value is None {
      let slot = self.slots[index]
      slot.value = Some(value)
      return { slot: index, generation: slot.generation, }
    }
  }
  self.slots.push({ value: Some(value), generation: 0, })
  { slot: self.slots.length() - 1, generation: 0, }
}

///|
pub fn[T] HostObjectTable::get(
  self : HostObjectTable[T],
  handle : HostObjectHandle,
) -> T? {
  if handle.slot < 0 || handle.slot >= self.slots.length() {
    return None
  }
  let slot = self.slots[handle.slot]
  if slot.generation != handle.generation {
    None
  } else {
    slot.value
  }
}

///|
pub fn[T] HostObjectTable::release(
  self : HostObjectTable[T],
  handle : HostObjectHandle,
) -> Bool {
  if handle.slot < 0 || handle.slot >= self.slots.length() {
    return false
  }
  let slot = self.slots[handle.slot]
  if slot.generation != handle.generation || slot.value is None {
    false
  } else {
    slot.value = None
    slot.generation = slot.generation + 1
    true
  }
}

///|
pub fn[T] HostObjectTable::live_count(self : HostObjectTable[T]) -> Int {
  let mut count = 0
  for slot in self.slots {
    if slot.value is Some(_) {
      count = count + 1
    }
  }
  count
}
