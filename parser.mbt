///|
pub(all) enum ExpressionParseResult {
  ExpressionParsed(Expr)
  ExpressionParseFailed(Array[Diagnostic])
}

///|
priv struct Parser {
  tokens : Array[Token]
  diagnostics : Array[Diagnostic]
  mut current : Int
}

///|
fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, diagnostics: [], current: 0, }
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
    let mut value = 0
    for index = 2; index < normalized.length(); index = index + 1 {
      value = value * 16 + hex_value(normalized.unsafe_get(index).to_int())
    }
    return Double::from_int(value)
  }
  let mut index = 0
  let mut value = 0.0
  while index < normalized.length() &&
        is_digit(normalized.unsafe_get(index).to_int()) {
    value = value * 10.0 +
      Double::from_int(normalized.unsafe_get(index).to_int() - 48)
    index = index + 1
  }
  if index < normalized.length() && normalized.unsafe_get(index).to_int() == 46 {
    index = index + 1
    let mut place = 0.1
    while index < normalized.length() &&
          is_digit(normalized.unsafe_get(index).to_int()) {
      value = value +
        Double::from_int(normalized.unsafe_get(index).to_int() - 48) * place
      place = place * 0.1
      index = index + 1
    }
  }
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
    let mut exponent = 0
    while index < normalized.length() {
      exponent = exponent * 10 + normalized.unsafe_get(index).to_int() - 48
      index = index + 1
    }
    let mut scale = 1.0
    let mut power = 0
    while power < exponent {
      scale = scale * 10.0
      power = power + 1
    }
    if sign < 0 {
      value = value / scale
    } else {
      value = value * scale
    }
  }
  value
}

///|
fn decode_string(text : String) -> String {
  text[1:text.length() - 1]
  .to_owned()
  .replace_all(old="\\n", new="\n")
  .replace_all(old="\\r", new="\r")
  .replace_all(old="\\t", new="\t")
  .replace_all(old="\\\"", new="\"")
  .replace_all(old="\\\\", new="\\")
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
    Literal(Value::string(decode_string(token.lexeme)), token.span)
  } else if self.take(Identifier) || self.take(Field) || self.take(StaticField) {
    Variable(token.lexeme, token.span)
  } else if self.take(ThisKeyword) {
    Variable("this", token.span)
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
      let right = self.unary()
      Unary(operator, right, SourceSpan::merge(token.span, right.span()))
    }
    None => self.primary()
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
    let right = self.shift()
    let span = SourceSpan::merge(expression.span(), right.span())
    expression = Binary(expression, InclusiveRange, right, span)
  } else if self.take(DotDotDot) {
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
    let then_branch = self.expression()
    ignore(self.consume(Colon, "expected ':' in conditional expression"))
    let else_branch = self.conditional()
    let span = SourceSpan::merge(condition.span(), else_branch.span())
    Conditional(condition, then_branch, else_branch, span)
  } else {
    condition
  }
}

///|
fn Parser::expression(self : Parser) -> Expr {
  self.conditional()
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
