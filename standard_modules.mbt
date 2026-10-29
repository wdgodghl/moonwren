///|
let standard_json_source =
  #|class Json {
  #|  foreign static parse(text)
  #|  static stringify(value) { return encode_(value, []) }
  #|  static encode_(value, seen) {
  #|    if (value == null) return "null"
  #|    if (value is Bool || value is Num) {
  #|      if (value is Num && (value.isNan || value.isInfinity)) Fiber.abort("JSON numbers must be finite.")
  #|      return value.toString
  #|    }
  #|    if (value is String) return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\b", "\\b").replace("\f", "\\f").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\""
  #|    if (!(value is List) && !(value is Map)) Fiber.abort("Value is not JSON serializable.")
  #|    for (parent in seen) if (Object.same(parent, value)) Fiber.abort("JSON value contains a cycle.")
  #|    seen.add(value)
  #|    var parts = []
  #|    if (value is List) {
  #|      for (item in value) parts.add(encode_(item, seen))
  #|      seen.removeAt(seen.count - 1)
  #|      return "[" + parts.join(",") + "]"
  #|    }
  #|    for (entry in value) {
  #|      if (!(entry.key is String)) Fiber.abort("JSON object keys must be Strings.")
  #|      parts.add(encode_(entry.key, seen) + ":" + encode_(entry.value, seen))
  #|    }
  #|    seen.removeAt(seen.count - 1)
  #|    return "{" + parts.join(",") + "}"
  #|  }
  #|}

///|
let standard_base64_source =
  #|class Base64 {
  #|  foreign static encode(text)
  #|  foreign static decode(text)
  #|}

///|
let standard_url_source =
  #|class Url {
  #|  foreign static encodeComponent(text)
  #|  foreign static decodeComponent(text)
  #|}

///|
let standard_uuid_source =
  #|class Uuid {
  #|  foreign static fromName(namespace, name)
  #|}

///|
let standard_http_source =
  #|class Http {
  #|  static request(method, url) { return request(method, url, {}, null) }
  #|  static request(method, url, headers) { return request(method, url, headers, null) }
  #|  static request(method, url, headers, body) {
  #|    if (!(method is String) || !(url is String) || !(headers is Map)) Fiber.abort("Http.request expects method, URL, and a header Map.")
  #|    return Fiber.yield({"$moonwren": "http", "method": method, "url": url, "headers": headers, "body": body})
  #|  }
  #|  static get(url) { return request("GET", url) }
  #|}

///|
fn standard_module_source(name : String) -> String? {
  match name {
    "moon/json" => Some(standard_json_source)
    "moon/base64" => Some(standard_base64_source)
    "moon/url" => Some(standard_url_source)
    "moon/uuid" => Some(standard_uuid_source)
    "moon/http" => Some(standard_http_source)
    _ => None
  }
}

///|
priv struct StandardJsonParser {
  characters : Array[Char]
  mut cursor : Int
  mut failure : String?
}

///|
fn StandardJsonParser::new(text : String) -> StandardJsonParser {
  { characters: text.to_array(), cursor: 0, failure: None, }
}

///|
fn StandardJsonParser::skip_space(self : StandardJsonParser) -> Unit {
  while self.cursor < self.characters.length() {
    let code = self.characters[self.cursor].to_int()
    if code == 32 || code == 9 || code == 10 || code == 13 {
      self.cursor = self.cursor + 1
    } else {
      break
    }
  }
}

///|
fn StandardJsonParser::fail(
  self : StandardJsonParser,
  message : String,
) -> Unit {
  if self.failure is None {
    self.failure = Some(message + " at character " + self.cursor.to_string())
  }
}

///|
fn StandardJsonParser::take(self : StandardJsonParser, expected : Int) -> Bool {
  if self.cursor < self.characters.length() &&
    self.characters[self.cursor].to_int() == expected {
    self.cursor = self.cursor + 1
    true
  } else {
    false
  }
}

///|
fn StandardJsonParser::literal(
  self : StandardJsonParser,
  text : String,
) -> Bool {
  let expected = text.to_array()
  if self.cursor + expected.length() > self.characters.length() {
    return false
  }
  for index = 0; index < expected.length(); index = index + 1 {
    if self.characters[self.cursor + index] != expected[index] {
      return false
    }
  }
  self.cursor = self.cursor + expected.length()
  true
}

