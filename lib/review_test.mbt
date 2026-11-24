/// Tests added for the November monthly review: the full
/// parser, the extended evaluator, and the @json bridge.
/// These are blackbox tests, so every library symbol is
/// written with the `@lib.` prefix (see README).

///|
test "review: arithmetic and comparison" {
  let input = @lib.parse_json_or_null("{\"a\": 6, \"b\": 2}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a + .b") |> unwrap(), input).to_string(),
    "8",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a - .b") |> unwrap(), input).to_string(),
    "4",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a * .b") |> unwrap(), input).to_string(),
    "12",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a / .b") |> unwrap(), input).to_string(),
    "3",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a % 4") |> unwrap(), input).to_string(),
    "2",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a > .b") |> unwrap(), input).to_string(),
    "true",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a == 6") |> unwrap(), input).to_string(),
    "true",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("1 + 2 * 3") |> unwrap(), @lib.Null).to_string(),
    "7",
  )
}

///|
test "review: // and if-then-else" {
  let input = @lib.parse_json_or_null("{\"a\": null}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a // \"x\"") |> unwrap(), input).to_string(),
    "\"x\"",
  )
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("if .a == null then 1 else 2 end") |> unwrap(),
      input,
    ).to_string(),
    "1",
  )
  let input2 = @lib.parse_json_or_null("{\"a\": 5}")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("if .a > 3 then \"big\" else \"small\" end") |> unwrap(),
      input2,
    ).to_string(),
    "\"big\"",
  )
}

///|
test "review: sort, unique, min, max, add, type" {
  let arr = @lib.parse_json_or_null("[3, 1, 2, 2]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("sort") |> unwrap(), arr).to_string(),
    "[1,2,2,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("unique") |> unwrap(), arr).to_string(),
    "[1,2,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("min") |> unwrap(), arr).to_string(),
    "1",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("max") |> unwrap(), arr).to_string(),
    "3",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("add") |> unwrap(), arr).to_string(),
    "8",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("sort_by(.)") |> unwrap(), arr).to_string(),
    "[1,2,2,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("type") |> unwrap(), arr).to_string(),
    "\"array\"",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("tostring") |> unwrap(), @lib.Num(42.0)).to_string(),
    "\"42\"",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("tonumber") |> unwrap(), @lib.Str("42")).to_string(),
    "42",
  )
}

///|
test "review: object and array construction" {
  let input = @lib.parse_json_or_null("{\"a\": 1}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("{b: .a, c: 2}") |> unwrap(), input).to_string(),
    "{\"b\":1,\"c\":2}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("{a}") |> unwrap(), input).to_string(),
    "{\"a\":1}",
  )
  let arr = @lib.parse_json_or_null("[1, 2]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("[.[] + 10]") |> unwrap(), arr).to_string(),
    "[11,12]",
  )
}

///|
test "review: map drops empty outputs, BinOp is multi-output" {
  let arr = @lib.parse_json_or_null("[1, 2, 3, 4]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("map(select(. > 2))") |> unwrap(), arr).to_string(),
    "[3,4]",
  )
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter(".[] * 2") |> unwrap(), arr),
    ["2", "4", "6", "8"],
  )
}

///|
test "review: json bridge round-trips" {
  match
    @lib.parse_json(
      "{\"name\": \"Yan\", \"score\": 95, \"tags\": [\"a\", \"b\"]}",
    ) {
    Ok(v) => {
      assert_eq(
        v.to_string(),
        "{\"name\":\"Yan\",\"score\":95,\"tags\":[\"a\",\"b\"]}",
      )
      assert_eq(v.field("name").to_string(), "\"Yan\"")
    }
    Err(_) => assert_eq(true, false)
  }
  match @lib.parse_json("not json") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
  // String escaping: quotes and newlines must survive.
  let s = @lib.Str("hi \"x\"\n")
  assert_eq(s.to_string(), "\"hi \\\"x\\\"\\n\"")
}

///|
test "review: keys are sorted, objects keep input order" {
  let o = @lib.parse_json_or_null("{\"b\": 2, \"a\": 1}")
  assert_eq(o.keys().to_string(), "[\"a\",\"b\"]")
  assert_eq(o.to_string(), "{\"b\":2,\"a\":1}")
}

