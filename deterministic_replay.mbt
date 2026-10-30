///|
pub(all) enum SchedulerReplayEvent {
  ReplayAdvance(Double)
  ReplayDeliver(Int32, ForeignOwnedValue)
  ReplayCancel(Int32)
  ReplayObserve(String)
}

///|
pub(all) struct SchedulerReplayLog {
  workload_digest : String
  events : Array[SchedulerReplayEvent]
}

///|
pub(all) enum SchedulerReplayResult {
  SchedulerReplayCompleted(Int32)
  SchedulerReplayDiverged(Int32, String, String)
  SchedulerReplayInvalid(String)
}

///|
pub(all) enum SchedulerReplayDecodeResult {
  SchedulerReplayDecoded(SchedulerReplayLog)
  SchedulerReplayDecodeFailed(String)
}

///|
pub struct VmSchedulerRecorder {
  scheduler : VmScheduler
  workload_digest : String
  events : Array[SchedulerReplayEvent]
}

///|
pub fn VmSchedulerRecorder::new(
  scheduler : VmScheduler,
  workload_digest : String,
) -> VmSchedulerRecorder {
  { scheduler, workload_digest, events: [], }
}

///|
fn replay_field(value : String) -> String {
  value.length().to_string() + "\n" + value
}

///|
fn encode_owned_value(value : ForeignOwnedValue) -> String? {
  match value {
    ForeignNull => Some("N")
    ForeignBool(item) => Some(if item { "B1" } else { "B0" })
    ForeignNumber(item) => Some("D" + replay_field(item.to_string()))
    ForeignString(item) => Some("S" + replay_field(item))
    ForeignBytes(bytes) => {
      let mut encoded = "X" + bytes.length().to_string() + "\n"
      for byte in bytes {
        if byte < 0 || byte > 255 {
          return None
        }
        encoded = encoded + byte.to_string() + "\n"
      }
      Some(encoded)
    }
    ForeignRange(from, to, inclusive) =>
      Some(
        "R" +
        replay_field(from.to_string()) +
        replay_field(to.to_string()) +
        (if inclusive { "1" } else { "0" }),
      )
    ForeignList(items) => {
      let mut encoded = "L" + items.length().to_string() + "\n"
      for item in items {
        let child = match encode_owned_value(item) {
          Some(value) => value
          None => return None
        }
        encoded = encoded + replay_field(child)
      }
      Some(encoded)
    }
    ForeignMap(entries) => {
      let mut encoded = "M" + entries.length().to_string() + "\n"
      for entry in entries {
        let key = match encode_owned_value(entry.key) {
          Some(value) => value
          None => return None
        }
        let item = match encode_owned_value(entry.value) {
          Some(value) => value
          None => return None
        }
        encoded = encoded + replay_field(key) + replay_field(item)
      }
      Some(encoded)
    }
    ForeignExisting(_) => None
  }
}

///|
fn replay_output(output : Array[String]) -> String {
  let mut encoded = output.length().to_string() + "\n"
  for line in output {
    encoded = encoded + replay_field(line)
  }
  encoded
}

///|
fn scheduler_event_fingerprint(
  scheduler : VmScheduler,
  event : VmSchedulerEvent,
) -> String {
  match event {
    VmSchedulerIdle => "I"
    VmSchedulerExternalRequest(task, request, output) => {
      let snapshot = match scheduler.snapshot_request(request) {
        Some(value) =>
          match encode_owned_value(value) {
            Some(encoded) => encoded
            None => "<unsupported>"
          }
        None => "<unavailable>"
      }
      "E" +
      task.to_string() +
      "\n" +
      replay_field(snapshot) +
      replay_output(output)
    }
    VmSchedulerTaskCompleted(task, value, output) => {
      let snapshot = match
        snapshot_scheduler_value(scheduler.vm.runtime(), value, 0) {
        Some(item) =>
          match encode_owned_value(item) {
            Some(encoded) => encoded
            None => "<unsupported>"
          }
        None => "<unsupported>"
      }
      "C" +
      task.to_string() +
      "\n" +
      replay_field(snapshot) +
      replay_output(output)
    }
    VmSchedulerTaskFailed(task, issues, output) => {
      let mut encoded = "F" + task.to_string() + "\n"
      encoded = encoded + issues.length().to_string() + "\n"
      for issue in issues {
        encoded = encoded + replay_field(issue.message)
      }
      encoded + replay_output(output)
    }
  }
}

///|
pub fn VmSchedulerRecorder::advance(
  self : VmSchedulerRecorder,
  milliseconds : Double,
) -> Bool {
  if self.scheduler.advance(milliseconds) {
    self.events.push(ReplayAdvance(milliseconds))
    true
  } else {
    false
  }
}

