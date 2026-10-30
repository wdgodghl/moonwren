///|
/// Tokens and recoverable diagnostics produced from one source string.
pub(all) struct ScanResult {
  tokens : Array[Token]
  diagnostics : Array[Diagnostic]
}

///|
pub fn ScanResult::is_success(self : ScanResult) -> Bool {
  self.diagnostics.is_empty()
}

///|
priv struct Lexer {
  source : String
  tokens : Array[Token]
  diagnostics : Array[Diagnostic]
  mut start : Int32
  mut current : Int32
  mut start_line : Int32
  mut start_column : Int32
  mut line : Int32
  mut column : Int32
}

///|
fn Lexer::new(source : String) -> Lexer {
  {
    source,
    tokens: [],
    diagnostics: [],
    start: 0,
    current: 0,
    start_line: 1,
    start_column: 1,
    line: 1,
    column: 1,
  }
}

///|
fn Lexer::at_end(self : Lexer) -> Bool {
  self.current >= self.source.length()
}

///|
fn Lexer::position(self : Lexer) -> SourcePosition {
  { offset: self.current, line: self.line, column: self.column, }
}

///|
fn Lexer::span(self : Lexer) -> SourceSpan {
  {
    start: {
      offset: self.start,
      line: self.start_line,
      column: self.start_column,
    },
    end: self.position(),
  }
}

///|
fn Lexer::point_span(self : Lexer) -> SourceSpan {
  let position = self.position()
  { start: position, end: position, }
}

///|
fn Lexer::lexeme(self : Lexer) -> String {
  self.source[self.start:self.current].to_owned()
}

///|
fn Lexer::peek(self : Lexer) -> Int32 {
  if self.at_end() {
    -1
  } else {
    self.source.unsafe_get(self.current).to_int()
  }
}

///|
fn Lexer::peek_next(self : Lexer) -> Int32 {
  if self.current + 1 >= self.source.length() {
    -1
  } else {
    self.source.unsafe_get(self.current + 1).to_int()
  }
}

///|
fn Lexer::advance(self : Lexer) -> Int32 {
  let code = self.source.unsafe_get(self.current).to_int()
  self.current = self.current + 1
  self.column = self.column + 1
  code
}

///|
fn Lexer::consume_newline(self : Lexer) -> Unit {
  self.current = self.current + 1
  self.line = self.line + 1
  self.column = 1
}

///|
fn Lexer::matches(self : Lexer, expected : Int32) -> Bool {
  if self.peek() != expected {
    false
  } else {
    ignore(self.advance())
    true
  }
}

///|
fn Lexer::add(self : Lexer, kind : TokenKind) -> Unit {
  self.tokens.push(Token::new(kind, self.lexeme(), self.span()))
}

///|
fn Lexer::report(self : Lexer, code : DiagnosticCode, message : String) -> Unit {
  self.diagnostics.push(Diagnostic::new(Scan, code, message, self.span()))
}

///|
fn is_digit(code : Int32) -> Bool {
  code >= 48 && code <= 57
}

///|
fn is_hex_digit(code : Int32) -> Bool {
  is_digit(code) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102)
}

///|
fn is_alpha(code : Int32) -> Bool {
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 95 ||
  code >= 128
}

///|
fn is_alpha_numeric(code : Int32) -> Bool {
  is_alpha(code) || is_digit(code)
}

///|
fn Lexer::identifier(self : Lexer) -> Unit {
  while is_alpha_numeric(self.peek()) {
    ignore(self.advance())
  }
  let text = self.lexeme()
  let kind = if text.length() >= 2 &&
    text.unsafe_get(0).to_int() == 95 &&
    text.unsafe_get(1).to_int() == 95 {
    StaticField
  } else if text.length() >= 1 && text.unsafe_get(0).to_int() == 95 {
    Field
  } else {
    keyword_kind(text)
  }
  self.add(kind)
}

///|
fn Lexer::decimal_tail(self : Lexer) -> Unit {
  while is_digit(self.peek()) || self.peek() == 95 {
    ignore(self.advance())
  }
  if self.peek() == 46 && is_digit(self.peek_next()) {
    ignore(self.advance())
    while is_digit(self.peek()) || self.peek() == 95 {
      ignore(self.advance())
    }
  }
  if self.peek() == 69 || self.peek() == 101 {
    ignore(self.advance())
    if self.peek() == 43 || self.peek() == 45 {
      ignore(self.advance())
    }
    let exponent_start = self.current
    while is_digit(self.peek()) || self.peek() == 95 {
      ignore(self.advance())
    }
    if self.current == exponent_start {
      self.report(InvalidNumber, "expected exponent digits")
    }
  }
}

