///|
pub(all) enum UnaryOperator {
  Negate
  LogicalNot
  BitwiseNot
} derive(Eq, Debug)

///|
pub extend UnaryOperator with Eq::{equal, not_equal}

///|
pub extend UnaryOperator with Debug::{to_repr}

///|
pub(all) enum BinaryOperator {
  Add
  Subtract
  Multiply
  Divide
  Remainder
  EqualTo
  NotEqualTo
  LessThan
  LessThanOrEqual
  GreaterThan
  GreaterThanOrEqual
  LogicalAnd
  LogicalOr
  BitwiseAnd
  BitwiseOr
  BitwiseXor
  ShiftLeft
  ShiftRight
  InclusiveRange
  ExclusiveRange
  IsType
} derive(Eq, Debug)

///|
pub extend BinaryOperator with Eq::{equal, not_equal}

///|
pub extend BinaryOperator with Debug::{to_repr}

///|
/// Expression tree retained independently from the parser and evaluator.
pub(all) enum Expr {
  Literal(Value, SourceSpan)
  Variable(String, SourceSpan)
  Unary(UnaryOperator, Expr, SourceSpan)
  Binary(Expr, BinaryOperator, Expr, SourceSpan)
  Conditional(Expr, Expr, Expr, SourceSpan)
  Grouping(Expr, SourceSpan)
} derive(Eq, Debug)

///|
pub extend Expr with Eq::{equal, not_equal}

///|
pub extend Expr with Debug::{to_repr}

///|
pub fn Expr::span(self : Expr) -> SourceSpan {
  match self {
    Literal(_, span)
    | Variable(_, span)
    | Unary(_, _, span)
    | Binary(_, _, _, span)
    | Conditional(_, _, _, span)
    | Grouping(_, span) => span
  }
}
