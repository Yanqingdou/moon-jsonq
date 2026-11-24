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
    Reduce(exp, name, init, update) => {
      // Fold `exp`'s outputs into one value: the accumulator
      // starts at `init` (evaluated on the original input),
      // and each output feeds `update` with `.` set to the
      // accumulator and `$name` to that output.
      let mut acc = eval_one_env(init, input, env)
      for v in eval_env(exp, input, env) {
        let inner : Array[EnvEntry] = [EnvEntry::new(name, v)]
        for e in env {
          inner.push(e)
        }
        acc = eval_one_env(update, acc, inner)
      }
      [acc]
    }
    GroupBy(f) =>
      match input {
        Arr(items) => {
          // jq sorts by f first, then groups equal keys.
          let sorted = items.copy()
          sorted.sort_by(fn(a, b) {
            eval_one_env(f, a, env).compare(eval_one_env(f, b, env))
          })
          let groups : Array[JVal] = []
          let mut cur : Array[JVal] = []
          let mut cur_key : JVal = Null
          for item in sorted {
            let k = eval_one_env(f, item, env)
            if cur.length() == 0 {
              cur.push(item)
              cur_key = k
            } else if k.compare(cur_key) == 0 {
              cur.push(item)
            } else {
              groups.push(Arr(cur))
              cur = [item]
              cur_key = k
            }
          }
          if cur.length() > 0 {
            groups.push(Arr(cur))
          }
          [Arr(groups)]
        }
        _ => [Null]
      }
    ToEntries =>
      match input {
        Obj(entries) => {
          // Insertion order is preserved (see lib/json.mbt).
          let out : Array[JVal] = []
          for e in entries {
            out.push(
              Obj([
                ObjEntry::new("key", Str(e.key)),
                ObjEntry::new("value", e.value),
              ]),
            )
          }
          [Arr(out)]
        }
        Arr(items) => {
          let out : Array[JVal] = []
          let mut i = 0
          while i < items.length() {
            out.push(
              Obj([
                ObjEntry::new("key", Num(i.to_double())),
                ObjEntry::new("value", items[i]),
              ]),
            )
            i = i + 1
          }
          [Arr(out)]
        }
        _ => [Null]
      }
    FromEntries =>
      match input {
        Arr(items) => {
          let mut entries : Array[ObjEntry] = []
          for item in items {
            match item {
              Obj(es) => {
                // "key" wins over "name"; a non-string key
                // is skipped; a missing "value" is null.
                let key = match entry_field(es, "key") {
                  Some(Str(k)) => Some(k)
                  _ =>
                    match entry_field(es, "name") {
                      Some(Str(k)) => Some(k)
                      _ => None
                    }
                }
                match key {
                  Some(k) => {
                    let v = match entry_field(es, "value") {
                      Some(v) => v
                      None => Null
                    }
                    entries = put_entry(entries, k, v)
                  }
                  None => ()
                }
              }
              _ => ()
            }
          }
          [Obj(entries)]
        }
        _ => [Null]
      }
    WithEntries(f) =>
      match eval_env(ToEntries, input, env) {
        [Arr(items)] => {
          // to_entries | map(f) | from_entries.
          let out : Array[JVal] = []
          for item in items {
            for v in eval_env(f, item, env) {
              out.push(v)
            }
          }
          eval_env(FromEntries, Arr(out), env)
        }
        _ => [Null]
      }
    Update(paths, op, rhs) => eval_update(paths, op, rhs, input, env)
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
/// What a leaf update does to the value at a path.
priv enum LeafOut {
  Replace(JVal)
  Delete
}

///|
/// What one step of an update does to a value: a new value,
/// a request to delete it from its parent, or a type error
/// (the whole update then yields `Null`, like the
/// evaluator's other lenient type mistakes).
priv enum UpdateResult {
  Updated(JVal)
  Deleted
  Failed
}

///|
/// How a leaf value is computed from its old value.
/// `PipeRhs` is `|=`: the RHS filter runs on the old
/// value. `Combine` is `=` / `+=` / …: the RHS was already
/// evaluated on the original input, and is combined here.
priv enum Updater {
  PipeRhs(Filter)
  Combine(UpdateOp, JVal)
}

