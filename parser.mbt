///|
pub(all) enum ExpressionParseResult {
  ExpressionParsed(Expr)
  ExpressionParseFailed(Array[Diagnostic])
}

///|
pub(all) enum ProgramParseResult {
  ProgramParsed(Array[Stmt])
  ProgramParseFailed(Array[Diagnostic])
}

///|
priv struct Parser {
  tokens : Array[Token]
  diagnostics : Array[Diagnostic]
  mut current : Int
  mut current_method_name : String
  mut current_method_is_constructor : Bool
}

///|
fn Parser::new(tokens : Array[Token]) -> Parser {
  {
    tokens,
    diagnostics: [],
    current: 0,
    current_method_name: "",
    current_method_is_constructor: false,
  }
}

///|
fn Parser::current_token(self : Parser) -> Token {
  self.tokens[self.current]
}

///|
fn Parser::previous(self : Parser) -> Token {
  self.tokens[self.current - 1]
}

///|
fn Parser::check(self : Parser, kind : TokenKind) -> Bool {
  self.current_token().kind == kind
}

///|
fn Parser::advance(self : Parser) -> Token {
  if !self.check(Eof) {
    self.current = self.current + 1
  }
  self.previous()
}

///|
fn Parser::take(self : Parser, kind : TokenKind) -> Bool {
  if self.check(kind) {
    ignore(self.advance())
    true
  } else {
    false
  }
}

///|
fn Parser::report(
  self : Parser,
  code : DiagnosticCode,
  message : String,
  span : SourceSpan,
) -> Unit {
  self.diagnostics.push(Diagnostic::new(Parse, code, message, span))
}

///|
fn Parser::consume(self : Parser, kind : TokenKind, message : String) -> Token {
  if self.check(kind) {
    self.advance()
  } else {
    let token = self.current_token()
    self.report(ExpectedToken, message, token.span)
    token
  }
}

///|
fn Parser::skip_newlines(self : Parser) -> Unit {
  while self.take(Newline) {

  }
}

///|
fn clean_number(text : String) -> String {
  text.replace_all(old="_", new="")
}

///|
fn hex_value(code : Int) -> Int {
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 55
  } else {
    code - 87
  }
}

///|
fn parse_number_value(text : String) -> Double {
  let normalized = clean_number(text)
  if normalized.length() >= 2 &&
    normalized.unsafe_get(0).to_int() == 48 &&
    (
      normalized.unsafe_get(1).to_int() == 120 ||
      normalized.unsafe_get(1).to_int() == 88
    ) {
    let mut value = 0.0
    for index = 2; index < normalized.length(); index = index + 1 {
      value = value * 16.0 +
        Double::from_int(hex_value(normalized.unsafe_get(index).to_int()))
    }
    return value
  }
  let mut index = 0
  let mut value = 0.0
  let mut decimal_digits = 0
  let mut after_decimal = false
  while index < normalized.length() {
    let code = normalized.unsafe_get(index).to_int()
    if is_digit(code) {
      value = value * 10.0 + Double::from_int(code - 48)
      if after_decimal {
        decimal_digits = decimal_digits + 1
      }
      index = index + 1
    } else if code == 46 {
      after_decimal = true
      index = index + 1
    } else {
      break
    }
  }
  let mut explicit_exponent = 0
  if index < normalized.length() &&
    (
      normalized.unsafe_get(index).to_int() == 69 ||
      normalized.unsafe_get(index).to_int() == 101
    ) {
    index = index + 1
    let mut sign = 1
    if index < normalized.length() &&
      normalized.unsafe_get(index).to_int() == 45 {
      sign = -1
      index = index + 1
    } else if index < normalized.length() &&
      normalized.unsafe_get(index).to_int() == 43 {
      index = index + 1
    }
    while index < normalized.length() {
      explicit_exponent = explicit_exponent * 10 +
        normalized.unsafe_get(index).to_int() -
        48
      index = index + 1
    }
    if sign < 0 {
      explicit_exponent = -explicit_exponent
    }
  }
  let exponent = explicit_exponent - decimal_digits
  let mut power = 0
  if exponent < 0 {
    while power < -exponent {
      value = value / 10.0
      power = power + 1
    }
  } else {
    while power < exponent {
      value = value * 10.0
      power = power + 1
    }
  }
  value
}

///|
fn append_utf8_bytes(bytes : Array[Int], code_point : Int) -> Unit {
  if code_point <= 0x7f {
    bytes.push(code_point)
  } else if code_point <= 0x7ff {
    bytes.push(0xc0 | (code_point >> 6))
    bytes.push(0x80 | (code_point & 0x3f))
  } else if code_point <= 0xffff {
    bytes.push(0xe0 | (code_point >> 12))
    bytes.push(0x80 | ((code_point >> 6) & 0x3f))
    bytes.push(0x80 | (code_point & 0x3f))
  } else {
    bytes.push(0xf0 | (code_point >> 18))
    bytes.push(0x80 | ((code_point >> 12) & 0x3f))
    bytes.push(0x80 | ((code_point >> 6) & 0x3f))
    bytes.push(0x80 | (code_point & 0x3f))
  }
}