///|
fn Lexer::number(self : Lexer, first : Int32) -> Unit {
  if first == 48 && (self.peek() == 120 || self.peek() == 88) {
    ignore(self.advance())
    let digits_start = self.current
    while is_hex_digit(self.peek()) || self.peek() == 95 {
      ignore(self.advance())
    }
    if self.current == digits_start {
      self.report(InvalidNumber, "expected hexadecimal digits")
    }
  } else {
    self.decimal_tail()
  }
  if parse_number_value(self.lexeme()).is_inf() {
    self.report(InvalidNumber, "number literal is too large")
  }
  self.add(Number)
}

///|
fn valid_escape(code : Int32) -> Bool {
  code == 34 ||
  code == 37 ||
  code == 48 ||
  code == 85 ||
  code == 92 ||
  code == 97 ||
  code == 98 ||
  code == 101 ||
  code == 102 ||
  code == 110 ||
  code == 114 ||
  code == 116 ||
  code == 117 ||
  code == 120 ||
  code == 118
}

///|
fn Lexer::string(self : Lexer) -> Unit {
  let mut interpolation_depth = 0
  let mut expression_string = false
  while !self.at_end() {
    let code = self.peek()
    if interpolation_depth == 0 && code == 34 {
      break
    }
    if code == 10 {
      self.consume_newline()
    } else if code == 92 {
      ignore(self.advance())
      if self.at_end() {
        break
      }
      let escaped = self.advance()
      if !valid_escape(escaped) {
        self.report(InvalidEscape, "invalid string escape")
      } else {
        let digits = if escaped == 120 {
          2
        } else if escaped == 117 {
          4
        } else if escaped == 85 {
          8
        } else {
          0
        }
        for digit_index = 0; digit_index < digits; digit_index = digit_index + 1 {
          if !is_hex_digit(self.peek()) {
            self.report(InvalidEscape, "invalid string escape")
            break
          }
          ignore(self.advance())
        }
      }
    } else if interpolation_depth == 0 && code == 37 && self.peek_next() == 40 {
      ignore(self.advance())
      ignore(self.advance())
      interpolation_depth = 1
    } else if interpolation_depth > 0 {
      ignore(self.advance())
      if expression_string {
        if code == 34 {
          expression_string = false
        }
      } else if code == 34 {
        expression_string = true
      } else if code == 40 {
        interpolation_depth = interpolation_depth + 1
      } else if code == 41 {
        interpolation_depth = interpolation_depth - 1
      }
    } else {
      ignore(self.advance())
    }
  }
  if self.at_end() || interpolation_depth != 0 {
    self.diagnostics.push(
      Diagnostic::new(
        Scan,
        UnterminatedString,
        "unterminated string",
        self.point_span(),
      ),
    )
    return
  }
  ignore(self.advance())
  self.add(StringLiteral)
}

///|
fn Lexer::raw_string(self : Lexer) -> Unit {
  // The first quote was consumed by scan_one(). Consume the remaining two.
  ignore(self.advance())
  ignore(self.advance())
  while !self.at_end() {
    if self.peek() == 34 &&
      self.peek_next() == 34 &&
      self.current + 2 < self.source.length() &&
      self.source.unsafe_get(self.current + 2).to_int() == 34 {
      ignore(self.advance())
      ignore(self.advance())
      ignore(self.advance())
      self.add(StringLiteral)
      return
    }
    if self.peek() == 10 {
      self.consume_newline()
    } else {
      ignore(self.advance())
    }
  }
  self.diagnostics.push(
    Diagnostic::new(
      Scan,
      UnterminatedString,
      "unterminated raw string",
      self.point_span(),
    ),
  )
}

///|
fn Lexer::line_comment(self : Lexer) -> Unit {
  while !self.at_end() && self.peek() != 10 {
    ignore(self.advance())
  }
}

