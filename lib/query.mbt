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
/// Not yet: `def`, `test` (regex),
/// `..` (recursive descent),
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
/// The key is a filter, not a plain string: usually a
/// `Literal(Str)` for a static key, or an `Interp` when the
/// key itself is interpolated, e.g. `{"\(.k)": v}`.
pub(all) struct ObjectField {
  key : Filter
  value : Filter
}

///|
pub fn ObjectField::new(key : Filter, value : Filter) -> ObjectField {
  { key, value, }
}

///|
/// One piece of an interpolated string `"…\(expr)…"`.
pub(all) enum InterpPart {
  /// Literal text (escapes already decoded).
  Text(String)
  /// An embedded filter, evaluated and stringified.
  Expr(Filter)
}

///|
/// One step of an update-assignment path (`.a.b[0][]`, …).
/// A path is a list of these steps; `[]` is the whole input
/// (`.` itself, as in `. |= f`).
pub(all) enum PathStep {
  /// `.name` / `.["name"]` — object field.
  Field(String)
  /// `.[0]` / `.[-1]` — array index.
  Index(Int32)
  /// `.[expr]` — index/key computed by a filter, evaluated
  /// against the value at that step (like a normal pipe step).
  IndexExpr(Filter)
  /// `.[]` — every element / value.
  Iterate
  /// `.[a:b]` — slice; bounds are `None` when omitted.
  Slice(Filter?, Filter?)
}

///|
/// Which update-assignment operator was written.
pub(all) enum UpdateOp {
  /// `|=` — RHS runs on the old path value.
  UpdPipe
  /// `=` — RHS runs on the original input.
  UpdSet
  /// `+=`, `-=`, `*=`, `/=`, `%=` — RHS runs on the
  /// original input, then is combined with the old value.
  UpdAdd
  UpdSub
  UpdMul
  UpdDiv
  UpdMod
  /// `//=` — RHS runs on the original input; it replaces
  /// the old value only when that value is false/null.
  UpdAlt
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
  /// `split(sep)` — split a string into an array of strings.
  Split(Filter)
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
  /// `"…\(expr)…"` — string interpolation; one output per
  /// output of the embedded filters (like jq).
  Interp(Array[InterpPart])
  /// `$x` — read a bound variable.
  Var(String)
  /// `exp as $x | body` — run `body` once per output of
  /// `exp`, with `$x` bound to that output (input unchanged).
  Bind(Filter, String, Filter)
  /// `reduce exp as $x (init; update)` — fold `exp`'s
  /// outputs into one value, starting from `init`.
  Reduce(Filter, String, Filter, Filter)
  /// `group_by(f)` — sort an array by `f`, then group
  /// consecutive elements with equal `f` values.
  GroupBy(Filter)
  /// `to_entries` — an object becomes
  /// `[{"key": k, "value": v}, …]` (insertion order); an
  /// array becomes `[{"key": 0, "value": v0}, …]`.
  ToEntries
  /// `from_entries` — the inverse of `to_entries`; accepts
  /// `"key"` or `"name"`, missing `"value"` means null,
  /// later duplicates win.
  FromEntries
  /// `with_entries(f)` — `to_entries | map(f) | from_entries`.
  WithEntries(Filter)
  /// `path |= f` / `path = f` / `path += f` / … — update
  /// assignment (see `PathStep` / `UpdateOp`). `paths` holds
  /// one path for `.a.b`, several for `(.a, .b)`, and a
  /// single empty path for `. |= f`.
  Update(Array[Array[PathStep]], UpdateOp, Filter)
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