///|
fn decode_string_value(text : String) -> Value {
  let bytes : Array[Int] = []
  let characters = text[1:text.length() - 1].to_owned().to_array()
  let mut index = 0
  while index < characters.length() {
    let code = characters[index].to_int()
    if code == 13 {
      bytes.push(10)
      index = index + 1
      if index < characters.length() && characters[index].to_int() == 10 {
        index = index + 1
      }
      continue
    }
    if code != 92 {
      append_utf8_bytes(bytes, code)
      index = index + 1
      continue
    }
    index = index + 1
    let escaped = characters[index].to_int()
    index = index + 1
    match escaped {
      34 => bytes.push(34)
      37 => bytes.push(37)
      48 => bytes.push(0)
      92 => bytes.push(92)
      97 => bytes.push(7)
      98 => bytes.push(8)
      101 => bytes.push(27)
      102 => bytes.push(12)
      110 => bytes.push(10)
      114 => bytes.push(13)
      116 => bytes.push(9)
      118 => bytes.push(11)
      120 | 117 | 85 => {
        let digit_count = if escaped == 120 {
          2
        } else if escaped == 117 {
          4
        } else {
          8
        }
        let mut value = 0
        for digit_index = 0
            digit_index < digit_count
            digit_index = digit_index + 1 {
          value = value * 16 + hex_value(characters[index].to_int())
          index = index + 1
        }
        if escaped == 120 {
          bytes.push(value)
        } else {
          append_utf8_bytes(bytes, value)
        }
      }
      _ => bytes.push(escaped)
    }
  }
  string_value_from_bytes(bytes)
}

///|
fn only_horizontal_whitespace(text : String) -> Bool {
  for character in text {
    let code = character.to_int()
    if code != 32 && code != 9 && code != 13 {
      return false
    }
  }
  true
}

///|
/// Source-file line endings are lexical newlines, not String data chosen by
/// the host checkout mode. Normalize CRLF and lone CR while decoding literal
/// text; an explicit `\r` escape in a regular String remains byte 13.
fn normalize_literal_newlines(text : String) -> String {
  let result : Array[Char] = []
  let characters = text.to_array()
  let mut index = 0
  while index < characters.length() {
    if characters[index].to_int() == 13 {
      result.push('\n')
      index = index + 1
      if index < characters.length() && characters[index].to_int() == 10 {
        index = index + 1
      }
    } else {
      result.push(characters[index])
      index = index + 1
    }
  }
  String::from_array(result)
}

///|
fn decode_raw_string_value(text : String) -> Value {
  let mut content = normalize_literal_newlines(
    text[3:text.length() - 3].to_owned(),
  )
  let mut first_newline = -1
  for index = 0; index < content.length(); index = index + 1 {
    if content.unsafe_get(index).to_int() == 10 {
      first_newline = index
      break
    }
  }
  if first_newline >= 0 &&
    only_horizontal_whitespace(content[0:first_newline].to_owned()) {
    content = content[first_newline + 1:content.length()].to_owned()
  }
  let mut last_newline = -1
  for index = 0; index < content.length(); index = index + 1 {
    if content.unsafe_get(index).to_int() == 10 {
      last_newline = index
    }
  }
  if last_newline >= 0 &&
    only_horizontal_whitespace(
      content[last_newline + 1:content.length()].to_owned(),
    ) {
    content = content[0:last_newline].to_owned()
  }
  Value::string(content)
}

///|
fn decode_string(text : String) -> String {
  match decode_string_value(text) {
    StringValue(decoded) => decoded
    RawStringValue(bytes) => string_display_from_bytes(bytes)
    _ => abort("decoded string literal must be a String")
  }
}

///|
fn Parser::interpolated_string(self : Parser, token : Token) -> Expr {
  let content = token.lexeme[1:token.lexeme.length() - 1].to_owned()
  let parts : Array[Expr] = []
  let mut segment_start = 0
  let mut index = 0
  while index + 1 < content.length() {
    let code = content.unsafe_get(index).to_int()
    if code == 92 {
      index = index + 2
      continue
    }
    if code != 37 || content.unsafe_get(index + 1).to_int() != 40 {
      index = index + 1
      continue
    }
    let prefix = content[segment_start:index].to_owned()
    parts.push(Literal(decode_string_value("\"" + prefix + "\""), token.span))
    let expression_start = index + 2
    let mut cursor = expression_start
    let mut depth = 1
    let mut in_string = false
    while cursor < content.length() && depth > 0 {
      let current = content.unsafe_get(cursor).to_int()
      if in_string {
        if current == 92 {
          cursor = cursor + 2
          continue
        }
        if current == 34 {
          in_string = false
        }
      } else if current == 34 {
        in_string = true
      } else if current == 40 {
        depth = depth + 1
      } else if current == 41 {
        depth = depth - 1
      }
      cursor = cursor + 1
    }
    if depth != 0 {
      self.report(
        ExpectedToken,
        "unterminated interpolation expression",
        token.span,
      )
      return Literal(decode_string_value(token.lexeme), token.span)
    }
    let source = content[expression_start:cursor - 1].to_owned()
    let expression = if only_horizontal_whitespace(source) {
      let position : SourcePosition = {
        offset: token.span.end.offset,
        line: token.span.end.line + 1,
        column: 1,
      }
      self.report(ExpectedExpression, "expected interpolation expression", {
        start: position,
        end: position,
      })
      Literal(Value::null(), token.span)
    } else {
      match parse_expression(source) {
        ExpressionParsed(expression) => expression
        ExpressionParseFailed(issues) => {
          for issue in issues {
            self.diagnostics.push(issue)
          }
          Literal(Value::null(), token.span)
        }
      }
    }
    parts.push(PropertyGet(expression, "toString", token.span))
    segment_start = cursor
    index = cursor
  }
  let suffix = content[segment_start:content.length()].to_owned()
  parts.push(Literal(decode_string_value("\"" + suffix + "\""), token.span))
  let mut result = parts[0]
  for part_index = 1; part_index < parts.length(); part_index = part_index + 1 {
    result = Binary(result, Add, parts[part_index], token.span)
  }
  result
}

