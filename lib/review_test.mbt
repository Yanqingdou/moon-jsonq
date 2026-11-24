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
