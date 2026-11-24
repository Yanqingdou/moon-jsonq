/// moon-jsonq: filter evaluator.
///
/// `eval_env(filter, input, env)` is the heart of the project. Everything
/// else — the parser in `parser.mbt`, the CLI in `main/main.mbt`,
/// the Wasm demo in P2 — is a thin wrapper around this function.
///
/// Design notes for reviewers (and for the hackathon judges):
/// 1. Filters are pure: no I/O, no global state, no mutation of
///    the input. That makes them trivial to test and to run in
///    Wasm.
/// 2. Errors never crash the evaluator. A type mistake
///    (e.g. `.name` on a number, `.[0]` on a string, `1 + "a"`)
///    returns `Null` or `[]`, like jq's lenient behaviour for
///    missing fields. Strict error reporting
///    (`Result[JVal, String]`) is a P2 item, listed in docs/PLAN.md.
/// 3. `eval_one` is the helper for `map` / `select` / `sort_by`,
///    where jq expects exactly one output per element in this
///    subset. If a filter produces 0 outputs there, we treat it
///    as `Null`; if it produces 2+, we take the first.

///|
/// One variable binding in the evaluator environment.
/// The environment is a list, newest binding first, so a
/// lookup finds the innermost binding (shadowing works).
/// `--arg` variables start in the list; `as` prepends.
pub(all) struct EnvEntry {
  name : String
  value : JVal
}

///|
pub fn EnvEntry::new(name : String, value : JVal) -> EnvEntry {
  { name, value, }
}

///|
/// Look a variable up in the environment, innermost first.
/// Returns `None` when the variable is not bound; the
/// evaluator treats that as `Null` (jq rejects it at
/// compile time, we stay lenient at run time).
pub fn env_lookup(env : Array[EnvEntry], name : String) -> JVal? {
  for entry in env {
    if entry.name == name {
      return Some(entry.value)
    }
  }
  None
}

///|
/// Evaluate a filter on one input value, return all outputs.
/// Thin wrapper with an empty environment; `--arg` variables
/// and `as` bindings go through `eval_env`.
pub fn eval(filter : Filter, input : JVal) -> Array[JVal] {
  eval_env(filter, input, [])
}