///|
fn standard_hex_digit(code : Int) -> Int? {
  if code >= 48 && code <= 57 {
    Some(code - 48)
  } else if code >= 65 && code <= 70 {
    Some(code - 55)
  } else if code >= 97 && code <= 102 {
    Some(code - 87)
  } else {
    None
  }
}

///|
fn StandardJsonParser::unicode_escape(self : StandardJsonParser) -> Int? {
  if self.cursor + 4 > self.characters.length() {
    return None
  }
  let mut value = 0
  for _index = 0; _index < 4; _index = _index + 1 {
    let digit = match
      standard_hex_digit(self.characters[self.cursor].to_int()) {
      Some(value) => value
      None => return None
    }
    value = value * 16 + digit
    self.cursor = self.cursor + 1
  }
  Some(value)
}

///|
fn StandardJsonParser::string(self : StandardJsonParser) -> String? {
  if !self.take(34) {
    return None
  }
  let bytes : Array[Int] = []
  while self.cursor < self.characters.length() {
    let code = self.characters[self.cursor].to_int()
    self.cursor = self.cursor + 1
    if code == 34 {
      return match string_value_from_bytes(bytes) {
        StringValue(text) => Some(text)
        _ => None
      }
    }
    if code < 32 {
      self.fail("unescaped control character in JSON string")
      return None
    }
    if code != 92 {
      append_utf8_bytes(bytes, code)
      continue
    }
    if self.cursor >= self.characters.length() {
      return None
    }
    let escaped = self.characters[self.cursor].to_int()
    self.cursor = self.cursor + 1
    match escaped {
      34 | 47 | 92 => bytes.push(escaped)
      98 => bytes.push(8)
      102 => bytes.push(12)
      110 => bytes.push(10)
      114 => bytes.push(13)
      116 => bytes.push(9)
      117 => {
        let mut point = match self.unicode_escape() {
          Some(value) => value
          None => return None
        }
        if point >= 0xd800 && point <= 0xdbff {
          if !self.take(92) || !self.take(117) {
            return None
          }
          let low = match self.unicode_escape() {
            Some(value) => value
            None => return None
          }
          if low < 0xdc00 || low > 0xdfff {
            return None
          }
          point = 0x10000 + ((point - 0xd800) << 10) + low - 0xdc00
        } else if point >= 0xdc00 && point <= 0xdfff {
          return None
        }
        append_utf8_bytes(bytes, point)
      }
      _ => return None
    }
  }
  None
}

///|
fn StandardJsonParser::number(self : StandardJsonParser) -> ForeignOwnedValue? {
  let start = self.cursor
  ignore(self.take(45))
  if self.take(48) {
    if self.cursor < self.characters.length() {
      let next = self.characters[self.cursor].to_int()
      if next >= 48 && next <= 57 {
        return None
      }
    }
  } else {
    if self.cursor >= self.characters.length() {
      return None
    }
    let first = self.characters[self.cursor].to_int()
    if first < 49 || first > 57 {
      return None
    }
    self.cursor = self.cursor + 1
    while self.cursor < self.characters.length() {
      let code = self.characters[self.cursor].to_int()
      if code < 48 || code > 57 {
        break
      }
      self.cursor = self.cursor + 1
    }
  }
  if self.take(46) {
    let fraction_start = self.cursor
    while self.cursor < self.characters.length() {
      let code = self.characters[self.cursor].to_int()
      if code < 48 || code > 57 {
        break
      }
      self.cursor = self.cursor + 1
    }
    if self.cursor == fraction_start {
      return None
    }
  }
  if self.cursor < self.characters.length() &&
    (
      self.characters[self.cursor].to_int() == 69 ||
      self.characters[self.cursor].to_int() == 101
    ) {
    self.cursor = self.cursor + 1
    if self.cursor < self.characters.length() &&
      (
        self.characters[self.cursor].to_int() == 43 ||
        self.characters[self.cursor].to_int() == 45
      ) {
      self.cursor = self.cursor + 1
    }
    let exponent_start = self.cursor
    while self.cursor < self.characters.length() {
      let code = self.characters[self.cursor].to_int()
      if code < 48 || code > 57 {
        break
      }
      self.cursor = self.cursor + 1
    }
    if self.cursor == exponent_start {
      return None
    }
  }
  let text = String::from_array(self.characters[start:self.cursor].to_owned())
  let number = parse_number_value(text)
  if number.is_inf() || number.is_nan() {
    None
  } else {
    Some(ForeignNumber(number))
  }
}