///|
fn Lexer::block_comment(self : Lexer) -> Unit {
  let mut depth = 1
  while depth > 0 && !self.at_end() {
    if self.peek() == 47 && self.peek_next() == 42 {
      ignore(self.advance())
      ignore(self.advance())
      depth = depth + 1
    } else if self.peek() == 42 && self.peek_next() == 47 {
      ignore(self.advance())
      ignore(self.advance())
      depth = depth - 1
    } else if self.peek() == 10 {
      self.consume_newline()
    } else {
      ignore(self.advance())
    }
  }
  if depth > 0 {
    self.diagnostics.push(
      Diagnostic::new(
        Scan,
        UnterminatedComment,
        "unterminated block comment",
        self.point_span(),
      ),
    )
  }
}

///|
fn Lexer::scan_one(self : Lexer) -> Unit {
  let code = self.advance()
  match code {
    40 => self.add(LeftParen)
    41 => self.add(RightParen)
    123 => self.add(LeftBrace)
    125 => self.add(RightBrace)
    91 => self.add(LeftBracket)
    93 => self.add(RightBracket)
    58 => self.add(Colon)
    44 => self.add(Comma)
    45 => self.add(Minus)
    43 => self.add(Plus)
    42 => self.add(Star)
    37 => self.add(Percent)
    94 => self.add(Caret)
    126 => self.add(Tilde)
    63 => self.add(Question)
    35 => self.add(Hash)
    46 =>
      if self.matches(46) {
        if self.matches(46) {
          self.add(DotDotDot)
        } else {
          self.add(DotDot)
        }
      } else {
        self.add(Dot)
      }
    124 => if self.matches(124) { self.add(PipePipe) } else { self.add(Pipe) }
    38 =>
      if self.matches(38) {
        self.add(AmpersandAmpersand)
      } else {
        self.add(Ampersand)
      }
    33 => if self.matches(61) { self.add(BangEqual) } else { self.add(Bang) }
    61 => if self.matches(61) { self.add(EqualEqual) } else { self.add(Equal) }
    60 =>
      if self.matches(61) {
        self.add(LessEqual)
      } else if self.matches(60) {
        self.add(LessLess)
      } else {
        self.add(Less)
      }
    62 =>
      if self.matches(61) {
        self.add(GreaterEqual)
      } else if self.matches(62) {
        self.add(GreaterGreater)
      } else {
        self.add(Greater)
      }
    47 =>
      if self.matches(47) {
        self.line_comment()
      } else if self.matches(42) {
        self.block_comment()
      } else {
        self.add(Slash)
      }
    34 =>
      if self.peek() == 34 && self.peek_next() == 34 {
        self.raw_string()
      } else {
        self.string()
      }
    10 => {
      self.line = self.line + 1
      self.column = 1
      self.add(Newline)
    }
    13 =>
      if self.peek() != 10 {
        self.line = self.line + 1
        self.column = 1
      }
    9 | 32 => ()
    _ =>
      if is_digit(code) {
        self.number(code)
      } else if is_alpha(code) {
        self.identifier()
      } else {
        self.report(UnexpectedCharacter, "unexpected character")
      }
  }
}

///|
fn Lexer::scan(self : Lexer) -> ScanResult {
  if self.current == 0 &&
    self.peek() == 35 &&
    self.peek_next() == 33 &&
    self.source.length() > 2 &&
    self.source.unsafe_get(2).to_int() == 47 {
    while !self.at_end() && self.peek() != 10 {
      ignore(self.advance())
    }
  }
  while !self.at_end() {
    self.start = self.current
    self.start_line = self.line
    self.start_column = self.column
    self.scan_one()
  }
  self.start = self.current
  self.start_line = self.line
  self.start_column = self.column
  self.add(Eof)
  { tokens: self.tokens, diagnostics: self.diagnostics, }
}

///|
/// Tokenize a Wren source string while collecting all recoverable scan errors.
pub fn scan(source : String) -> ScanResult {
  let normalized = if source.length() >= 1 &&
    source.unsafe_get(0).to_int() == 0xfeff {
    source[1:].to_owned()
  } else if source.length() >= 3 &&
    source.unsafe_get(0).to_int() == 0xef &&
    source.unsafe_get(1).to_int() == 0xbb &&
    source.unsafe_get(2).to_int() == 0xbf {
    source[3:].to_owned()
  } else {
    source
  }
  Lexer::new(normalized).scan()
}