///|
/// Evaluate a filter with a variable environment.
pub fn eval_env(
  filter : Filter,
  input : JVal,
  env : Array[EnvEntry],
) -> Array[JVal] {
  match filter {
    Identity => [input]
    Field(name) => [input.field(name)]
    Index(i) => [input.index(i)]
    IndexStr(key) => [input.field(key)]
    IndexExpr(f) => {
      let key = eval_one_env(f, input, env)
      match key {
        Num(n) => [input.index(n.to_int())]
        Str(s) => [input.field(s)]
        _ => [Null]
      }
    }
    Slice(lo, hi) => {
      let lov = match lo {
        None => Null
        Some(f) => eval_one_env(f, input, env)
      }
      let hiv = match hi {
        None => Null
        Some(f) => eval_one_env(f, input, env)
      }
      [input.slice(lov, hiv)]
    }
    Split(f) =>
      match (input, eval_one_env(f, input, env)) {
        (Str(s), Str(sep)) =>
          // MoonBit's split already matches jq here:
          // empty separator splits into characters, a
          // trailing separator keeps a final empty string.
          // One difference: "".split("") is [""] in MoonBit
          // but [] in jq, so an empty input is always [].
          if s == "" {
            [Arr([])]
          } else {
            let parts : Array[JVal] = []
            for part in s.split(sep) {
              parts.push(Str(part.to_owned()))
            }
            [Arr(parts)]
          }
        _ => [Null]
      }
    Iterate => input.iterate()
    Pipe(steps) => {
      let mut cur : Array[JVal] = [input]
      for step in steps {
        let next : Array[JVal] = []
        for value in cur {
          for out in eval_env(step, value, env) {
            next.push(out)
          }
        }
        cur = next
      }
      cur
    }
    Comma(parts) => {
      let out : Array[JVal] = []
      for part in parts {
        for value in eval_env(part, input, env) {
          out.push(value)
        }
      }
      out
    }
    Alt(a, b) => {
      let outs = eval_env(a, input, env)
      let mut use_b = true
      for out in outs {
        if out.is_truthy() {
          use_b = false
        }
      }
      if use_b || outs.length() == 0 {
        eval_env(b, input, env)
      } else {
        outs
      }
    }
    BinOp(op, a, b) => {
      // jq: if either side produces several values, every
      // combination is produced (e.g. `.[] + 10` on [1,2]).
      let outs : Array[JVal] = []
      for av in eval_env(a, input, env) {
        for bv in eval_env(b, input, env) {
          outs.push(eval_binop(op, av, bv))
        }
      }
      outs
    }
    Neg(f) =>
      match eval_one_env(f, input, env) {
        Num(n) => [Num(0.0 - n)]
        _ => [Null]
      }
    If(cond, then_f, else_f) =>
      if eval_one_env(cond, input, env).is_truthy() {
        eval_env(then_f, input, env)
      } else {
        eval_env(else_f, input, env)
      }
    ArrayCons(parts) => {
      let out : Array[JVal] = []
      for part in parts {
        for value in eval_env(part, input, env) {
          out.push(value)
        }
      }
      [Arr(out)]
    }
    ObjectCons(fields) => {
      let entries : Array[ObjEntry] = []
      for field in fields {
        // The key is a filter: usually a literal string, or
        // an interpolation for `{"\(.k)": v}`.
        match eval_one_env(field.key, input, env) {
          Str(k) =>
            entries.push(
              ObjEntry::new(k, eval_one_env(field.value, input, env)),
            )
          // A non-string key is an error in jq; here the
          // entry is skipped, like the evaluator's other
          // lenient type mistakes.
          _ => ()
        }
      }
      [Obj(entries)]
    }
    Map(f) =>
      match input {
        Arr(items) => {
          // Collect *all* outputs of f per element; an element
          // whose f produces no output contributes nothing
          // (e.g. map(select(. > 2)) drops the small ones).
          let out : Array[JVal] = []
          for item in items {
            for value in eval_env(f, item, env) {
              out.push(value)
            }
          }
          [Arr(out)]
        }
        _ => [Null]
      }
    Select(f) => {
      let cond = eval_one_env(f, input, env)
      if cond.is_truthy() {
        [input]
      } else {
        []
      }
    }
    Length => [input.length()]
    Keys => [input.keys()]
    Sort =>
      match input {
        Arr(items) => {
          let sorted = items.copy()
          sorted.sort_by(fn(a, b) { a.compare(b) })
          [Arr(sorted)]
        }
        _ => [Null]
      }
    SortBy(f) =>
      match input {
        Arr(items) => {
          let sorted = items.copy()
          sorted.sort_by(fn(a, b) {
            eval_one_env(f, a, env).compare(eval_one_env(f, b, env))
          })
          [Arr(sorted)]
        }
        _ => [Null]
      }
    Unique =>
      match input {
        Arr(items) => {
          let sorted = items.copy()
          sorted.sort_by(fn(a, b) { a.compare(b) })
          let out : Array[JVal] = []
          for item in sorted {
            match out {
              [] => out.push(item)
              [.., last] => if last.compare(item) != 0 { out.push(item) }
            }
          }
          [Arr(out)]
        }
        _ => [Null]
      }
    Min =>
      match input {
        Arr([]) => [Null]
        Arr(items) => {
          let mut best = items[0]
          for item in items {
            if item.compare(best) < 0 {
              best = item
            }
          }
          [best]
        }
        _ => [Null]
      }
    Max =>
      match input {
        Arr([]) => [Null]
        Arr(items) => {
          let mut best = items[0]
          for item in items {
            if item.compare(best) > 0 {
              best = item
            }
          }
          [best]
        }
        _ => [Null]
      }
    Add =>
      match input {
        Arr([]) => [Null]
        Arr(items) => {
          let mut acc = items[0]
          let mut i = 1
          while i < items.length() {
            acc = add_values(acc, items[i])
            i = i + 1
          }
          [acc]
        }
        _ => [Null]
      }
    Type => [Str(input.type_name())]
    ToString => [Str(input.to_string())]
    ToNumber =>
      match input {
        Num(_) => [input]
        Str(s) => {
          let n = @string.parse_double(s) catch { _ => 0.0 }
          // parse_double returns 0.0 on the catch path too, so
          // re-check with a round-trip: only accept if the
          // string really parses. A failed parse is Null in jq.
          let ok = try {
            let _ = @string.parse_double(s)
            true
          } catch {
            _ => false
          }
          if ok {
            [Num(n)]
          } else {
            [Null]
          }
        }
        _ => [Null]
      }
    Not => [Bool(!input.is_truthy())]
    Empty => []
    Var(name) =>
      match env_lookup(env, name) {
        Some(v) => [v]
        None => [Null]
      }
    Bind(exp, name, body) => {
      // Run `body` once per output of `exp`, with `$name`
      // bound to that output; the input is unchanged.
      let outs : Array[JVal] = []
      for v in eval_env(exp, input, env) {
        let inner : Array[EnvEntry] = [EnvEntry::new(name, v)]
        for e in env {
          inner.push(e)
        }
        for out in eval_env(body, input, inner) {
          outs.push(out)
        }
      }
      outs
    }
    Interp(parts) => {
      // Cross-product of the parts: literal text appends
      // itself, an embedded filter appends one string per
      // output it produces (like jq: `"\(.a, .b)"` gives
      // two outputs). Values are stringified like jq's
      // `tostring`, except strings stay unquoted.
      let mut acc : Array[String] = [""]
      for part in parts {
        match part {
          Text(t) => {
            let next : Array[String] = []
            for s in acc {
              next.push(s + t)
            }
            acc = next
          }
          Expr(f) => {
            let next : Array[String] = []
            for s in acc {
              for v in eval_env(f, input, env) {
                let piece = match v {
                  Str(x) => x
                  _ => v.to_string()
                }
                next.push(s + piece)
              }
            }
            acc = next
          }
        }
      }
      let out : Array[JVal] = []
      for s in acc {
        out.push(Str(s))
      }
      out
    }
    Literal(value) => [value]
  }
}