///|
fn Parser::primary(self : Parser) -> Expr {
  let token = self.current_token()
  if self.take(FalseKeyword) {
    Literal(Value::bool(false), token.span)
  } else if self.take(TrueKeyword) {
    Literal(Value::bool(true), token.span)
  } else if self.take(NullKeyword) {
    Literal(Value::null(), token.span)
  } else if self.take(Number) {
    Literal(Value::number(parse_number_value(token.lexeme)), token.span)
  } else if self.take(StringLiteral) {
    if token.lexeme.has_prefix("\"\"\"") {
      Literal(decode_raw_string_value(token.lexeme), token.span)
    } else if token.lexeme.contains("%(") {
      self.interpolated_string(token)
    } else {
      Literal(decode_string_value(token.lexeme), token.span)
    }
  } else if self.take(Identifier) {
    Variable(token.lexeme, token.span)
  } else if self.take(Field) {
    FieldGet(token.lexeme, token.span)
  } else if self.take(StaticField) {
    StaticFieldGet(token.lexeme, token.span)
  } else if self.take(ThisKeyword) {
    Variable("this", token.span)
  } else if self.take(SuperKeyword) {
    Variable("$super", token.span)
  } else if self.take(LeftBracket) {
    self.skip_newlines()
    let items : Array[Expr] = []
    if !self.check(RightBracket) {
      while true {
        items.push(self.expression())
        if !self.take(Comma) {
          self.skip_newlines()
          break
        }
        self.skip_newlines()
        if self.check(RightBracket) {
          break
        }
      }
    }
    let closing = self.consume(RightBracket, "expected ']' after list literal")
    ListLiteral(items, SourceSpan::merge(token.span, closing.span))
  } else if self.take(LeftBrace) {
    self.skip_newlines()
    let entries : Array[MapEntryExpr] = []
    if !self.check(RightBrace) {
      while true {
        let key = self.expression()
        match key {
          Binary(_, _, _, span) | Conditional(_, _, _, span) =>
            self.report(
              UnexpectedToken,
              "map keys containing operators must be parenthesized",
              span,
            )
          _ => ()
        }
        self.skip_newlines()
        ignore(self.consume(Colon, "expected ':' after map key"))
        self.skip_newlines()
        let value = self.expression()
        entries.push({ key, value, })
        self.skip_newlines()
        if !self.take(Comma) {
          break
        }
        self.skip_newlines()
        if self.check(RightBrace) {
          break
        }
      }
    }
    let closing = self.consume(RightBrace, "expected '}' after map literal")
    MapLiteral(entries, SourceSpan::merge(token.span, closing.span))
  } else if self.take(LeftParen) {
    self.skip_newlines()
    let inner = self.expression()
    self.skip_newlines()
    let closing = self.consume(RightParen, "expected ')' after expression")
    Grouping(inner, SourceSpan::merge(token.span, closing.span))
  } else {
    self.report(ExpectedExpression, "expected expression", token.span)
    if !self.check(Eof) {
      ignore(self.advance())
    }
    Literal(Value::null(), token.span)
  }
}

///|
fn Parser::function_literal(self : Parser, start : SourceSpan) -> Expr {
  ignore(self.consume(LeftBrace, "expected '{' after function constructor"))
  let mut multiline = false
  if self.take(Newline) {
    multiline = true
    self.skip_newlines()
  }
  let parameters : Array[String] = []
  if self.take(Pipe) {
    if self.check(Pipe) {
      self.report(
        UnexpectedToken,
        "an empty parameter list must omit the pipes",
        self.current_token().span,
      )
    } else {
      while true {
        let parameter = self.consume(Identifier, "expected parameter name")
        parameters.push(parameter.lexeme)
        if !self.take(Comma) {
          break
        }
      }
    }
    ignore(self.consume(Pipe, "expected '|' after parameters"))
    if self.take(Newline) {
      multiline = true
      self.skip_newlines()
    }
  }
  let body : Array[Stmt] = []
  if multiline {
    while !self.check(RightBrace) && !self.check(Eof) {
      let statement = self.declaration()
      if self.check(RightBrace) &&
        statement.span().end.line == self.current_token().span.start.line {
        self.report(
          ExpectedToken,
          "expected newline before '}' in a statement block",
          statement.span(),
        )
      }
      body.push(statement)
      self.skip_newlines()
    }
  } else if !self.check(RightBrace) {
    let expression = self.expression()
    body.push(ExpressionStatement(expression, expression.span()))
    if self.check(Newline) {
      self.report(
        ExpectedToken,
        "a single-expression function must close on the same line",
        expression.span(),
      )
      self.skip_newlines()
    }
  }
  if multiline {
    body.push(ReturnStatement(None, self.current_token().span))
  }
  let closing = self.consume(RightBrace, "expected '}' after function body")
  FunctionLiteral(parameters, body, SourceSpan::merge(start, closing.span))
}

