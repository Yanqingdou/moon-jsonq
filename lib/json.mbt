/// moon-jsonq: JSON value type.
///
/// This is our own value type on purpose, instead of reusing
/// `@json.Json` directly in the evaluator.
///
/// Why:
/// - `@json.Json` is `Null | True | False | Number | String | Array | Object`
///   in moonbitlang/core, with `Number(Double, repr~ : String?)` and
///   `Object(Map[String, Json])`. Its constructors are `pub fn`s
///   (`Json::number`, `Json::string`, …), and matching on it is fine,
///   but our evaluator wants one explicit number type and one
///   object representation it controls.
/// - Our `JVal` has `Num(Double)` and `Obj(Array[ObjEntry])`, and a
///   single `to_string` the evaluator and tests can rely on.
/// - The bridge to `@json` lives in `json_io.mbt`:
///   `@json.parse(s)` -> `JVal`, and `JVal` -> `Json` -> `.stringify()`.
///
/// Verified against moon 0.1.20261119, core `moonbitlang/core/json`.

///|
/// One key/value pair inside a JSON object.
/// We use a struct (not a tuple) so field access is `entry.key`
/// and `entry.value` everywhere, with no tuple-index guessing.
pub(all) struct ObjEntry {
  key : String
  value : JVal
}

///|
pub fn ObjEntry::new(key : String, value : JVal) -> ObjEntry {
  { key, value, }
}

///|
/// JSON value. Mirrors jq / JSON exactly, nothing more.
pub(all) enum JVal {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  Arr(Array[JVal])
  Obj(Array[ObjEntry])
}

///|
/// Build an object from key/value pairs, in order.
pub fn obj(entries : Array[ObjEntry]) -> JVal {
  Obj(entries)
}

///|
/// `true` in jq is truthy, `false` and `null` are falsy.
/// Everything else (including `0`, `""`, `[]`, `{}`) is truthy,
/// exactly like jq.
pub fn JVal::is_truthy(self : JVal) -> Bool {
  match self {
    Null => false
    Bool(b) => b
    _ => true
  }
}

///|
/// jq `type`: "null" | "boolean" | "number" | "string" | "array" | "object".
pub fn JVal::type_name(self : JVal) -> String {
  match self {
    Null => "null"
    Bool(_) => "boolean"
    Num(_) => "number"
    Str(_) => "string"
    Arr(_) => "array"
    Obj(_) => "object"
  }
}

///|
/// jq ordering rank, for `sort` / comparison:
/// null (0) < false (1) < true (2) < number (3) < string (4)
/// < array (5) < object (6).
fn JVal::rank(self : JVal) -> Int32 {
  match self {
    Null => 0
    Bool(false) => 1
    Bool(true) => 2
    Num(_) => 3
    Str(_) => 4
    Arr(_) => 5
    Obj(_) => 6
  }
}

///|
/// jq total order. Returns -1, 0 or 1.
/// Numbers compare numerically, strings lexicographically,
/// booleans false < true, arrays compare element by element,
/// objects compare by sorted keys then values.
pub fn JVal::compare(self : JVal, other : JVal) -> Int32 {
  let r1 = self.rank()
  let r2 = other.rank()
  if r1 != r2 {
    if r1 < r2 {
      -1
    } else {
      1
    }
  } else {
    match (self, other) {
      (Null, Null) => 0
      (Bool(a), Bool(b)) => if a == b { 0 } else if !a { -1 } else { 1 }
      (Num(a), Num(b)) => if a < b { -1 } else if a > b { 1 } else { 0 }
      (Str(a), Str(b)) => if a == b { 0 } else if a < b { -1 } else { 1 }
      (Arr(a), Arr(b)) => {
        let mut i = 0
        let n = if a.length() < b.length() { a.length() } else { b.length() }
        while i < n {
          let c = a[i].compare(b[i])
          if c != 0 {
            return c
          }
          i = i + 1
        }
        if a.length() < b.length() {
          -1
        } else if a.length() > b.length() {
          1
        } else {
          0
        }
      }
      (Obj(a), Obj(b)) => {
        // Compare by sorted keys, then values, like jq.
        let ka = sorted_keys(a)
        let kb = sorted_keys(b)
        let mut i = 0
        let n = if ka.length() < kb.length() {
          ka.length()
        } else {
          kb.length()
        }
        while i < n {
          if ka[i] != kb[i] {
            if ka[i] < kb[i] {
              return -1
            } else {
              return 1
            }
          }
          let c = self.field(ka[i]).compare(other.field(kb[i]))
          if c != 0 {
            return c
          }
          i = i + 1
        }
        if ka.length() < kb.length() {
          -1
        } else if ka.length() > kb.length() {
          1
        } else {
          0
        }
      }
      _ => 0
    }
  }
}

