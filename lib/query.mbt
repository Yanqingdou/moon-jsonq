/// moon-jsonq: jq filter AST.
///
/// A filter takes one JSON value in and produces zero, one or
/// many JSON values out. That is why `eval` returns
/// `Array[JVal]`, not a single `JVal`:
/// - `.name` produces 1 value
/// - `.[]` on `[1, 2, 3]` produces 3 values
/// - `select(.score >= 90)` produces 0 or 1 values
///
/// This matches jq semantics and makes `|`, `,`, `map` and
/// `select` fall out naturally as list operations.
///
/// Scope for the November monthly review (see docs/PLAN.md):
///   `.`  `.name`  `.a.b`  `.[0]`  `.["k"]`  `.[]`  `|`  `,`  `//`
///   `map(f)`  `select(f)`  `length`  `keys`  `sort`  `sort_by(f)`
///   `unique`  `min`  `max`  `add`  `type`  `tostring`  `tonumber`
///   `not`  `empty`  `if-then-else-end`  `[f]`  `{k: f, …}`
///   arithmetic `+ - * / %`, comparisons `== != < <= > >=`,
///   literals, string literals, `and` / `or`
///
/// Not yet: `def`, `reduce`, `group_by`, `test` (regex),
/// `..` (recursive descent), `$variables`, string interpolation,
/// `getpath` / `paths`, module import. Those are listed in
/// docs/PLAN.md as P2, with the reason for each deferral.

///|
/// A binary operator, for arithmetic and comparison.
pub(all) enum Op {
  Add
  Sub
  Mul
  Div
  Mod
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  And
  Or
}

///|
/// One field of an object-construction filter `{k: f, …}`.
pub(all) struct ObjectField {
  key : String
  value : Filter
}

///|
pub fn ObjectField::new(key : String, value : Filter) -> ObjectField {
  { key, value, }
}

///|
/// A jq filter, as a tree.
pub(all) enum Filter {
  /// `.` — identity, returns the input unchanged.
  Identity
  /// `.name` — field access.
  Field(String)
  /// `.[0]` / `.[-1]` — array index.
  Index(Int32)
  /// `.[a:b]` — slice; each bound is `None` when omitted,
  /// or `Some(filter)` evaluated against the input.
  Slice(Filter?, Filter?)
  /// `.["key"]` — field access by a string literal.
  IndexStr(String)
  /// `.[expr]` — index/key computed by a filter.
  IndexExpr(Filter)
  /// `.[]` — iterate array elements / object values.
  Iterate
  /// `a | b` — run `a`, then run `b` on each of its outputs.
  /// Stored as a list so `a | b | c` is one node, not nested
  /// binary trees.
  Pipe(Array[Filter])
  /// `a, b` — run both, concatenate outputs.
  Comma(Array[Filter])
  /// `a // b` — if `a` is false/null, use `b` instead.
  Alt(Filter, Filter)
  /// `a op b` — arithmetic / comparison / `and` / `or`.
  BinOp(Op, Filter, Filter)
  /// `-f` — numeric negation.
  Neg(Filter)
  /// `if cond then a else b end`.
  If(Filter, Filter, Filter)
  /// `[f]` — collect all outputs of `f` into one array.
  ArrayCons(Array[Filter])
  /// `{k: f, …}` — build an object from filters.
  ObjectCons(Array[ObjectField])
  /// `map(f)` — apply `f` to every array element, collect results.
  Map(Filter)
  /// `select(f)` — keep input iff `f` is truthy on it.
  Select(Filter)
  /// `length` — see `JVal::length` in json.mbt.
  Length
  /// `keys` — see `JVal::keys` in json.mbt.
  Keys
  /// `sort` — sort an array by jq order.
  Sort
  /// `sort_by(f)` — sort an array by `f` of each element.
  SortBy(Filter)
  /// `unique` — sort and de-duplicate an array.
  Unique
  /// `min` / `max` — smallest / largest element of an array.
  Min
  Max
  /// `add` — sum / concatenate the elements of an array.
  Add
  /// `type` — "null" | "boolean" | "number" | "string" | "array" | "object".
  Type
  /// `tostring` — JSON text of the value, as a string.
  ToString
  /// `tonumber` — number, or parse a string as a number.
  ToNumber
  /// `not` — logical negation of truthiness.
  Not
  /// `empty` — produces no output at all.
  Empty
  /// A literal value, e.g. `42`, `"hi"`, `true`, `null`.
  Literal(JVal)
}

///|
/// Convenience: `.name` without writing `Field("name")` by hand.
pub fn field(name : String) -> Filter {
  Field(name)
}

///|
/// Convenience: `a | b`.
pub fn pipe(a : Filter, b : Filter) -> Filter {
  Pipe([a, b])
}

///|
/// Convenience: `a, b`.
pub fn comma(a : Filter, b : Filter) -> Filter {
  Comma([a, b])
}