///|
/// One binary operation on two already-evaluated values.
/// Arithmetic follows jq: `+` adds numbers, concatenates
/// strings and arrays, and merges objects (right wins);
/// `-` subtracts numbers and removes array elements;
/// `*` multiplies numbers and deep-merges objects (here:
/// shallow merge, same as `+` for objects);
/// `/` and `%` are numeric only.
/// Comparison uses jq total order (`JVal::compare`).
/// `and` / `or` use jq truthiness.
fn eval_binop(op : Op, a : JVal, b : JVal) -> JVal {
  match op {
    Add => add_values(a, b)
    Sub =>
      match (a, b) {
        (Num(x), Num(y)) => Num(x - y)
        (Arr(xs), Arr(ys)) => {
          let out : Array[JVal] = []
          for x in xs {
            let mut found = false
            for y in ys {
              if x.compare(y) == 0 {
                found = true
              }
            }
            if !found {
              out.push(x)
            }
          }
          Arr(out)
        }
        _ => Null
      }
    Mul =>
      match (a, b) {
        (Num(x), Num(y)) => Num(x * y)
        (Obj(xs), Obj(ys)) => merge_objects(xs, ys)
        _ => Null
      }
    Div =>
      match (a, b) {
        (Num(x), Num(y)) => if y == 0.0 { Null } else { Num(x / y) }
        (Str(s), Str(sep)) => {
          // "a,b" / "," -> ["a", "b"], like jq.
          let parts : Array[JVal] = []
          if sep == "" {
            for c in s.to_array() {
              parts.push(Str(c.to_string()))
            }
          } else {
            for part in s.split(sep) {
              parts.push(Str(part.to_owned()))
            }
          }
          Arr(parts)
        }
        _ => Null
      }
    Mod =>
      match (a, b) {
        (Num(x), Num(y)) => if y == 0.0 { Null } else { Num(x % y) }
        _ => Null
      }
    Eq => Bool(a.compare(b) == 0)
    Ne => Bool(a.compare(b) != 0)
    Lt => Bool(a.compare(b) < 0)
    Le => Bool(a.compare(b) <= 0)
    Gt => Bool(a.compare(b) > 0)
    Ge => Bool(a.compare(b) >= 0)
    And => Bool(a.is_truthy() && b.is_truthy())
    Or => Bool(a.is_truthy() || b.is_truthy())
  }
}

///|
/// `+` in jq, shared by `BinOp(Add)` and `add`.
fn add_values(a : JVal, b : JVal) -> JVal {
  match (a, b) {
    (Null, x) => x
    (x, Null) => x
    (Num(x), Num(y)) => Num(x + y)
    (Str(x), Str(y)) => Str(x + y)
    (Arr(xs), Arr(ys)) => {
      let out : Array[JVal] = []
      for x in xs {
        out.push(x)
      }
      for y in ys {
        out.push(y)
      }
      Arr(out)
    }
    (Obj(xs), Obj(ys)) => merge_objects(xs, ys)
    _ => Null
  }
}

///|
/// Merge two objects, right wins on duplicate keys.
/// Rebuilds the entry list instead of mutating entries in
/// place, so the result does not depend on struct-copy
/// semantics of `for` loops.
fn merge_objects(xs : Array[ObjEntry], ys : Array[ObjEntry]) -> JVal {
  let mut entries : Array[ObjEntry] = []
  for e in xs {
    entries.push(e)
  }
  for e in ys {
    let kept : Array[ObjEntry] = []
    for old in entries {
      if old.key != e.key {
        kept.push(old)
      }
    }
    kept.push(e)
    entries = kept
  }
  Obj(entries)
}

///|
/// Evaluate a filter and take a single output.
/// Thin wrapper with an empty environment; see `eval_one_env`.
pub fn eval_one(filter : Filter, input : JVal) -> JVal {
  eval_one_env(filter, input, [])
}

///|
/// Evaluate a filter and take a single output, with a
/// variable environment. Used by `map`, `select`, `sort_by`,
/// and binary operators. If a filter produces 0 outputs,
/// we treat it as `Null`; if it produces 2+, we take the first.
pub fn eval_one_env(
  filter : Filter,
  input : JVal,
  env : Array[EnvEntry],
) -> JVal {
  let outs = eval_env(filter, input, env)
  if outs.length() == 0 {
    Null
  } else {
    outs[0]
  }
}

///|
/// Run a filter on an input and return every output as a
/// compact JSON string. This is what the CLI uses, and what
/// the tests assert on (via `to_string`, not via stdout).
pub fn eval_to_strings(filter : Filter, input : JVal) -> Array[String] {
  let outs = eval(filter, input)
  let lines : Array[String] = []
  for out in outs {
    lines.push(out.to_string())
  }
  lines
}