///|
/// Evaluate an update assignment. `|=` produces one output
/// (the RHS's first output per leaf; no output deletes the
/// leaf). `=` / `+=` / … produce one output per RHS output,
/// each evaluated on the original input.
fn eval_update(
  paths : Array[Array[PathStep]],
  op : UpdateOp,
  rhs : Filter,
  input : JVal,
  env : Array[EnvEntry],
) -> Array[JVal] {
  match op {
    UpdPipe => {
      let mut cur = input
      for path in paths {
        match apply_update(cur, path, 0, PipeRhs(rhs), env) {
          Updated(v) => cur = v
          Deleted =>
            // The path was missing and the update deleted
            // it: the input is unchanged — except for `.`
            // itself, where deleting the root means no
            // output at all (`. |= empty`).
            if path.length() == 0 {
              return []
            }
          Failed => return [Null]
        }
      }
      [cur]
    }
    _ => {
      let rhs_outs = eval_env(rhs, input, env)
      if rhs_outs.length() == 0 {
        // `.a = empty` and `.a //= empty` produce no
        // output at all, even when the old value is truthy.
        return []
      }
      let outs : Array[JVal] = []
      for rv in rhs_outs {
        let mut cur = input
        let mut failed = false
        let mut i = 0
        while i < paths.length() && !failed {
          match apply_update(cur, paths[i], 0, Combine(op, rv), env) {
            Updated(v) => cur = v
            Deleted => ()
            Failed => failed = true
          }
          i = i + 1
        }
        if failed {
          outs.push(Null)
        } else {
          outs.push(cur)
        }
      }
      outs
    }
  }
}

///|
/// Compute a leaf's new value from its old value.
fn updater_apply(
  updater : Updater,
  old : JVal,
  env : Array[EnvEntry],
) -> LeafOut {
  match updater {
    PipeRhs(rhs) =>
      match eval_env(rhs, old, env) {
        [] => Delete
        [first, ..] => Replace(first)
      }
    Combine(op, rv) => Replace(combine_values(op, old, rv))
  }
}

///|
/// Combine an old path value with an already-evaluated RHS
/// value, for `=` / `+=` / `-=` / `*=` / `/=` / `%=` / `//=`.
fn combine_values(op : UpdateOp, old : JVal, rv : JVal) -> JVal {
  match op {
    UpdPipe => old
    UpdSet => rv
    UpdAdd => add_values(old, rv)
    UpdSub => eval_binop(Sub, old, rv)
    UpdMul => eval_binop(Mul, old, rv)
    UpdDiv => eval_binop(Div, old, rv)
    UpdMod => eval_binop(Mod, old, rv)
    UpdAlt => if old.is_truthy() { old } else { rv }
  }
}