///|
fn StandardJsonParser::array(self : StandardJsonParser) -> ForeignOwnedValue? {
  if !self.take(91) {
    return None
  }
  self.skip_space()
  let values : Array[ForeignOwnedValue] = []
  if self.take(93) {
    return Some(ForeignList(values))
  }
  while true {
    let value = match self.value() {
      Some(value) => value
      None => return None
    }
    values.push(value)
    self.skip_space()
    if self.take(93) {
      return Some(ForeignList(values))
    }
    if !self.take(44) {
      return None
    }
    self.skip_space()
  } nobreak {
    None
  }
}

///|
fn StandardJsonParser::object(self : StandardJsonParser) -> ForeignOwnedValue? {
  if !self.take(123) {
    return None
  }
  self.skip_space()
  let entries : Array[ForeignOwnedMapEntry] = []
  if self.take(125) {
    return Some(ForeignMap(entries))
  }
  while true {
    let key = match self.string() {
      Some(value) => value
      None => return None
    }
    self.skip_space()
    if !self.take(58) {
      return None
    }
    self.skip_space()
    let value = match self.value() {
      Some(value) => value
      None => return None
    }
    entries.push(ForeignOwnedMapEntry::new(ForeignString(key), value))
    self.skip_space()
    if self.take(125) {
      return Some(ForeignMap(entries))
    }
    if !self.take(44) {
      return None
    }
    self.skip_space()
  } nobreak {
    None
  }
}

///|
fn StandardJsonParser::value(self : StandardJsonParser) -> ForeignOwnedValue? {
  self.skip_space()
  if self.cursor >= self.characters.length() {
    return None
  }
  match self.characters[self.cursor].to_int() {
    34 =>
      match self.string() {
        Some(text) => Some(ForeignString(text))
        None => None
      }
    91 => self.array()
    123 => self.object()
    116 => if self.literal("true") { Some(ForeignBool(true)) } else { None }
    102 => if self.literal("false") { Some(ForeignBool(false)) } else { None }
    110 => if self.literal("null") { Some(ForeignNull) } else { None }
    _ => self.number()
  }
}

///|
fn parse_standard_json(text : String) -> Result[ForeignOwnedValue, String] {
  let parser = StandardJsonParser::new(text)
  let value = match parser.value() {
    Some(value) => value
    None =>
      return Err(
        match parser.failure {
          Some(message) => message
          None => "invalid JSON at character " + parser.cursor.to_string()
        },
      )
  }
  parser.skip_space()
  if parser.cursor != parser.characters.length() {
    Err("unexpected JSON data at character " + parser.cursor.to_string())
  } else {
    Ok(value)
  }
}

///|
fn standard_string_argument(
  call : ForeignCallContext,
  index : Int,
  label : String,
) -> Result[String, String] {
  match call.argument(index) {
    Some(value) =>
      match value.as_string() {
        ValueConverted(text) => Ok(text)
        ValueConversionFailed(_, received) =>
          Err("\{label} must be a String, received \{received}")
      }
    None => Err("\{label} is missing")
  }
}

///|
fn url_unreserved(byte : Int) -> Bool {
  (byte >= 65 && byte <= 90) ||
  (byte >= 97 && byte <= 122) ||
  (byte >= 48 && byte <= 57) ||
  byte == 45 ||
  byte == 46 ||
  byte == 95 ||
  byte == 126
}

///|
fn encode_url_component(text : String) -> String {
  let hex = "0123456789ABCDEF"
  let result : Array[Char] = []
  for byte in @utf8.encode(text) {
    let value = byte.to_int()
    if url_unreserved(value) {
      result.push(byte.to_char())
    } else {
      result.push('%')
      result.push(hex.unsafe_get(value >> 4).to_byte().to_char())
      result.push(hex.unsafe_get(value & 15).to_byte().to_char())
    }
  }
  String::from_array(result)
}