///|
fn Parser::method_call(self : Parser) -> Expr {
  let mut receiver = self.primary()
  let super_span = match receiver {
    Variable("$super", span) => Some(span)
    _ => None
  }
  match super_span {
    Some(start) =>
      if self.take(LeftParen) {
        self.skip_newlines()
        let arguments : Array[Expr] = []
        if !self.check(RightParen) {
          while true {
            arguments.push(self.expression())
            self.skip_newlines()
            if !self.take(Comma) {
              break
            }
            self.skip_newlines()
          }
        }
        let closing = self.consume(
          RightParen,
          "expected ')' after superclass constructor arguments",
        )
        receiver = SuperConstructorCall(
          arguments,
          SourceSpan::merge(start, closing.span),
        )
      }
    None => ()
  }
  while true {
    if self.check(Newline) {
      let checkpoint = self.current
      self.skip_newlines()
      if !self.check(Dot) {
        self.current = checkpoint
      }
    }
    let implicit_name = match receiver {
      Variable(name, _) if name != "$super" => Some(name)
      _ => None
    }
    match implicit_name {
      Some(name) =>
        if self.take(LeftParen) {
          self.skip_newlines()
          let arguments : Array[Expr] = []
          if !self.check(RightParen) {
            while true {
              arguments.push(self.expression())
              self.skip_newlines()
              if !self.take(Comma) {
                break
              }
              self.skip_newlines()
            }
          }
          let closing = self.consume(RightParen, "expected ')' after arguments")
          receiver = MethodCall(
            Variable("this", receiver.span()),
            name,
            arguments,
            SourceSpan::merge(receiver.span(), closing.span),
          )
          continue
        }
      None => ()
    }
    if self.take(Dot) {
      self.skip_newlines()
      let name = self.consume(Identifier, "expected method name after '.'")
      let is_function_literal = match receiver {
        Variable("Fn", _) | Variable("Fiber", _) =>
          name.lexeme == "new" && self.check(LeftBrace)
        _ => false
      }
      if is_function_literal {
        let owner = receiver
        let literal = self.function_literal(owner.span())
        receiver = match owner {
          Variable("Fiber", _) =>
            MethodCall(
              owner,
              "new",
              [literal],
              SourceSpan::merge(owner.span(), literal.span()),
            )
          _ => literal
        }
      } else if self.take(LeftParen) {
        self.skip_newlines()
        let arguments : Array[Expr] = []
        if !self.check(RightParen) {
          while true {
            arguments.push(self.expression())
            self.skip_newlines()
            if !self.take(Comma) {
              break
            }
            self.skip_newlines()
          }
        }
        let closing = self.consume(RightParen, "expected ')' after arguments")
        receiver = MethodCall(
          receiver,
          name.lexeme,
          arguments,
          SourceSpan::merge(receiver.span(), closing.span),
        )
      } else {
        receiver = PropertyGet(
          receiver,
          name.lexeme,
          SourceSpan::merge(receiver.span(), name.span),
        )
      }
      if !is_function_literal && self.check(LeftBrace) {
        let literal = self.function_literal(receiver.span())
        receiver = match receiver {
          MethodCall(owner, method_name, arguments, call_span) => {
            arguments.push(literal)
            MethodCall(
              owner,
              method_name,
              arguments,
              SourceSpan::merge(call_span, literal.span()),
            )
          }
          PropertyGet(owner, method_name, call_span) =>
            MethodCall(
              owner,
              method_name,
              [literal],
              SourceSpan::merge(call_span, literal.span()),
            )
          expression => expression
        }
      }
    } else if self.take(LeftBracket) {
      self.skip_newlines()
      let arguments : Array[Expr] = [self.expression()]
      self.skip_newlines()
      while self.take(Comma) {
        self.skip_newlines()
        arguments.push(self.expression())
        self.skip_newlines()
      }
      let closing = self.consume(RightBracket, "expected ']' after subscript")
      let call_span = SourceSpan::merge(receiver.span(), closing.span)
      receiver = if arguments.length() == 1 {
        SubscriptGet(receiver, arguments[0], call_span)
      } else {
        MethodCall(receiver, "[]", arguments, call_span)
      }
    } else {
      break
    }
  }
  match receiver {
    Variable("$super", span) if self.current_method_name != "" =>
      if self.current_method_is_constructor {
        self.report(
          ExpectedToken,
          "expected '(' after 'super' in a constructor",
          span,
        )
      } else {
        receiver = PropertyGet(receiver, self.current_method_name, span)
      }
    _ => ()
  }
  receiver
}

///|
fn Parser::unary(self : Parser) -> Expr {
  let token = self.current_token()
  let operator = if self.take(Bang) {
    Some(LogicalNot)
  } else if self.take(Minus) {
    Some(Negate)
  } else if self.take(Tilde) {
    Some(BitwiseNot)
  } else {
    None
  }
  match operator {
    Some(operator) => {
      self.skip_newlines()
      let right = self.unary()
      Unary(operator, right, SourceSpan::merge(token.span, right.span()))
    }
    None => self.method_call()
  }
}

///|
fn Parser::factor(self : Parser) -> Expr {
  let mut expression = self.unary()
  while true {
    let operator = if self.take(Star) {
      Some(Multiply)
    } else if self.take(Slash) {
      Some(Divide)
    } else if self.take(Percent) {
      Some(Remainder)
    } else {
      None
    }
    match operator {
      Some(operator) => {
        self.skip_newlines()
        let right = self.unary()
        let span = SourceSpan::merge(expression.span(), right.span())
        expression = Binary(expression, operator, right, span)
      }
      None => break
    }
  }
  expression
}

///|
fn Parser::term(self : Parser) -> Expr {
  let mut expression = self.factor()
  while true {
    let operator = if self.take(Plus) {
      Some(Add)
    } else if self.take(Minus) {
      Some(Subtract)
    } else {
      None
    }
    match operator {
      Some(operator) => {
        self.skip_newlines()
        let right = self.factor()
        let span = SourceSpan::merge(expression.span(), right.span())
        expression = Binary(expression, operator, right, span)
      }
      None => break
    }
  }
  expression
}

