///|
/// Result of exporting selected module globals to a portable `MWS1` archive.
pub(all) enum VmStateSaveResult {
  VmStateSaved(String)
  VmStateSaveFailed(Diagnostic)
}

///|
/// Result of atomically restoring globals from a portable state archive.
pub(all) enum VmStateRestoreResult {
  VmStateRestored(Int)
  VmStateRestoreFailed(Diagnostic)
}

///|
priv enum StateNode {
  StateNull
  StateBool(Bool)
  StateNumber(String)
  StateString(String)
  StateRawString(Array[Int])
  StateRange(String, String, Bool)
  StateList(Array[Int])
  StateMap(Array[(Int, Int)])
}

///|
priv struct StateRoot {
  name : String
  node : Int
}

///|
priv struct StateDocument {
  module_name : String
  roots : Array[StateRoot]
  nodes : Array[StateNode]
}

///|
priv struct StateBuilder {
  context : RuntimeContext
  nodes : Array[StateNode]
  list_runtime_ids : Array[Int]
  list_node_ids : Array[Int]
  map_runtime_ids : Array[Int]
  map_node_ids : Array[Int]
}

///|
priv enum StateNodeResult {
  StateNodeEncoded(Int)
  StateNodeFailed(String)
}

///|
fn state_issue(message : String, module_name : String) -> Diagnostic {
  Diagnostic::new(Runtime, UnsupportedFeature, message, SourceSpan::empty()).with_source(
    module_name,
  )
}

///|
fn state_field(text : String) -> String {
  text.to_array().length().to_string() + "\n" + text
}

///|
fn state_find_runtime(
  runtime_ids : Array[Int],
  node_ids : Array[Int],
  identifier : Int,
) -> Int? {
  for index = 0; index < runtime_ids.length(); index = index + 1 {
    if runtime_ids[index] == identifier {
      return Some(node_ids[index])
    }
  }
  None
}

///|
fn state_bytes_text(bytes : Array[Int]) -> String {
  let digits = "0123456789abcdef"
  let mut text = ""
  for byte in bytes {
    let normalized = byte & 255
    text = text +
      digits.unsafe_get(normalized / 16).to_string() +
      digits.unsafe_get(normalized % 16).to_string()
  }
  text
}

///|
fn StateBuilder::encode_value(
  self : StateBuilder,
  value : Value,
  path : String,
) -> StateNodeResult {
  match value {
    NullValue => {
      let node = self.nodes.length()
      self.nodes.push(StateNull)
      StateNodeEncoded(node)
    }
    BoolValue(value) => {
      let node = self.nodes.length()
      self.nodes.push(StateBool(value))
      StateNodeEncoded(node)
    }
    NumberValue(value) => {
      let node = self.nodes.length()
      self.nodes.push(StateNumber(value.to_string()))
      StateNodeEncoded(node)
    }
    StringValue(value) => {
      let node = self.nodes.length()
      self.nodes.push(StateString(value))
      StateNodeEncoded(node)
    }
    RawStringValue(bytes) => {
      let copied : Array[Int] = []
      for byte in bytes {
        copied.push(byte)
      }
      let node = self.nodes.length()
      self.nodes.push(StateRawString(copied))
      StateNodeEncoded(node)
    }
    RangeValue(from, to, inclusive) => {
      let node = self.nodes.length()
      self.nodes.push(StateRange(from.to_string(), to.to_string(), inclusive))
      StateNodeEncoded(node)
    }
    ListValue(identifier) => {
      match
        state_find_runtime(
          self.list_runtime_ids,
          self.list_node_ids,
          identifier,
        ) {
        Some(node) => return StateNodeEncoded(node)
        None => ()
      }
      if identifier < 0 ||
        identifier >= self.context.lists.length() ||
        !self.context.lists[identifier].alive {
        return StateNodeFailed("\{path} refers to an unavailable List")
      }
      let node = self.nodes.length()
      self.nodes.push(StateNull)
      self.list_runtime_ids.push(identifier)
      self.list_node_ids.push(node)
      let children : Array[Int] = []
      let items = self.context.lists[identifier].items
      for index = 0; index < items.length(); index = index + 1 {
        match self.encode_value(items[index], "\{path}[\{index}]") {
          StateNodeEncoded(child) => children.push(child)
          StateNodeFailed(message) => return StateNodeFailed(message)
        }
      }
      self.nodes[node] = StateList(children)
      StateNodeEncoded(node)
    }
    MapValue(identifier) => {
      match
        state_find_runtime(self.map_runtime_ids, self.map_node_ids, identifier) {
        Some(node) => return StateNodeEncoded(node)
        None => ()
      }
      if identifier < 0 ||
        identifier >= self.context.maps.length() ||
        !self.context.maps[identifier].alive {
        return StateNodeFailed("\{path} refers to an unavailable Map")
      }
      let node = self.nodes.length()
      self.nodes.push(StateNull)
      self.map_runtime_ids.push(identifier)
      self.map_node_ids.push(node)
      let children : Array[(Int, Int)] = []
      let entries = self.context.maps[identifier].entries
      for index = 0; index < entries.length(); index = index + 1 {
        let key = match
          self.encode_value(entries[index].key, "\{path}.key[\{index}]") {
          StateNodeEncoded(child) => child
          StateNodeFailed(message) => return StateNodeFailed(message)
        }
        let item = match
          self.encode_value(entries[index].value, "\{path}.value[\{index}]") {
          StateNodeEncoded(child) => child
          StateNodeFailed(message) => return StateNodeFailed(message)
        }
        children.push((key, item))
      }
      self.nodes[node] = StateMap(children)
      StateNodeEncoded(node)
    }
    other =>
      StateNodeFailed(
        "\{path} contains unsupported runtime value \{other.type_name()}",
      )
  }
}