///|
/// Sorted object keys, as plain strings. Used by `keys` and by
/// object comparison. Insertion sort is fine here: objects in
/// jq filters are usually small, and this keeps the code free
/// of a `Compare` impl on `JVal`.
fn sorted_keys(entries : Array[ObjEntry]) -> Array[String] {
  let keys : Array[String] = []
  for entry in entries {
    keys.push(entry.key)
  }
  // Insertion sort, in place.
  let mut i = 1
  while i < keys.length() {
    let mut j = i
    while j > 0 && keys[j - 1] > keys[j] {
      let tmp = keys[j - 1]
      keys[j - 1] = keys[j]
      keys[j] = tmp
      j = j - 1
    }
    i = i + 1
  }
  keys
}

///|
/// Slice an array or a string, like jq `.[a:b]`.
/// `lo` / `hi` are the evaluated bound values: `Null` means
/// omitted, `Num(n)` is floored to an integer (jq floors,
/// so `.[1.5:3]` starts at 1 and `.[-1.5:3]` at `len - 2`).
/// Negative indices count from the end, out-of-range bounds
/// are clamped, and `lo > hi` gives an empty result.
/// `Null` input slices to `Null` (like jq); anything else
/// that is not an array or a string gives `Null` (jq errors,
/// we stay lenient like the rest of the evaluator).
/// A bound that is neither a number nor null also gives `Null`.
pub fn JVal::slice(self : JVal, lo : JVal, hi : JVal) -> JVal {
  // A bound must be a number or null (omitted); anything else
  // is an error in jq, and Null here, like the rest of the
  // evaluator's lenient behaviour.
  match (lo, hi) {
    (Num(_) | Null, Num(_) | Null) => ()
    _ => return Null
  }
  match self {
    Null => Null
    Arr(items) => {
      let len = items.length()
      let a = clamp_bound(lo, len, 0)
      let b = clamp_bound(hi, len, len)
      // Collect by hand: items[a:b] is an ArrayView, not an Array.
      let out : Array[JVal] = []
      let mut i = a
      while i < b {
        out.push(items[i])
        i = i + 1
      }
      Arr(out)
    }
    Str(s) => {
      let chars = s.to_array()
      let len = chars.length()
      let a = clamp_bound(lo, len, 0)
      let b = clamp_bound(hi, len, len)
      let out : Array[Char] = []
      let mut i = a
      while i < b {
        out.push(chars[i])
        i = i + 1
      }
      Str(String::from_array(out))
    }
    _ => Null
  }
}

///|
/// Resolve one slice bound to a clamped index in `[0, len]`.
/// `Null` means "omitted", so it resolves to `default`
/// (0 for the lower bound, `len` for the upper).
fn clamp_bound(v : JVal, len : Int32, default : Int32) -> Int32 {
  let i = match v {
    Null => default
    Num(n) => {
      // Floor, like jq: 1.5 -> 1, -1.5 -> -2.
      let f = n.floor().to_int()
      if f < 0 {
        len + f
      } else {
        f
      }
    }
    _ => default
  }
  if i < 0 {
    0
  } else if i > len {
    len
  } else {
    i
  }
}

///|
/// Look up `key` in an object. Missing key -> `Null`, like jq's
/// `.missing` (which returns `null`, it does not error).
pub fn JVal::field(self : JVal, key : String) -> JVal {
  match self {
    Obj(entries) => {
      for entry in entries {
        if entry.key == key {
          return entry.value
        }
      }
      Null
    }
    _ => Null
  }
}