///|
fn Parser::shift(self : Parser) -> Expr {
  let mut expression = self.term()
  while true {
    let operator = if self.take(LessLess) {
      Some(ShiftLeft)
    } else if self.take(GreaterGreater) {
      Some(ShiftRight)
    } else {
      None
    }
    match operator {
      Some(operator) => {
        self.skip_newlines()
        let right = self.term()
        let span = SourceSpan::merge(expression.span(), right.span())
        expression = Binary(expression, operator, right, span)
      }
      None => break
    }
  }
  expression
}

///|
fn Parser::range(self : Parser) -> Expr {
  let mut expression = self.shift()
  if self.take(DotDot) {
    self.skip_newlines()
    let right = self.shift()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, InclusiveRange, right, span)
  } else if self.take(DotDotDot) {
    self.skip_newlines()
    let right = self.shift()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, ExclusiveRange, right, span)
  }
  expression
}

///|
fn Parser::comparison(self : Parser) -> Expr {
  let mut expression = self.range()
  while true {
    let operator = if self.take(Less) {
      Some(LessThan)
    } else if self.take(LessEqual) {
      Some(LessThanOrEqual)
    } else if self.take(Greater) {
      Some(GreaterThan)
    } else if self.take(GreaterEqual) {
      Some(GreaterThanOrEqual)
    } else if self.take(IsKeyword) {
      Some(IsType)
    } else {
      None
    }
    match operator {
      Some(operator) => {
        self.skip_newlines()
        let right = self.range()
        let span = SourceSpan::merge(expression.span(), right.span())
        expression = Binary(expression, operator, right, span)
      }
      None => break
    }
  }
  expression
}

///|
fn Parser::equality(self : Parser) -> Expr {
  let mut expression = self.comparison()
  while true {
    let operator = if self.take(EqualEqual) {
      Some(EqualTo)
    } else if self.take(BangEqual) {
      Some(NotEqualTo)
    } else {
      None
    }
    match operator {
      Some(operator) => {
        self.skip_newlines()
        let right = self.comparison()
        let span = SourceSpan::merge(expression.span(), right.span())
        expression = Binary(expression, operator, right, span)
      }
      None => break
    }
  }
  expression
}

///|
fn Parser::bitwise_and(self : Parser) -> Expr {
  let mut expression = self.equality()
  while self.take(Ampersand) {
    self.skip_newlines()
    let right = self.equality()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, BitwiseAnd, right, span)
  }
  expression
}

///|
fn Parser::bitwise_xor(self : Parser) -> Expr {
  let mut expression = self.bitwise_and()
  while self.take(Caret) {
    self.skip_newlines()
    let right = self.bitwise_and()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, BitwiseXor, right, span)
  }
  expression
}

///|
fn Parser::bitwise_or(self : Parser) -> Expr {
  let mut expression = self.bitwise_xor()
  while self.take(Pipe) {
    self.skip_newlines()
    let right = self.bitwise_xor()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, BitwiseOr, right, span)
  }
  expression
}

///|
fn Parser::logical_and(self : Parser) -> Expr {
  let mut expression = self.bitwise_or()
  while self.take(AmpersandAmpersand) {
    self.skip_newlines()
    let right = self.bitwise_or()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, LogicalAnd, right, span)
  }
  expression
}

///|
fn Parser::logical_or(self : Parser) -> Expr {
  let mut expression = self.logical_and()
  while self.take(PipePipe) {
    self.skip_newlines()
    let right = self.logical_and()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, LogicalOr, right, span)
  }
  expression
}

///|
fn Parser::conditional(self : Parser) -> Expr {
  let condition = self.logical_or()
  if self.take(Question) {
    self.skip_newlines()
    let then_branch = self.expression()
    match then_branch {
      Conditional(_, _, _, nested_span) =>
        self.report(
          UnexpectedToken,
          "a conditional expression in the then branch must be parenthesized",
          nested_span,
        )
      _ => ()
    }
    ignore(self.consume(Colon, "expected ':' in conditional expression"))
    self.skip_newlines()
    let else_branch = self.conditional()
    let span = SourceSpan::merge(condition.span(), else_branch.span())
    Conditional(condition, then_branch, else_branch, span)
  } else {
    condition
  }
}

///|
fn Parser::assignment(self : Parser) -> Expr {
  let target = self.conditional()
  if self.take(Equal) {
    self.skip_newlines()
    let value = self.assignment()
    match target {
      Variable(name, target_span) =>
        Assign(name, value, SourceSpan::merge(target_span, value.span()))
      FieldGet(name, target_span) =>
        FieldAssign(name, value, SourceSpan::merge(target_span, value.span()))
      StaticFieldGet(name, target_span) =>
        StaticFieldAssign(
          name,
          value,
          SourceSpan::merge(target_span, value.span()),
        )
      SubscriptGet(receiver, index, target_span) =>
        SubscriptSet(
          receiver,
          index,
          value,
          SourceSpan::merge(target_span, value.span()),
        )
      MethodCall(receiver, "[]", arguments, target_span) => {
        arguments.push(value)
        MethodCall(
          receiver,
          "[]=",
          arguments,
          SourceSpan::merge(target_span, value.span()),
        )
      }
      PropertyGet(receiver, name, target_span) =>
        PropertySet(
          receiver,
          name,
          value,
          SourceSpan::merge(target_span, value.span()),
        )
      _ => {
        self.report(
          UnexpectedToken,
          "assignment target must be a variable, field, property, or subscript",
          target.span(),
        )
        target
      }
    }
  } else {
    target
  }
}

///|
fn Parser::expression(self : Parser) -> Expr {
  self.assignment()
}