///|
fn encode_state_node(node : StateNode) -> String {
  match node {
    StateNull => "N"
    StateBool(value) => if value { "B1" } else { "B0" }
    StateNumber(value) => "D" + state_field(value)
    StateString(value) => "S" + state_field(value)
    StateRawString(bytes) => "X" + state_field(state_bytes_text(bytes))
    StateRange(from, to, inclusive) =>
      "R" +
      state_field(from) +
      state_field(to) +
      (if inclusive { "1" } else { "0" })
    StateList(children) => {
      let mut record = "L" + state_field(children.length().to_string())
      for child in children {
        record = record + state_field(child.to_string())
      }
      record
    }
    StateMap(children) => {
      let mut record = "M" + state_field(children.length().to_string())
      for (key, value) in children {
        record = record +
          state_field(key.to_string()) +
          state_field(value.to_string())
      }
      record
    }
  }
}

///|
fn encode_state_document(document : StateDocument) -> String {
  let mut payload = state_field(document.module_name) +
    state_field(document.roots.length().to_string())
  for root in document.roots {
    payload = payload +
      state_field(root.name) +
      state_field(root.node.to_string())
  }
  payload = payload + state_field(document.nodes.length().to_string())
  for node in document.nodes {
    payload = payload + state_field(encode_state_node(node))
  }
  let checksum = module_checksum(payload)
  "MWS1\n" + state_field(checksum) + payload
}

///|
/// Export selected globals. Primitive values, ranges, Strings (including raw
/// bytes), Lists and Maps are portable; graph identity and cycles are kept.
pub fn Vm::save_state(
  self : Vm,
  module_name : String,
  names : Array[String],
) -> VmStateSaveResult {
  if self.closed {
    return VmStateSaveFailed(state_issue("VM is closed", module_name))
  }
  let context = self.runtime()
  let module_index = match find_runtime_module(context, module_name) {
    Some(index) => index
    None =>
      return VmStateSaveFailed(
        state_issue("module '\{module_name}' is not loaded", module_name),
      )
  }
  let builder : StateBuilder = {
    context,
    nodes: [],
    list_runtime_ids: [],
    list_node_ids: [],
    map_runtime_ids: [],
    map_node_ids: [],
  }
  let roots : Array[StateRoot] = []
  for name in names {
    for root in roots {
      if root.name == name {
        return VmStateSaveFailed(
          state_issue("duplicate state root '\{name}'", module_name),
        )
      }
    }
    let value = match context.modules[module_index].environment.get(name) {
      Some(value) => value
      None =>
        return VmStateSaveFailed(
          state_issue(
            "module '\{module_name}' does not define '\{name}'",
            module_name,
          ),
        )
    }
    match builder.encode_value(value, name) {
      StateNodeEncoded(node) => roots.push({ name, node, })
      StateNodeFailed(message) =>
        return VmStateSaveFailed(state_issue(message, module_name))
    }
  }
  VmStateSaved(
    encode_state_document({ module_name, roots, nodes: builder.nodes, }),
  )
}

///|
priv struct StateReader {
  characters : Array[Char]
  mut cursor : Int
}

///|
fn StateReader::field(self : StateReader) -> String? {
  let (length, after_length) = match
    archive_read_number(self.characters, self.cursor) {
    Some(value) => value
    None => return None
  }
  let (value, after_value) = match
    archive_take_text(self.characters, after_length, length) {
    Some(value) => value
    None => return None
  }
  self.cursor = after_value
  Some(value)
}