///|
/// Index into an array. Negative index counts from the end,
/// like jq: `.[-1]` is the last element. Out of range -> `Null`.
pub fn JVal::index(self : JVal, i : Int32) -> JVal {
  match self {
    Arr(items) => {
      let len = items.length()
      let idx = if i < 0 { len + i } else { i }
      if idx < 0 || idx >= len {
        Null
      } else {
        items[idx]
      }
    }
    _ => Null
  }
}

///|
/// All values of an array or object, in order.
/// For objects this is the values, not the keys (jq `.[]`).
pub fn JVal::iterate(self : JVal) -> Array[JVal] {
  match self {
    Arr(items) => items
    Obj(entries) => {
      let out : Array[JVal] = []
      for entry in entries {
        out.push(entry.value)
      }
      out
    }
    _ => []
  }
}

///|
/// `length` in jq: string length, array length, object key count,
/// number's absolute value, `null` -> 0, `true/false` -> error
/// in real jq. Here we return `Null` for bool instead of erroring,
/// so the evaluator never crashes on a type mistake.
pub fn JVal::length(self : JVal) -> JVal {
  match self {
    Null => Num(0.0)
    Bool(_) => Null
    Num(n) => if n < 0.0 { Num(0.0 - n) } else { Num(n) }
    Str(s) => Num(s.length().to_double())
    Arr(items) => Num(items.length().to_double())
    Obj(entries) => Num(entries.length().to_double())
  }
}

///|
/// `keys` in jq: sorted keys for objects, `[0, 1, ...]` for arrays.
pub fn JVal::keys(self : JVal) -> JVal {
  match self {
    Obj(entries) => {
      let out : Array[JVal] = []
      for key in sorted_keys(entries) {
        out.push(Str(key))
      }
      Arr(out)
    }
    Arr(items) => {
      let out : Array[JVal] = []
      let mut i = 0
      while i < items.length() {
        out.push(Num(i.to_double()))
        i = i + 1
      }
      Arr(out)
    }
    _ => Null
  }
}

///|
/// Compact JSON printing, e.g. `{"name":"Yan","score":95}`.
/// Strings are printed through `@json.Json::string(s).stringify()`,
/// so quotes, backslashes, newlines and control characters are
/// escaped exactly like a JSON encoder would. Object key order
/// is insertion order, matching the input document.
pub fn JVal::to_string(self : JVal) -> String {
  match self {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Num(n) => n.to_string()
    Str(s) => @json.Json::string(s).stringify()
    Arr(items) => {
      let mut out = "["
      let mut first = true
      for item in items {
        if !first {
          out = out + ","
        }
        first = false
        out = out + item.to_string()
      }
      out + "]"
    }
    Obj(entries) => {
      let mut out = "{"
      let mut first = true
      for entry in entries {
        if !first {
          out = out + ","
        }
        first = false
        out = out +
          @json.Json::string(entry.key).stringify() +
          ":" +
          entry.value.to_string()
      }
      out + "}"
    }
  }
}

///|
/// Pretty JSON with 2-space indent, for `--pretty`.
/// Delegates to `@json` so indentation and escaping are correct.
pub fn JVal::to_pretty_string(self : JVal) -> String {
  self.to_json().stringify(indent=2)
}

///|
/// Convert to `@json.Json`, for output and for interop.
/// Object key order is preserved (Map is insertion-ordered).
pub fn JVal::to_json(self : JVal) -> @json.Json {
  match self {
    Null => @json.Json::null()
    Bool(b) => @json.Json::boolean(b)
    Num(n) => @json.Json::number(n)
    Str(s) => @json.Json::string(s)
    Arr(items) => {
      let out : Array[@json.Json] = []
      for item in items {
        out.push(item.to_json())
      }
      @json.Json::array(out)
    }
    Obj(entries) => {
      let map : Map[String, @json.Json] = Map([])
      for entry in entries {
        map[entry.key] = entry.value.to_json()
      }
      @json.Json::object(map)
    }
  }
}