///|
fn Parser::finish_statement(self : Parser) -> Unit {
  if self.take(Newline) {
    self.skip_newlines()
  } else if !self.check(RightBrace) &&
    !self.check(ElseKeyword) &&
    !self.check(Eof) {
    self.report(
      ExpectedToken,
      "expected newline after statement",
      self.current_token().span,
    )
    while !self.check(Newline) &&
          !self.check(RightBrace) &&
          !self.check(ElseKeyword) &&
          !self.check(Eof) {
      ignore(self.advance())
    }
    self.skip_newlines()
  }
}

///|
fn Parser::variable_declaration(self : Parser, start : Token) -> Stmt {
  let name = self.consume(Identifier, "expected variable name")
  let initializer = if self.take(Equal) {
    self.skip_newlines()
    Some(self.expression())
  } else {
    None
  }
  let end_span = match initializer {
    Some(expression) => expression.span()
    None => name.span
  }
  self.finish_statement()
  VariableStatement(
    name.lexeme,
    initializer,
    SourceSpan::merge(start.span, end_span),
  )
}

///|
fn Parser::import_declaration(self : Parser, start : Token) -> Stmt {
  self.skip_newlines()
  let module_token = self.consume(
    StringLiteral,
    "expected module string after import",
  )
  let module_name = decode_string(module_token.lexeme)
  let bindings : Array[ImportBinding] = []
  let mut end_span = module_token.span
  let after_module = self.current
  self.skip_newlines()
  if self.take(ForKeyword) {
    self.skip_newlines()
    while true {
      let imported = self.consume(Identifier, "expected imported name")
      let binding_token = if self.take(AsKeyword) {
        self.consume(Identifier, "expected alias after 'as'")
      } else {
        imported
      }
      bindings.push({ name: imported.lexeme, local_name: binding_token.lexeme, })
      end_span = binding_token.span
      let after_binding = self.current
      self.skip_newlines()
      if !self.take(Comma) {
        self.current = after_binding
        break
      }
      self.skip_newlines()
    }
  } else {
    self.current = after_module
  }
  self.finish_statement()
  ImportStatement(
    module_name,
    bindings,
    SourceSpan::merge(start.span, end_span),
  )
}

///|
fn Parser::block_statement(self : Parser, opening : Token) -> Stmt {
  self.skip_newlines()
  let statements : Array[Stmt] = []
  while !self.check(RightBrace) && !self.check(Eof) {
    statements.push(self.declaration())
    self.skip_newlines()
  }
  let closing = self.consume(RightBrace, "expected '}' after block")
  BlockStatement(statements, SourceSpan::merge(opening.span, closing.span))
}

///|
fn Parser::condition_in_parentheses(self : Parser, owner : String) -> Expr {
  ignore(self.consume(LeftParen, "expected '(' after \{owner}"))
  self.skip_newlines()
  let condition = self.expression()
  self.skip_newlines()
  ignore(self.consume(RightParen, "expected ')' after condition"))
  condition
}

///|
fn Parser::if_statement(self : Parser, start : Token) -> Stmt {
  let condition = self.condition_in_parentheses("if")
  self.skip_newlines()
  let then_branch = self.statement()
  self.skip_newlines()
  let else_branch = if self.take(ElseKeyword) {
    if self.check(Newline) {
      self.report(
        ExpectedExpression,
        "expected statement on the same line after 'else'",
        self.previous().span,
      )
    }
    self.skip_newlines()
    Some(self.statement())
  } else {
    None
  }
  let end_span = match else_branch {
    Some(branch) => branch.span()
    None => then_branch.span()
  }
  IfStatement(
    condition,
    then_branch,
    else_branch,
    SourceSpan::merge(start.span, end_span),
  )
}

///|
fn Parser::while_statement(self : Parser, start : Token) -> Stmt {
  let condition = self.condition_in_parentheses("while")
  self.skip_newlines()
  let body = self.statement()
  let span = SourceSpan::merge(start.span, body.span())
  WhileStatement(condition, body, span)
}

///|
fn Parser::for_statement(self : Parser, start : Token) -> Stmt {
  ignore(self.consume(LeftParen, "expected '(' after for"))
  let name = self.consume(Identifier, "expected loop variable name")
  ignore(self.consume(InKeyword, "expected 'in' after loop variable"))
  self.skip_newlines()
  let sequence = self.expression()
  self.skip_newlines()
  ignore(self.consume(RightParen, "expected ')' after loop sequence"))
  self.skip_newlines()
  let body = self.statement()
  ForStatement(
    name.lexeme,
    sequence,
    body,
    SourceSpan::merge(start.span, body.span()),
  )
}

///|
fn Parser::return_statement(self : Parser, start : Token) -> Stmt {
  let value = if self.check(Newline) ||
    self.check(RightBrace) ||
    self.check(Eof) {
    None
  } else {
    Some(self.expression())
  }
  let end_span = match value {
    Some(expression) => expression.span()
    None => start.span
  }
  self.finish_statement()
  ReturnStatement(value, SourceSpan::merge(start.span, end_span))
}

///|
fn Parser::parameter_list(self : Parser) -> Array[String] {
  let parameters : Array[String] = []
  self.skip_newlines()
  if !self.check(RightParen) {
    while true {
      let parameter = self.consume(Identifier, "expected parameter name")
      if string_array_contains(parameters, parameter.lexeme) {
        self.report(
          DuplicateVariable,
          "duplicate parameter '\{parameter.lexeme}'",
          parameter.span,
        )
      }
      parameters.push(parameter.lexeme)
      self.skip_newlines()
      if !self.take(Comma) {
        break
      }
      self.skip_newlines()
    }
  }
  ignore(self.consume(RightParen, "expected ')' after parameters"))
  parameters
}

