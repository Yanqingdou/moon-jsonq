/// moon-jsonq: bridge to MoonBit's built-in JSON.
///
/// MoonBit's core library has a `json` package:
///   `Json` enum = `Null | True | False | Number(Double, repr~ : String?)`
///   `| String(String) | Array(Array[Json]) | Object(Map[String, Json])`
///   `@json.parse(s)` turns a string into a `Json` (raises
///   `ParseError` on bad input)
///   `json.stringify()` turns a `Json` back into a string
///   Constructors: `Json::null()`, `Json::boolean(b)`,
///   `Json::number(n)`, `Json::string(s)`, `Json::array(a)`,
///   `Json::object(map)`
///
/// Verified against moon 0.1.20261119, core `moonbitlang/core/json`.
/// `Object` is a `Map`, which is insertion-ordered, so object
/// key order survives the round trip.

///|
/// Parse a JSON document into our `JVal`.
/// Returns `Err` with a human-readable message on bad input,
/// instead of raising, so the CLI can print it and exit 1.
pub fn parse_json(text : String) -> Result[JVal, String] {
  Ok(from_json(@json.parse(text))) catch {
    e => Err("invalid JSON: " + e.to_string())
  }
}

///|
/// Parse JSON, or return `Null` on error. Used only in tests
/// that need a quick value without error handling.
pub fn parse_json_or_null(text : String) -> JVal {
  match parse_json(text) {
    Ok(v) => v
    Err(_) => Null
  }
}

///|
/// Convert `@json.Json` -> `JVal`, recursively.
pub fn from_json(j : @json.Json) -> JVal {
  match j {
    @json.Null => Null
    @json.True => Bool(true)
    @json.False => Bool(false)
    @json.Number(n, ..) => Num(n)
    @json.String(s) => Str(s)
    @json.Array(items) => {
      let out : Array[JVal] = []
      for item in items {
        out.push(from_json(item))
      }
      Arr(out)
    }
    @json.Object(m) => {
      let entries : Array[ObjEntry] = []
      for (key, value) in m {
        entries.push(ObjEntry::new(key, from_json(value)))
      }
      Obj(entries)
    }
  }
}

///|
/// Parse a JSON document that may contain several values
/// separated by whitespace (e.g. NDJSON with one value per
/// line, or jq's default multi-value stdin). Returns all
/// values, in order. A document with a single value returns
/// a one-element array. Used for `--slurp` and for the
/// CLI's multi-document mode.
pub fn parse_json_stream(text : String) -> Result[Array[JVal], String] {
  // Split on lines; each non-empty line must be one JSON value.
  // This covers the common NDJSON case. A value split across
  // several lines (pretty-printed JSON) is handled by the
  // caller falling back to `parse_json` on the whole text.
  let values : Array[JVal] = []
  for line in text.split("\n") {
    let trimmed = line.trim()
    if trimmed.length() > 0 {
      match parse_json(trimmed.to_owned()) {
        Ok(v) => values.push(v)
        Err(msg) => return Err(msg)
      }
    }
  }
  Ok(values)
}