///|
pub fn VmSchedulerRecorder::poll(
  self : VmSchedulerRecorder,
) -> VmSchedulerEvent {
  let event = self.scheduler.poll()
  self.events.push(
    ReplayObserve(scheduler_event_fingerprint(self.scheduler, event)),
  )
  event
}

///|
pub fn VmSchedulerRecorder::deliver(
  self : VmSchedulerRecorder,
  task_identifier : Int32,
  response : ForeignOwnedValue,
) -> Bool {
  if encode_owned_value(response) is None {
    return false
  }
  if self.scheduler.deliver_owned(task_identifier, response) {
    self.events.push(ReplayDeliver(task_identifier, response))
    true
  } else {
    false
  }
}

///|
pub fn VmSchedulerRecorder::cancel(
  self : VmSchedulerRecorder,
  task_identifier : Int32,
) -> Bool {
  if self.scheduler.cancel(task_identifier) {
    self.events.push(ReplayCancel(task_identifier))
    true
  } else {
    false
  }
}

///|
pub fn VmSchedulerRecorder::log(
  self : VmSchedulerRecorder,
) -> SchedulerReplayLog {
  { workload_digest: self.workload_digest, events: self.events.copy(), }
}

///|
pub fn replay_scheduler_log(
  scheduler : VmScheduler,
  log : SchedulerReplayLog,
  expected_workload_digest : String,
) -> SchedulerReplayResult {
  if log.workload_digest != expected_workload_digest {
    return SchedulerReplayInvalid("workload digest mismatch")
  }
  for index = 0; index < log.events.length(); index = index + 1 {
    match log.events[index] {
      ReplayAdvance(milliseconds) =>
        if !scheduler.advance(milliseconds) {
          return SchedulerReplayInvalid("virtual time advance was rejected")
        }
      ReplayDeliver(task, response) =>
        if !scheduler.deliver_owned(task, response) {
          return SchedulerReplayInvalid("recorded response was rejected")
        }
      ReplayCancel(task) =>
        if !scheduler.cancel(task) {
          return SchedulerReplayInvalid("recorded cancellation was rejected")
        }
      ReplayObserve(expected) => {
        let actual = scheduler_event_fingerprint(scheduler, scheduler.poll())
        if actual != expected {
          return SchedulerReplayDiverged(index, expected, actual)
        }
      }
    }
  }
  SchedulerReplayCompleted(log.events.length())
}

///|
fn encode_replay_event(event : SchedulerReplayEvent) -> String? {
  match event {
    ReplayAdvance(milliseconds) =>
      Some("A" + replay_field(milliseconds.to_string()))
    ReplayDeliver(task, response) => {
      let value = match encode_owned_value(response) {
        Some(encoded) => encoded
        None => return None
      }
      Some("D" + task.to_string() + "\n" + replay_field(value))
    }
    ReplayCancel(task) => Some("C" + task.to_string() + "\n")
    ReplayObserve(fingerprint) => Some("O" + replay_field(fingerprint))
  }
}

///|
/// Encode a replay transcript into the deterministic MWR1 format.
pub fn encode_scheduler_replay_log(log : SchedulerReplayLog) -> String? {
  let mut encoded = "MWR1\n" +
    replay_field(log.workload_digest) +
    log.events.length().to_string() +
    "\n"
  for event in log.events {
    let record = match encode_replay_event(event) {
      Some(value) => value
      None => return None
    }
    encoded = encoded + replay_field(record)
  }
  Some(encoded)
}

///|
priv struct ReplayReader {
  characters : Array[Char]
  mut cursor : Int32
}

///|
fn ReplayReader::number(self : ReplayReader) -> Int32? {
  let value = archive_read_number(self.characters, self.cursor)
  match value {
    Some((number, next)) => {
      self.cursor = next
      Some(number)
    }
    None => None
  }
}

///|
fn ReplayReader::field(self : ReplayReader) -> String? {
  let length = match self.number() {
    Some(value) => value
    None => return None
  }
  match archive_take_text(self.characters, self.cursor, length) {
    Some((text, next)) => {
      self.cursor = next
      Some(text)
    }
    None => None
  }
}

