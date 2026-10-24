///|
/// All punctuation, operators, literals, and reserved words recognized by Wren.
pub(all) enum TokenKind {
  LeftParen
  RightParen
  LeftBrace
  RightBrace
  LeftBracket
  RightBracket
  Colon
  Comma
  Dot
  DotDot
  DotDotDot
  Minus
  Plus
  Slash
  Star
  Percent
  Pipe
  PipePipe
  Ampersand
  AmpersandAmpersand
  Caret
  Tilde
  Question
  Hash
  Bang
  BangEqual
  Equal
  EqualEqual
  Less
  LessEqual
  LessLess
  Greater
  GreaterEqual
  GreaterGreater
  Newline
  Identifier
  Field
  StaticField
  Number
  StringLiteral
  BreakKeyword
  ClassKeyword
  ConstructKeyword
  ContinueKeyword
  ElseKeyword
  FalseKeyword
  ForKeyword
  ForeignKeyword
  IfKeyword
  ImportKeyword
  AsKeyword
  InKeyword
  IsKeyword
  NullKeyword
  ReturnKeyword
  StaticKeyword
  SuperKeyword
  ThisKeyword
  TrueKeyword
  VarKeyword
  WhileKeyword
  Eof
} derive(Eq, Debug)

///|
pub extend TokenKind with Eq::{equal, not_equal}

///|
pub extend TokenKind with Debug::{to_repr}

///|
/// A token retains its original source spelling for diagnostics and parsing.
pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : SourceSpan
}

///|
pub fn Token::new(
  kind : TokenKind,
  lexeme : String,
  span : SourceSpan,
) -> Token {
  { kind, lexeme, span, }
}

///|
pub fn Token::is_keyword(self : Token) -> Bool {
  match self.kind {
    BreakKeyword
    | ClassKeyword
    | ConstructKeyword
    | ContinueKeyword
    | ElseKeyword
    | FalseKeyword
    | ForKeyword
    | ForeignKeyword
    | IfKeyword
    | ImportKeyword
    | AsKeyword
    | InKeyword
    | IsKeyword
    | NullKeyword
    | ReturnKeyword
    | StaticKeyword
    | SuperKeyword
    | ThisKeyword
    | TrueKeyword
    | VarKeyword
    | WhileKeyword => true
    _ => false
  }
}

///|
fn keyword_kind(text : String) -> TokenKind {
  match text {
    "break" => BreakKeyword
    "class" => ClassKeyword
    "construct" => ConstructKeyword
    "continue" => ContinueKeyword
    "else" => ElseKeyword
    "false" => FalseKeyword
    "for" => ForKeyword
    "foreign" => ForeignKeyword
    "if" => IfKeyword
    "import" => ImportKeyword
    "as" => AsKeyword
    "in" => InKeyword
    "is" => IsKeyword
    "null" => NullKeyword
    "return" => ReturnKeyword
    "static" => StaticKeyword
    "super" => SuperKeyword
    "this" => ThisKeyword
    "true" => TrueKeyword
    "var" => VarKeyword
    "while" => WhileKeyword
    _ => Identifier
  }
}