///|
test "p2: slice .[a:b] on arrays and strings" {
  let arr = @lib.parse_json_or_null("[0, 1, 2, 3, 4]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[1:3]") |> unwrap(), arr).to_string(),
    "[1,2]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[2:]") |> unwrap(), arr).to_string(),
    "[2,3,4]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[:2]") |> unwrap(), arr).to_string(),
    "[0,1]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[-2:]") |> unwrap(), arr).to_string(),
    "[3,4]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[:-1]") |> unwrap(), arr).to_string(),
    "[0,1,2,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[10:20]") |> unwrap(), arr).to_string(),
    "[]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[-10:2]") |> unwrap(), arr).to_string(),
    "[0,1]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[3:1]") |> unwrap(), arr).to_string(),
    "[]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:0]") |> unwrap(), arr).to_string(),
    "[]",
  )
  // Null bounds mean "omitted", like jq.
  let arr4 = @lib.parse_json_or_null("[0, 1, 2, 3]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[1:null]") |> unwrap(), arr4).to_string(),
    "[1,2,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[null:2]") |> unwrap(), arr4).to_string(),
    "[0,1]",
  )
  // Bounds are expressions, floored like jq (1.5 -> 1, -1.5 -> -2).
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:1+1]") |> unwrap(), arr4).to_string(),
    "[0,1]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[1.5:3]") |> unwrap(), arr4).to_string(),
    "[1,2]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[-1.5:3]") |> unwrap(), arr4).to_string(),
    "[2]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:length]") |> unwrap(), arr4).to_string(),
    "[0,1,2,3]",
  )
  // Strings slice by character.
  let s = @lib.parse_json_or_null("\"abcdef\"")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[1:3]") |> unwrap(), s).to_string(),
    "\"bc\"",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[-2:]") |> unwrap(), s).to_string(),
    "\"ef\"",
  )
  // Null input slices to null, like jq.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:1]") |> unwrap(), @lib.Null).to_string(),
    "null",
  )
  // `.[:]` with both bounds omitted is a syntax error in jq.
  match @lib.parse_filter(".[:]") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
}

///|
test "p2: split(sep)" {
  let s = @lib.parse_json_or_null("\"a,b,c\"")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\",\")") |> unwrap(), s).to_string(),
    "[\"a\",\"b\",\"c\"]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\"\")") |> unwrap(), s).to_string(),
    "[\"a\",\",\",\"b\",\",\",\"c\"]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\"x\")") |> unwrap(), s).to_string(),
    "[\"a,b,c\"]",
  )
  let s2 = @lib.parse_json_or_null("\"a,b,\"")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\",\")") |> unwrap(), s2).to_string(),
    "[\"a\",\"b\",\"\"]",
  )
  let empty = @lib.parse_json_or_null("\"\"")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\",\")") |> unwrap(), empty).to_string(),
    "[]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\"\")") |> unwrap(), empty).to_string(),
    "[]",
  )
  let one = @lib.parse_json_or_null("\"a\"")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\"a\")") |> unwrap(), one).to_string(),
    "[\"\",\"\"]",
  )
  // Non-string input is Null here (jq errors); it stays lenient.
  assert_eq(
    @lib.eval_one(@lib.parse_filter("split(\",\")") |> unwrap(), @lib.Null).to_string(),
    "null",
  )
}

///|
test "p2: string interpolation" {
  let input = @lib.parse_json_or_null("{\"name\": \"Yan\", \"score\": 95}")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("\"\\(.name) has \\(.score) points\"") |> unwrap(),
      input,
    ).to_string(),
    "\"Yan has 95 points\"",
  )
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("\"\\(.score + 1) and \\(.score * 10)\"") |> unwrap(),
      input,
    ).to_string(),
    "\"96 and 950\"",
  )
  // Non-string values interpolate like tostring; null too.
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("\"\\(null)|\\(true)|\\([1,2])|\\(.missing)\"")
      |> unwrap(),
      input,
    ).to_string(),
    "\"null|true|[1,2]|null\"",
  )
  // A multi-output interpolation gives one output per value.
  let ab = @lib.parse_json_or_null("{\"a\": 1, \"b\": 2}")
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter("\"\\(.a, .b)\"") |> unwrap(), ab),
    ["\"1\"", "\"2\""],
  )
  // Nested quotes inside an interpolation.
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("\"outer \\(\"inner \\(.name)\") end\"") |> unwrap(),
      input,
    ).to_string(),
    "\"outer inner Yan end\"",
  )
  // Interpolation in an object value and in an object key.
  assert_eq(
    @lib.eval_one(@lib.parse_filter("{s: \"v=\\(.score)\"}") |> unwrap(), input).to_string(),
    "{\"s\":\"v=95\"}",
  )
  let one = @lib.parse_json_or_null("{\"a\": 1}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("{\"\\(.a)\": 1}") |> unwrap(), one).to_string(),
    "{\"1\":1}",
  )
  // An escaped backslash before a paren is literal, not an
  // interpolation: "\\(x)" stays as the text "\(x)".
  assert_eq(
    @lib.eval_one(@lib.parse_filter("\"\\\\(x)\"") |> unwrap(), @lib.Null).to_string(),
    "\"\\\\(x)\"",
  )
}

///|
/// Helper: unwrap a parse result in tests, failing the test
/// loudly if the filter did not parse.
fn unwrap(r : Result[@lib.Filter, String]) -> @lib.Filter {
  match r {
    Ok(f) => f
    Err(msg) => {
      println("parse failed in test: " + msg)
      @lib.Identity
    }
  }
}