///|
fn decode_owned_value(encoded : String) -> ForeignOwnedValue? {
  let reader : ReplayReader = { characters: encoded.to_array(), cursor: 0, }
  if reader.characters.is_empty() {
    return None
  }
  let tag = reader.characters[0]
  reader.cursor = 1
  let value = match tag {
    'N' => ForeignNull
    'B' => {
      if reader.cursor >= reader.characters.length() {
        return None
      }
      let flag = reader.characters[reader.cursor]
      reader.cursor = reader.cursor + 1
      if flag == '1' {
        ForeignBool(true)
      } else if flag == '0' {
        ForeignBool(false)
      } else {
        return None
      }
    }
    'D' => {
      let text = match reader.field() {
        Some(value) => value
        None => return None
      }
      let number = match state_parse_double(text) {
        Some(value) => value
        None => return None
      }
      ForeignNumber(number)
    }
    'S' =>
      match reader.field() {
        Some(value) => ForeignString(value)
        None => return None
      }
    'X' => {
      let count = match reader.number() {
        Some(value) => value
        None => return None
      }
      let bytes : Array[Int32] = []
      for _index = 0; _index < count; _index = _index + 1 {
        let byte = match reader.number() {
          Some(value) => value
          None => return None
        }
        if byte < 0 || byte > 255 {
          return None
        }
        bytes.push(byte)
      }
      ForeignBytes(bytes)
    }
    'R' => {
      let from_text = match reader.field() {
        Some(value) => value
        None => return None
      }
      let to_text = match reader.field() {
        Some(value) => value
        None => return None
      }
      let from = match state_parse_double(from_text) {
        Some(value) => value
        None => return None
      }
      let to = match state_parse_double(to_text) {
        Some(value) => value
        None => return None
      }
      if reader.cursor >= reader.characters.length() {
        return None
      }
      let inclusive = reader.characters[reader.cursor] == '1'
      reader.cursor = reader.cursor + 1
      ForeignRange(from, to, inclusive)
    }
    'L' => {
      let count = match reader.number() {
        Some(value) => value
        None => return None
      }
      let values : Array[ForeignOwnedValue] = []
      for _index = 0; _index < count; _index = _index + 1 {
        let child = match reader.field() {
          Some(value) => value
          None => return None
        }
        match decode_owned_value(child) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      ForeignList(values)
    }
    'M' => {
      let count = match reader.number() {
        Some(value) => value
        None => return None
      }
      let entries : Array[ForeignOwnedMapEntry] = []
      for _index = 0; _index < count; _index = _index + 1 {
        let key_text = match reader.field() {
          Some(value) => value
          None => return None
        }
        let value_text = match reader.field() {
          Some(value) => value
          None => return None
        }
        let key = match decode_owned_value(key_text) {
          Some(value) => value
          None => return None
        }
        let item = match decode_owned_value(value_text) {
          Some(value) => value
          None => return None
        }
        entries.push(ForeignOwnedMapEntry::new(key, item))
      }
      ForeignMap(entries)
    }
    _ => return None
  }
  if reader.cursor == reader.characters.length() {
    Some(value)
  } else {
    None
  }
}

///|
fn decode_replay_event(record : String) -> SchedulerReplayEvent? {
  let reader : ReplayReader = { characters: record.to_array(), cursor: 1, }
  if reader.characters.is_empty() {
    return None
  }
  let event = match reader.characters[0] {
    'A' => {
      let text = match reader.field() {
        Some(value) => value
        None => return None
      }
      match state_parse_double(text) {
        Some(value) => ReplayAdvance(value)
        None => return None
      }
    }
    'D' => {
      let task = match reader.number() {
        Some(value) => value
        None => return None
      }
      let encoded = match reader.field() {
        Some(value) => value
        None => return None
      }
      match decode_owned_value(encoded) {
        Some(value) => ReplayDeliver(task, value)
        None => return None
      }
    }
    'C' =>
      match reader.number() {
        Some(value) => ReplayCancel(value)
        None => return None
      }
    'O' =>
      match reader.field() {
        Some(value) => ReplayObserve(value)
        None => return None
      }
    _ => return None
  }
  if reader.cursor == reader.characters.length() {
    Some(event)
  } else {
    None
  }
}

///|
pub fn decode_scheduler_replay_log(
  encoded : String,
) -> SchedulerReplayDecodeResult {
  let characters = encoded.to_array()
  let header = ['M', 'W', 'R', '1', '\n']
  if characters.length() < header.length() {
    return SchedulerReplayDecodeFailed("replay log header is missing")
  }
  for index = 0; index < header.length(); index = index + 1 {
    if characters[index] != header[index] {
      return SchedulerReplayDecodeFailed("unsupported replay log format")
    }
  }
  let reader : ReplayReader = { characters, cursor: header.length(), }
  let digest = match reader.field() {
    Some(value) => value
    None => return SchedulerReplayDecodeFailed("invalid workload digest")
  }
  let count = match reader.number() {
    Some(value) => value
    None => return SchedulerReplayDecodeFailed("invalid replay event count")
  }
  let events : Array[SchedulerReplayEvent] = []
  for _index = 0; _index < count; _index = _index + 1 {
    let record = match reader.field() {
      Some(value) => value
      None => return SchedulerReplayDecodeFailed("truncated replay event")
    }
    match decode_replay_event(record) {
      Some(event) => events.push(event)
      None => return SchedulerReplayDecodeFailed("invalid replay event")
    }
  }
  if reader.cursor != characters.length() {
    SchedulerReplayDecodeFailed("unexpected trailing replay data")
  } else {
    SchedulerReplayDecoded({ workload_digest: digest, events, })
  }
}