///|
fn decode_url_component(text : String) -> String? {
  let characters = text.to_array()
  let bytes : Array[Byte] = []
  let mut index = 0
  while index < characters.length() {
    if characters[index] == '%' {
      if index + 2 >= characters.length() {
        return None
      }
      let high = match standard_hex_digit(characters[index + 1].to_int()) {
        Some(value) => value
        None => return None
      }
      let low = match standard_hex_digit(characters[index + 2].to_int()) {
        Some(value) => value
        None => return None
      }
      bytes.push((high * 16 + low).to_byte())
      index = index + 3
    } else {
      let encoded = @utf8.encode(String::from_array([characters[index]]))
      for byte in encoded {
        bytes.push(byte)
      }
      index = index + 1
    }
  }
  Some(@utf8.decode(Bytes::from_array(bytes))) catch {
    _ => None
  }
}

///|
fn name_uuid(scope_name : String, name : String) -> String {
  let digest = sha256_hex(scope_name + "\u0000" + name).to_array()
  digest[12] = '8'
  digest[16] = '8'
  String::from_array(digest[0:8].to_owned()) +
  "-" +
  String::from_array(digest[8:12].to_owned()) +
  "-" +
  String::from_array(digest[12:16].to_owned()) +
  "-" +
  String::from_array(digest[16:20].to_owned()) +
  "-" +
  String::from_array(digest[20:32].to_owned())
}

///|
fn append_standard_module_bindings(
  methods : Array[ForeignMethodBinding],
) -> Unit {
  methods.push(
    ForeignMethodBinding::new_context("moon/json", "Json", true, "parse(_)", fn(
      call,
    ) {
      let text = match standard_string_argument(call, 0, "JSON text") {
        Ok(value) => value
        Err(message) => return ForeignContextAborted(message)
      }
      match parse_standard_json(text) {
        Ok(value) => ForeignContextReturned(value)
        Err(message) => ForeignContextAborted(message)
      }
    }),
  )
  methods.push(
    ForeignMethodBinding::new_context(
      "moon/base64",
      "Base64",
      true,
      "encode(_)",
      fn(call) {
        let text = match standard_string_argument(call, 0, "text") {
          Ok(value) => value
          Err(message) => return ForeignContextAborted(message)
        }
        ForeignContextReturned(
          ForeignString(@base64.encode(@utf8.encode(text), padding=true)),
        )
      },
    ),
  )
  methods.push(
    ForeignMethodBinding::new_context(
      "moon/base64",
      "Base64",
      true,
      "decode(_)",
      fn(call) {
        let text = match standard_string_argument(call, 0, "Base64 text") {
          Ok(value) => value
          Err(message) => return ForeignContextAborted(message)
        }
        let bytes = @base64.decode(text) catch {
          _ => return ForeignContextAborted("invalid Base64 text")
        }
        let raw : Array[Int] = []
        for byte in bytes {
          raw.push(byte.to_int())
        }
        ForeignContextReturned(ForeignBytes(raw))
      },
    ),
  )
  for signature in ["encodeComponent(_)", "decodeComponent(_)"] {
    methods.push(
      ForeignMethodBinding::new_context("moon/url", "Url", true, signature, fn(
        call,
      ) {
        let text = match standard_string_argument(call, 0, "URL text") {
          Ok(value) => value
          Err(message) => return ForeignContextAborted(message)
        }
        if signature == "encodeComponent(_)" {
          ForeignContextReturned(ForeignString(encode_url_component(text)))
        } else {
          match decode_url_component(text) {
            Some(value) => ForeignContextReturned(ForeignString(value))
            None => ForeignContextAborted("invalid URL component encoding")
          }
        }
      }),
    )
  }
  methods.push(
    ForeignMethodBinding::new_context(
      "moon/uuid",
      "Uuid",
      true,
      "fromName(_,_)",
      fn(call) {
        let scope_name = match standard_string_argument(call, 0, "namespace") {
          Ok(value) => value
          Err(message) => return ForeignContextAborted(message)
        }
        let name = match standard_string_argument(call, 1, "name") {
          Ok(value) => value
          Err(message) => return ForeignContextAborted(message)
        }
        ForeignContextReturned(ForeignString(name_uuid(scope_name, name)))
      },
    ),
  )
}