///|
fn state_parse_nat(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0
  for character in text.to_array() {
    let code = character.to_int()
    if code < 48 || code > 57 {
      return None
    }
    value = value * 10 + code - 48
  }
  Some(value)
}

///|
fn StateReader::natural(self : StateReader) -> Int? {
  match self.field() {
    Some(text) => state_parse_nat(text)
    None => None
  }
}

///|
fn state_hex_value(code : Int) -> Int? {
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 97 && code <= 102 {
    Some(code - 87)
  } else {
    None
  }
}

///|
fn state_parse_bytes(text : String) -> Array[Int]? {
  let characters = text.to_array()
  if characters.length() % 2 != 0 {
    return None
  }
  let bytes : Array[Int] = []
  for index = 0; index < characters.length(); index = index + 2 {
    let high = match state_hex_value(characters[index].to_int()) {
      Some(value) => value
      None => return None
    }
    let low = match state_hex_value(characters[index + 1].to_int()) {
      Some(value) => value
      None => return None
    }
    bytes.push(high * 16 + low)
  }
  Some(bytes)
}

///|
fn state_parse_double(text : String) -> Double? {
  if text == "Infinity" || text == "infinity" {
    Some(@double.infinity)
  } else if text == "-Infinity" || text == "-infinity" {
    Some(-@double.infinity)
  } else if text == "NaN" || text == "nan" {
    Some(0x7ff8_0000_0000_0000UL.reinterpret_as_double())
  } else {
    parse_decimal_string(text)
  }
}

///|
fn decode_state_node(record : String) -> StateNode? {
  let characters = record.to_array()
  if characters.length() == 0 {
    return None
  }
  let tag = characters[0]
  let rest : Array[Char] = []
  for index = 1; index < characters.length(); index = index + 1 {
    rest.push(characters[index])
  }
  let reader : StateReader = { characters: rest, cursor: 0, }
  let parsed = match tag {
    'N' => StateNull
    'B' => {
      if rest.length() != 1 || (rest[0] != '0' && rest[0] != '1') {
        return None
      }
      reader.cursor = 1
      StateBool(rest[0] == '1')
    }
    'D' =>
      match reader.field() {
        Some(text) => StateNumber(text)
        None => return None
      }
    'S' =>
      match reader.field() {
        Some(text) => StateString(text)
        None => return None
      }
    'X' => {
      let text = match reader.field() {
        Some(text) => text
        None => return None
      }
      match state_parse_bytes(text) {
        Some(bytes) => StateRawString(bytes)
        None => return None
      }
    }
    'R' => {
      let from = match reader.field() {
        Some(text) => text
        None => return None
      }
      let to = match reader.field() {
        Some(text) => text
        None => return None
      }
      if reader.cursor >= rest.length() ||
        (rest[reader.cursor] != '0' && rest[reader.cursor] != '1') {
        return None
      }
      let inclusive = rest[reader.cursor] == '1'
      reader.cursor = reader.cursor + 1
      StateRange(from, to, inclusive)
    }
    'L' => {
      let count = match reader.natural() {
        Some(value) => value
        None => return None
      }
      if count > rest.length() {
        return None
      }
      let children : Array[Int] = []
      for child_index = 0; child_index < count; child_index = child_index + 1 {
        match reader.natural() {
          Some(child) => children.push(child)
          None => return None
        }
      }
      StateList(children)
    }
    'M' => {
      let count = match reader.natural() {
        Some(value) => value
        None => return None
      }
      if count > rest.length() {
        return None
      }
      let children : Array[(Int, Int)] = []
      for child_index = 0; child_index < count; child_index = child_index + 1 {
        let key = match reader.natural() {
          Some(value) => value
          None => return None
        }
        let value = match reader.natural() {
          Some(value) => value
          None => return None
        }
        children.push((key, value))
      }
      StateMap(children)
    }
    _ => return None
  }
  if reader.cursor == rest.length() {
    Some(parsed)
  } else {
    None
  }
}