///|
fn Parser::attribute_value(self : Parser) -> Value {
  let token = self.current_token()
  if self.take(StringLiteral) {
    if token.lexeme.has_prefix("\"\"\"") {
      decode_raw_string_value(token.lexeme)
    } else {
      decode_string_value(token.lexeme)
    }
  } else if self.take(Number) {
    Value::number(parse_number_value(token.lexeme))
  } else if self.take(TrueKeyword) {
    Value::bool(true)
  } else if self.take(FalseKeyword) {
    Value::bool(false)
  } else if self.take(NullKeyword) {
    Value::null()
  } else if self.take(Identifier) {
    Value::string(token.lexeme)
  } else {
    self.report(
      ExpectedExpression,
      "expected literal attribute value",
      token.span,
    )
    if !self.check(Eof) {
      ignore(self.advance())
    }
    Value::null()
  }
}

///|
fn Parser::attributes(self : Parser) -> Array[AttributeDecl] {
  let attributes : Array[AttributeDecl] = []
  while self.take(Hash) {
    let runtime = self.take(Bang)
    let owner = self.consume(Identifier, "expected attribute name")
    if self.take(LeftParen) {
      if self.check(RightParen) {
        self.report(
          ExpectedExpression,
          "attribute group cannot be empty",
          self.current_token().span,
        )
      }
      while !self.check(RightParen) && !self.check(Eof) {
        let key = self.consume(Identifier, "expected attribute key")
        let value = if self.take(Equal) {
          self.attribute_value()
        } else {
          Value::null()
        }
        if runtime {
          attributes.push({ group: Some(owner.lexeme), key: key.lexeme, value, })
        }
        if !self.take(Comma) {
          break
        }
      }
      ignore(self.consume(RightParen, "expected ')' after attribute group"))
    } else {
      let value = if self.take(Equal) {
        self.attribute_value()
      } else {
        Value::null()
      }
      if runtime {
        attributes.push({ group: None, key: owner.lexeme, value, })
      }
    }
    self.finish_statement()
    self.skip_newlines()
  }
  attributes
}

///|
fn Parser::method_declaration(
  self : Parser,
  attributes : Array[AttributeDecl],
) -> MethodDecl {
  let start = self.current_token()
  let is_foreign = self.take(ForeignKeyword)
  let is_static = self.take(StaticKeyword)
  let is_constructor = self.take(ConstructKeyword)
  if is_static && is_constructor {
    self.report(UnexpectedToken, "constructors cannot be static", start.span)
  }
  let name_start = self.current_token()
  let mut method_name = ""
  let parameters : Array[String] = []
  let mut has_parameters = false
  let mut is_operator = false
  if self.take(LeftBracket) {
    is_operator = true
    has_parameters = true
    self.skip_newlines()
    parameters.push(
      self.consume(Identifier, "expected subscript parameter name").lexeme,
    )
    self.skip_newlines()
    while self.take(Comma) {
      self.skip_newlines()
      parameters.push(
        self.consume(Identifier, "expected subscript parameter name").lexeme,
      )
      self.skip_newlines()
    }
    ignore(self.consume(RightBracket, "expected ']' after subscript parameter"))
    if self.take(Equal) {
      method_name = "[]="
      ignore(self.consume(LeftParen, "expected '(' after subscript setter"))
      parameters.push(
        self.consume(Identifier, "expected subscript setter value parameter").lexeme,
      )
      ignore(
        self.consume(RightParen, "expected ')' after subscript setter value"),
      )
    } else {
      method_name = "[]"
    }
  } else if self.check(Bang) ||
    self.check(Tilde) ||
    self.check(Minus) ||
    self.check(Plus) ||
    self.check(Slash) ||
    self.check(Star) ||
    self.check(Percent) ||
    self.check(Less) ||
    self.check(LessEqual) ||
    self.check(Greater) ||
    self.check(GreaterEqual) ||
    self.check(EqualEqual) ||
    self.check(BangEqual) ||
    self.check(Ampersand) ||
    self.check(Pipe) ||
    self.check(Caret) ||
    self.check(LessLess) ||
    self.check(GreaterGreater) ||
    self.check(DotDot) ||
    self.check(DotDotDot) ||
    self.check(IsKeyword) {
    is_operator = true
    let operator = self.advance()
    method_name = operator.lexeme
    if self.take(LeftParen) {
      has_parameters = true
      let parsed = self.parameter_list()
      for parameter in parsed {
        parameters.push(parameter)
      }
    } else if operator.kind != Bang &&
      operator.kind != Tilde &&
      operator.kind != Minus {
      self.report(
        ExpectedToken,
        "expected '(' after binary operator",
        self.current_token().span,
      )
    }
  } else {
    let name = self.consume(Identifier, "expected method name")
    method_name = name.lexeme
    if self.take(Equal) {
      method_name = method_name + "="
      has_parameters = true
      ignore(self.consume(LeftParen, "expected '(' after setter name"))
      let parsed = self.parameter_list()
      for parameter in parsed {
        parameters.push(parameter)
      }
    } else if self.take(LeftParen) {
      has_parameters = true
      let parsed = self.parameter_list()
      for parameter in parsed {
        parameters.push(parameter)
      }
    }
  }
  if is_constructor && !has_parameters {
    self.report(
      ExpectedToken,
      "expected '(' after constructor name",
      self.current_token().span,
    )
  }
  if is_constructor && (is_operator || method_name.has_suffix("=")) {
    self.report(
      UnexpectedToken,
      "a constructor must have a named method signature",
      name_start.span,
    )
  }
  if is_foreign && is_constructor {
    self.report(
      UnexpectedToken,
      "foreign constructors require foreign class support",
      start.span,
    )
  }
  if is_foreign {
    let end_span = if has_parameters {
      self.previous().span
    } else {
      name_start.span
    }
    self.finish_statement()
    return {
      name: method_name,
      parameters,
      body: [],
      is_constructor,
      is_getter: !is_constructor && !has_parameters && !is_operator,
      is_static,
      is_foreign,
      attributes,
      span: SourceSpan::merge(start.span, end_span),
    }
  }
  self.skip_newlines()
  let saved_method_name = self.current_method_name
  let saved_method_is_constructor = self.current_method_is_constructor
  self.current_method_name = method_name
  self.current_method_is_constructor = is_constructor
  let opening = self.consume(LeftBrace, "expected '{' before method body")
  let block = self.block_statement(opening)
  self.current_method_name = saved_method_name
  self.current_method_is_constructor = saved_method_is_constructor
  match block {
    BlockStatement(body, span) =>
      {
        name: method_name,
        parameters,
        body,
        is_constructor,
        is_getter: !is_constructor && !has_parameters && !is_operator,
        is_static,
        is_foreign,
        attributes,
        span: SourceSpan::merge(start.span, span),
      }
    _ => abort("method body must be a block")
  }
}

