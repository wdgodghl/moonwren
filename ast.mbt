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
  Assign(String, Expr, SourceSpan)
  FieldGet(String, SourceSpan)
  FieldAssign(String, Expr, SourceSpan)
  PropertyGet(Expr, String, SourceSpan)
  MethodCall(Expr, String, Array[Expr], SourceSpan)
  FunctionLiteral(Array[String], Array[Stmt], SourceSpan)
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
    | Assign(_, _, span)
    | FieldGet(_, span)
    | FieldAssign(_, _, span)
    | PropertyGet(_, _, span)
    | MethodCall(_, _, _, span)
    | FunctionLiteral(_, _, span)
    | Unary(_, _, span)
    | Binary(_, _, _, span)
    | Conditional(_, _, _, span)
    | Grouping(_, span) => span
  }
}

///|
/// Statements for the first executable subset of the language.
pub(all) enum Stmt {
  ExpressionStatement(Expr, SourceSpan)
  VariableStatement(String, Expr?, SourceSpan)
  BlockStatement(Array[Stmt], SourceSpan)
  IfStatement(Expr, Stmt, Stmt?, SourceSpan)
  WhileStatement(Expr, Stmt, SourceSpan)
  ForStatement(String, Expr, Stmt, SourceSpan)
  ReturnStatement(Expr?, SourceSpan)
  ClassStatement(String, Array[MethodDecl], SourceSpan)
} derive(Eq, Debug)

///|
pub extend Stmt with Eq::{equal, not_equal}

///|
pub extend Stmt with Debug::{to_repr}

///|
pub fn Stmt::span(self : Stmt) -> SourceSpan {
  match self {
    ExpressionStatement(_, span)
    | VariableStatement(_, _, span)
    | BlockStatement(_, span)
    | IfStatement(_, _, _, span)
    | WhileStatement(_, _, span)
    | ForStatement(_, _, _, span)
    | ReturnStatement(_, span)
    | ClassStatement(_, _, span) => span
  }
}

///|
/// One instance method, getter, or constructor declared in a class body.
pub(all) struct MethodDecl {
  name : String
  parameters : Array[String]
  body : Array[Stmt]
  is_constructor : Bool
  is_getter : Bool
  span : SourceSpan
} derive(Eq, Debug)

///|
pub extend MethodDecl with Eq::{equal, not_equal}

///|
pub extend MethodDecl with Debug::{to_repr}