///|
fn decode_state_document(archive : String) -> StateDocument? {
  let characters = archive.to_array()
  let header = ['M', 'W', 'S', '1', '\n']
  if characters.length() < header.length() {
    return None
  }
  for index = 0; index < header.length(); index = index + 1 {
    if characters[index] != header[index] {
      return None
    }
  }
  let reader : StateReader = { characters, cursor: 5, }
  let checksum = match reader.field() {
    Some(value) => value
    None => return None
  }
  let payload_start = reader.cursor
  let payload_chars : Array[Char] = []
  for index = payload_start; index < characters.length(); index = index + 1 {
    payload_chars.push(characters[index])
  }
  if module_checksum(String::from_array(payload_chars)) != checksum {
    return None
  }
  let module_name = match reader.field() {
    Some(value) => value
    None => return None
  }
  let root_count = match reader.natural() {
    Some(value) => value
    None => return None
  }
  if root_count > characters.length() {
    return None
  }
  let roots : Array[StateRoot] = []
  for root_index = 0; root_index < root_count; root_index = root_index + 1 {
    let name = match reader.field() {
      Some(value) => value
      None => return None
    }
    let node = match reader.natural() {
      Some(value) => value
      None => return None
    }
    for existing in roots {
      if existing.name == name {
        return None
      }
    }
    roots.push({ name, node, })
  }
  let node_count = match reader.natural() {
    Some(value) => value
    None => return None
  }
  if node_count > characters.length() {
    return None
  }
  let nodes : Array[StateNode] = []
  for node_index = 0; node_index < node_count; node_index = node_index + 1 {
    let record = match reader.field() {
      Some(value) => value
      None => return None
    }
    match decode_state_node(record) {
      Some(node) => nodes.push(node)
      None => return None
    }
  }
  if reader.cursor != characters.length() {
    return None
  }
  for root in roots {
    if root.node < 0 || root.node >= nodes.length() {
      return None
    }
  }
  for node in nodes {
    match node {
      StateList(children) =>
        for child in children {
          if child < 0 || child >= nodes.length() {
            return None
          }
        }
      StateMap(children) =>
        for (key, value) in children {
          if key < 0 ||
            key >= nodes.length() ||
            value < 0 ||
            value >= nodes.length() {
            return None
          }
        }
      _ => ()
    }
  }
  Some({ module_name, roots, nodes, })
}

///|
fn materialize_state(
  document : StateDocument,
  context : RuntimeContext,
) -> Array[Value]? {
  let values : Array[Value] = []
  for node in document.nodes {
    let value = match node {
      StateNull => Value::null()
      StateBool(value) => Value::bool(value)
      StateNumber(text) =>
        match state_parse_double(text) {
          Some(value) => Value::number(value)
          None => return None
        }
      StateString(value) => Value::string(value)
      StateRawString(bytes) => Value::raw_string(bytes)
      StateRange(from, to, inclusive) => {
        let from_value = match state_parse_double(from) {
          Some(value) => value
          None => return None
        }
        let to_value = match state_parse_double(to) {
          Some(value) => value
          None => return None
        }
        Value::range(from_value, to_value, inclusive)
      }
      StateList(_) => context.new_list([])
      StateMap(_) => context.new_map()
    }
    values.push(value)
  }
  for index = 0; index < document.nodes.length(); index = index + 1 {
    match document.nodes[index] {
      StateList(children) => {
        let identifier = match values[index] {
          ListValue(identifier) => identifier
          _ => return None
        }
        for child in children {
          context.lists[identifier].items.push(values[child])
        }
      }
      StateMap(children) => {
        let identifier = match values[index] {
          MapValue(identifier) => identifier
          _ => return None
        }
        for (key, item) in children {
          if !is_valid_map_key(values[key]) ||
            !context.set_map_entry(identifier, values[key], values[item]) {
            return None
          }
        }
      }
      _ => ()
    }
  }
  Some(values)
}

///|
/// Restore an `MWS1` archive into its named loaded module. All names and graph
/// records are validated before any module binding is changed.
pub fn Vm::restore_state(self : Vm, archive : String) -> VmStateRestoreResult {
  if self.closed {
    return VmStateRestoreFailed(state_issue("VM is closed", "<state>"))
  }
  let document = match decode_state_document(archive) {
    Some(document) => document
    None =>
      return VmStateRestoreFailed(
        state_issue("invalid or corrupted MWS1 state archive", "<state>"),
      )
  }
  let context = self.runtime()
  let module_index = match find_runtime_module(context, document.module_name) {
    Some(index) => index
    None =>
      return VmStateRestoreFailed(
        state_issue(
          "module '\{document.module_name}' is not loaded",
          document.module_name,
        ),
      )
  }
  for root in document.roots {
    if context.modules[module_index].environment.get(root.name) is None {
      return VmStateRestoreFailed(
        state_issue(
          "module '\{document.module_name}' does not define '\{root.name}'",
          document.module_name,
        ),
      )
    }
  }
  let values = match materialize_state(document, context) {
    Some(values) => values
    None =>
      return VmStateRestoreFailed(
        state_issue("state graph contains invalid values", document.module_name),
      )
  }
  for root in document.roots {
    ignore(
      context.modules[module_index].environment.assign(
        root.name,
        values[root.node],
      ),
    )
  }
  VmStateRestored(document.roots.length())
}