///|
/// Apply an update to the value at `steps[idx..]` inside
/// `node`, returning the updated node, `Deleted` when the
/// node itself should be removed from its parent, or
/// `Failed` on a type error (e.g. indexing a number).
/// Missing intermediate values are created — an object for
/// a field step, an array for an index/slice step — and a
/// creation that is then deleted propagates `Deleted`, so
/// `null | .a[0] |= empty` stays `null` instead of
/// becoming `{"a": null}`.
fn apply_update(
  node : JVal,
  steps : Array[PathStep],
  idx : Int32,
  updater : Updater,
  env : Array[EnvEntry],
) -> UpdateResult {
  if idx >= steps.length() {
    match updater_apply(updater, node, env) {
      Replace(v) => Updated(v)
      Delete => Deleted
    }
  } else {
    match steps[idx] {
      PathStep::Field(key) =>
        match node {
          Obj(entries) =>
            match apply_update(node.field(key), steps, idx + 1, updater, env) {
              Updated(v) => Updated(Obj(set_field(entries, key, v)))
              Deleted => Updated(Obj(remove_field(entries, key)))
              Failed => Failed
            }
          Null =>
            match apply_update(Null, steps, idx + 1, updater, env) {
              Updated(v) => Updated(Obj([ObjEntry::new(key, v)]))
              Deleted => Deleted
              Failed => Failed
            }
          _ => Failed
        }
      PathStep::Index(i) =>
        match node {
          Arr(items) => {
            let len = items.length()
            let resolved = if i < 0 { len + i } else { i }
            if resolved < 0 {
              Failed
            } else if resolved < len {
              match
                apply_update(items[resolved], steps, idx + 1, updater, env) {
                Updated(v) => {
                  let out = items.copy()
                  out[resolved] = v
                  Updated(Arr(out))
                }
                Deleted => {
                  let out : Array[JVal] = []
                  let mut j = 0
                  while j < len {
                    if j != resolved {
                      out.push(items[j])
                    }
                    j = j + 1
                  }
                  Updated(Arr(out))
                }
                Failed => Failed
              }
            } else {
              match apply_update(Null, steps, idx + 1, updater, env) {
                Updated(v) => {
                  let out = items.copy()
                  while out.length() < resolved {
                    out.push(Null)
                  }
                  out.push(v)
                  Updated(Arr(out))
                }
                Deleted => Updated(Arr(items))
                Failed => Failed
              }
            }
          }
          Null =>
            if i < 0 {
              Failed
            } else {
              match apply_update(Null, steps, idx + 1, updater, env) {
                Updated(v) => {
                  let out : Array[JVal] = []
                  while out.length() < i {
                    out.push(Null)
                  }
                  out.push(v)
                  Updated(Arr(out))
                }
                Deleted => Deleted
                Failed => Failed
              }
            }
          _ => Failed
        }
      PathStep::IndexExpr(f) => {
        // The key is computed on the value at this step,
        // like a normal pipe step, then re-dispatched as a
        // field or index step.
        let key = eval_one_env(f, node, env)
        match key {
          Num(n) => {
            let new_steps = steps.copy()
            new_steps[idx] = PathStep::Index(n.to_int())
            apply_update(node, new_steps, idx, updater, env)
          }
          Str(s) => {
            let new_steps = steps.copy()
            new_steps[idx] = PathStep::Field(s)
            apply_update(node, new_steps, idx, updater, env)
          }
          _ => Failed
        }
      }
      PathStep::Iterate =>
        match node {
          Arr(items) => {
            let out : Array[JVal] = []
            for item in items {
              match apply_update(item, steps, idx + 1, updater, env) {
                Updated(v) => out.push(v)
                Deleted => ()
                Failed => return Failed
              }
            }
            Updated(Arr(out))
          }
          Obj(entries) => {
            let out : Array[ObjEntry] = []
            for entry in entries {
              match apply_update(entry.value, steps, idx + 1, updater, env) {
                Updated(v) => out.push(ObjEntry::new(entry.key, v))
                Deleted => ()
                Failed => return Failed
              }
            }
            Updated(Obj(out))
          }
          _ => Failed
        }
      PathStep::Slice(lo_f, hi_f) => {
        let lo = match lo_f {
          None => Null
          Some(f) => eval_one_env(f, node, env)
        }
        let hi = match hi_f {
          None => Null
          Some(f) => eval_one_env(f, node, env)
        }
        match node {
          Arr(items) => {
            let bounds = node.slice_bounds(lo, hi)
            let a = bounds[0]
            let b = bounds[1]
            match
              apply_update(node.slice(lo, hi), steps, idx + 1, updater, env) {
              Updated(newv) =>
                match newv {
                  Arr(new_items) =>
                    Updated(Arr(splice_array(items, a, b, new_items)))
                  _ => Failed
                }
              Deleted => Updated(Arr(splice_array(items, a, b, [])))
              Failed => Failed
            }
          }
          Null =>
            // A slice of null is an empty array; updating
            // it creates the array (or stays null when the
            // update deletes it).
            match apply_update(Arr([]), steps, idx + 1, updater, env) {
              Updated(newv) =>
                match newv {
                  Arr(new_items) => Updated(Arr(new_items))
                  _ => Failed
                }
              Deleted => Deleted
              Failed => Failed
            }
          _ => Failed
        }
      }
    }
  }
}

///|
/// Insert or replace one object entry, keeping the position
/// of an existing key (a new key goes at the end).
fn set_field(
  entries : Array[ObjEntry],
  key : String,
  value : JVal,
) -> Array[ObjEntry] {
  let out : Array[ObjEntry] = []
  let mut found = false
  for entry in entries {
    if entry.key == key {
      out.push(ObjEntry::new(key, value))
      found = true
    } else {
      out.push(entry)
    }
  }
  if !found {
    out.push(ObjEntry::new(key, value))
  }
  out
}

///|
/// Remove one object entry, if present.
fn remove_field(entries : Array[ObjEntry], key : String) -> Array[ObjEntry] {
  let out : Array[ObjEntry] = []
  for entry in entries {
    if entry.key != key {
      out.push(entry)
    }
  }
  out
}

///|
/// `items[0:a] + middle + items[b:]`, for slice update.
fn splice_array(
  items : Array[JVal],
  a : Int32,
  b : Int32,
  middle : Array[JVal],
) -> Array[JVal] {
  let out : Array[JVal] = []
  let mut i = 0
  while i < a {
    out.push(items[i])
    i = i + 1
  }
  for x in middle {
    out.push(x)
  }
  let mut j = b
  while j < items.length() {
    out.push(items[j])
    j = j + 1
  }
  out
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
/// Look up one field of an object's entries, as a `JVal?`.
fn entry_field(entries : Array[ObjEntry], key : String) -> JVal? {
  for e in entries {
    if e.key == key {
      return Some(e.value)
    }
  }
  None
}

///|
/// Insert or replace one entry; later entries win, and the
/// surviving entry moves to the end (like jq's `from_entries`).
fn put_entry(
  entries : Array[ObjEntry],
  key : String,
  value : JVal,
) -> Array[ObjEntry] {
  let out : Array[ObjEntry] = []
  for e in entries {
    if e.key != key {
      out.push(e)
    }
  }
  out.push(ObjEntry::new(key, value))
  out
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