///|
fn Parser::class_declaration(
  self : Parser,
  start : Token,
  attributes : Array[AttributeDecl],
  is_foreign : Bool,
) -> Stmt {
  let name = self.consume(Identifier, "expected class name")
  self.skip_newlines()
  let superclass = if self.take(IsKeyword) {
    self.skip_newlines()
    Some(self.expression())
  } else {
    None
  }
  self.skip_newlines()
  ignore(self.consume(LeftBrace, "expected '{' after class name"))
  self.skip_newlines()
  let methods : Array[MethodDecl] = []
  while !self.check(RightBrace) && !self.check(Eof) {
    let method_attributes = self.attributes()
    methods.push(self.method_declaration(method_attributes))
    self.skip_newlines()
  }
  let closing = self.consume(RightBrace, "expected '}' after class body")
  ClassStatement(
    name.lexeme,
    superclass,
    methods,
    attributes,
    is_foreign,
    SourceSpan::merge(start.span, closing.span),
  )
}

///|
fn Parser::statement(self : Parser) -> Stmt {
  let start = self.current_token()
  if self.take(LeftBrace) {
    self.block_statement(start)
  } else if self.take(IfKeyword) {
    self.if_statement(start)
  } else if self.take(WhileKeyword) {
    self.while_statement(start)
  } else if self.take(ForKeyword) {
    self.for_statement(start)
  } else if self.take(ReturnKeyword) {
    self.return_statement(start)
  } else if self.take(BreakKeyword) {
    self.finish_statement()
    BreakStatement(start.span)
  } else if self.take(ContinueKeyword) {
    self.finish_statement()
    ContinueStatement(start.span)
  } else {
    let expression = self.expression()
    let span = expression.span()
    self.finish_statement()
    ExpressionStatement(expression, span)
  }
}

///|
fn Parser::declaration(self : Parser) -> Stmt {
  let start = self.current_token()
  if self.check(Hash) {
    let attributes = self.attributes()
    let declaration_start = self.current_token()
    if self.take(ClassKeyword) {
      self.class_declaration(declaration_start, attributes, false)
    } else if self.take(ForeignKeyword) {
      ignore(self.consume(ClassKeyword, "expected 'class' after 'foreign'"))
      self.class_declaration(declaration_start, attributes, true)
    } else {
      self.report(
        UnexpectedToken,
        "attributes can only be applied to a class or method",
        start.span,
      )
      self.declaration()
    }
  } else if self.take(ImportKeyword) {
    self.import_declaration(start)
  } else if self.take(ClassKeyword) {
    self.class_declaration(start, [], false)
  } else if self.take(ForeignKeyword) {
    ignore(self.consume(ClassKeyword, "expected 'class' after 'foreign'"))
    self.class_declaration(start, [], true)
  } else if self.take(VarKeyword) {
    self.variable_declaration(start)
  } else {
    self.statement()
  }
}

///|
fn Parser::parse_program(self : Parser) -> ProgramParseResult {
  let statements : Array[Stmt] = []
  self.skip_newlines()
  while !self.check(Eof) {
    statements.push(self.declaration())
    self.skip_newlines()
  }
  if self.diagnostics.is_empty() {
    ProgramParsed(statements)
  } else {
    ProgramParseFailed(self.diagnostics)
  }
}

///|
fn Parser::parse(self : Parser) -> ExpressionParseResult {
  self.skip_newlines()
  let expression = self.expression()
  self.skip_newlines()
  if !self.check(Eof) {
    self.report(
      UnexpectedToken,
      "unexpected token after expression",
      self.current_token().span,
    )
  }
  if self.diagnostics.is_empty() {
    ExpressionParsed(expression)
  } else {
    ExpressionParseFailed(self.diagnostics)
  }
}

///|
/// Parse one complete expression, including its lexical analysis phase.
pub fn parse_expression(source : String) -> ExpressionParseResult {
  let scanned = scan(source)
  if !scanned.diagnostics.is_empty() {
    ExpressionParseFailed(scanned.diagnostics)
  } else {
    Parser::new(scanned.tokens).parse()
  }
}

///|
/// Parse a complete source file containing declarations and statements.
pub fn parse_program(source : String) -> ProgramParseResult {
  let scanned = scan(source)
  if !scanned.diagnostics.is_empty() {
    ProgramParseFailed(scanned.diagnostics)
  } else {
    Parser::new(scanned.tokens).parse_program()
  }
}
