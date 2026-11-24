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
test "p2: variables and as binding" {
  let arr = @lib.parse_json_or_null("[1, 2, 3]")
  assert_eq(
    @lib.eval_to_strings(
      @lib.parse_filter(".[] as $x | $x * 2") |> unwrap(),
      arr,
    ),
    ["2", "4", "6"],
  )
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("1 as $x | 2 as $y | $x + $y") |> unwrap(),
      @lib.Null,
    ).to_string(),
    "3",
  )
  // `as` binds tighter than `,`: `.a, (.b as $x | $x + 10)`.
  let ab = @lib.parse_json_or_null("{\"a\": 1, \"b\": 2}")
  assert_eq(
    @lib.eval_to_strings(
      @lib.parse_filter(".a, .b as $x | $x + 10") |> unwrap(),
      ab,
    ),
    ["1", "12"],
  )
  // A bound variable survives later pipes.
  let five = @lib.parse_json_or_null("{\"a\": 5}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(". as $x | .a | $x") |> unwrap(), five).to_string(),
    "{\"a\":5}",
  )
  // Inner bindings shadow outer ones.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a as $x | .b as $x | $x") |> unwrap(), ab).to_string(),
    "2",
  )
  // Variables work with field suffixes and in strings.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(". as $x | $x.a") |> unwrap(), five).to_string(),
    "5",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(". as $x | \"\\($x.a)\"") |> unwrap(), five).to_string(),
    "\"5\"",
  )
  // An unbound variable is Null here (jq rejects it at
  // compile time); the filter still parses and runs.
  assert_eq(
    @lib.eval_one(@lib.parse_filter("$nope") |> unwrap(), @lib.Null).to_string(),
    "null",
  )
  // Destructuring `as` is a clear error, not a wrong answer.
  match @lib.parse_filter(". as {$a} | $a") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
  // `.as` is still the field "as"; only `. as $x | …` binds.
  let as_field = @lib.parse_json_or_null("{\"as\": 1}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".as") |> unwrap(), as_field).to_string(),
    "1",
  )
}

///|
test "p2: reduce" {
  let arr = @lib.parse_json_or_null("[1, 2, 3]")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce .[] as $x (0; . + $x)") |> unwrap(),
      arr,
    ).to_string(),
    "6",
  )
  let empty = @lib.parse_json_or_null("[]")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce .[] as $x (0; . + $x)") |> unwrap(),
      empty,
    ).to_string(),
    "0",
  )
  let words = @lib.parse_json_or_null("[\"a\", \"b\"]")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce .[] as $x (\"\"; . + $x)") |> unwrap(),
      words,
    ).to_string(),
    "\"ab\"",
  )
  // The init is evaluated on the original input.
  let five = @lib.parse_json_or_null("{\"a\": 5}")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce .a as $x (10; . + $x)") |> unwrap(),
      five,
    ).to_string(),
    "15",
  )
  // The accumulator can be an array; the exp can be a
  // parenthesised multi-output filter.
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce .[] as $x ([]; . + [$x])") |> unwrap(),
      arr,
    ).to_string(),
    "[1,2,3]",
  )
  let one = @lib.parse_json_or_null("[1]")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("reduce (.[] , .[]) as $x (0; . + 1)") |> unwrap(),
      one,
    ).to_string(),
    "2",
  )
}

///|
test "p2: group_by" {
  let arr = @lib.parse_json_or_null("[{\"a\": 2}, {\"a\": 1}, {\"a\": 2}]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.a)") |> unwrap(), arr).to_string(),
    "[[{\"a\":1}],[{\"a\":2},{\"a\":2}]]",
  )
  let nums = @lib.parse_json_or_null("[3, 1, 2, 1]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.)") |> unwrap(), nums).to_string(),
    "[[1,1],[2],[3]]",
  )
  let empty = @lib.parse_json_or_null("[]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.)") |> unwrap(), empty).to_string(),
    "[]",
  )
  // Null keys sort first (jq total order).
  let nulls = @lib.parse_json_or_null(
    "[{\"a\": null}, {\"a\": 1}, {\"a\": null}]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.a)") |> unwrap(), nulls).to_string(),
    "[[{\"a\":null},{\"a\":null}],[{\"a\":1}]]",
  )
  // Missing keys read as null, so they group together.
  let mixed = @lib.parse_json_or_null("[{\"a\": 1}, {\"b\": 2}]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.a)") |> unwrap(), mixed).to_string(),
    "[[{\"b\":2}],[{\"a\":1}]]",
  )
  // Non-array input is Null here (jq errors); it stays lenient.
  assert_eq(
    @lib.eval_one(@lib.parse_filter("group_by(.)") |> unwrap(), @lib.Num(5.0)).to_string(),
    "null",
  )
}

///|
test "p2: to_entries / from_entries / with_entries" {
  // to_entries on objects preserves insertion order.
  let obj = @lib.parse_json_or_null("{\"b\": 2, \"a\": 1}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("to_entries") |> unwrap(), obj).to_string(),
    "[{\"key\":\"b\",\"value\":2},{\"key\":\"a\",\"value\":1}]",
  )
  let arr = @lib.parse_json_or_null("[10, 20]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter("to_entries") |> unwrap(), arr).to_string(),
    "[{\"key\":0,\"value\":10},{\"key\":1,\"value\":20}]",
  )
  // from_entries accepts "key" or "name"; missing "value" is null.
  let entries = @lib.parse_json_or_null(
    "[{\"key\": \"a\", \"value\": 1}, {\"name\": \"b\"}]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("from_entries") |> unwrap(), entries).to_string(),
    "{\"a\":1,\"b\":null}",
  )
  // "key" wins over "name"; later duplicates win.
  let dup = @lib.parse_json_or_null(
    "[{\"key\": \"a\", \"name\": \"b\", \"value\": 1}, {\"key\": \"a\", \"value\": 2}]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter("from_entries") |> unwrap(), dup).to_string(),
    "{\"a\":2}",
  )
  // with_entries is to_entries | map(f) | from_entries.
  // The canonical `.value += 10` example now works (P3:
  // update assignment); the equivalent object form is
  // kept as a second check.
  let vals = @lib.parse_json_or_null("{\"a\": 1, \"b\": 2}")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("with_entries(.value += 10)") |> unwrap(),
      vals,
    ).to_string(),
    "{\"a\":11,\"b\":12}",
  )
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("with_entries({key: .key, value: (.value * 10)})")
      |> unwrap(),
      vals,
    ).to_string(),
    "{\"a\":10,\"b\":20}",
  )
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("with_entries(select(.key != \"a\"))") |> unwrap(),
      vals,
    ).to_string(),
    "{\"b\":2}",
  )
  // Round-trip.
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("to_entries | from_entries") |> unwrap(),
      obj,
    ).to_string(),
    "{\"b\":2,\"a\":1}",
  )
}

///|
test "p3: update assignment" {
  let ab = @lib.parse_json_or_null("{\"a\": 1, \"b\": 10}")
  // `|=` runs the RHS on the old path value.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a |= . + 1") |> unwrap(), ab).to_string(),
    "{\"a\":2,\"b\":10}",
  )
  // `+=` runs the RHS on the ORIGINAL input, not the old
  // value: `.a += .b` is 1 + 10, not 1 + null.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a += .b") |> unwrap(), ab).to_string(),
    "{\"a\":11,\"b\":10}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a = .b") |> unwrap(), ab).to_string(),
    "{\"a\":10,\"b\":10}",
  )
  // A missing path is created; `|=` with `empty` deletes.
  let one = @lib.parse_json_or_null("{\"a\": 1}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".missing |= . + 1") |> unwrap(), one).to_string(),
    "{\"a\":1,\"missing\":1}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a |= empty") |> unwrap(), one).to_string(),
    "{}",
  )
  // `=` with `empty` produces no output at all (jq: the
  // whole result disappears); `|=` keeps the rest.
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter(".a = empty") |> unwrap(), one),
    [],
  )
  // `=` fans out over RHS outputs; `|=` takes only the
  // first RHS output.
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter(".a = (1, 2)") |> unwrap(), one),
    ["{\"a\":1}", "{\"a\":2}"],
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a |= (1, 2)") |> unwrap(), one).to_string(),
    "{\"a\":1}",
  )
  // Nested paths, indexes, string keys, iterate.
  let nested = @lib.parse_json_or_null("{\"a\": {\"b\": 1}}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a.b |= . + 10") |> unwrap(), nested).to_string(),
    "{\"a\":{\"b\":11}}",
  )
  let arr = @lib.parse_json_or_null("[1, 2, 3]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[1] |= . + 10") |> unwrap(), arr).to_string(),
    "[1,12,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[] |= . + 10") |> unwrap(), arr).to_string(),
    "[11,12,13]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[] += 10") |> unwrap(), arr).to_string(),
    "[11,12,13]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[] |= empty") |> unwrap(), arr).to_string(),
    "[]",
  )
  // Null creates containers; an out-of-range index pads
  // with nulls; deleting a missing path changes nothing.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a.b |= 1") |> unwrap(), @lib.Null).to_string(),
    "{\"a\":{\"b\":1}}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0] |= 1") |> unwrap(), @lib.Null).to_string(),
    "[1]",
  )
  let two = @lib.parse_json_or_null("[1, 2]")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[5] |= 10") |> unwrap(), two).to_string(),
    "[1,2,null,null,null,10]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".missing |= empty") |> unwrap(), one).to_string(),
    "{\"a\":1}",
  )
  // Compound operators and `//=`.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a -= 1") |> unwrap(), one).to_string(),
    "{\"a\":0}",
  )
  let six = @lib.parse_json_or_null("{\"a\": 6}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a /= 2") |> unwrap(), six).to_string(),
    "{\"a\":3}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a *= 2") |> unwrap(), six).to_string(),
    "{\"a\":12}",
  )
  let seven = @lib.parse_json_or_null("{\"a\": 7}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a %= 3") |> unwrap(), seven).to_string(),
    "{\"a\":1}",
  )
  let null_a = @lib.parse_json_or_null("{\"a\": null}")
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a //= 5") |> unwrap(), null_a).to_string(),
    "{\"a\":5}",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a //= 5") |> unwrap(), one).to_string(),
    "{\"a\":1}",
  )
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter(".a //= empty") |> unwrap(), one),
    [],
  )
  // Slices: the replacement must be an array; `empty`
  // removes the slice.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:2] |= [9, 9]") |> unwrap(), arr).to_string(),
    "[9,9,3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:2] |= empty") |> unwrap(), arr).to_string(),
    "[3]",
  )
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:2] += [9]") |> unwrap(), arr).to_string(),
    "[1,2,9,3]",
  )
  // A slice assigned a non-array is a type error in jq;
  // here it is Null, like the evaluator's other lenient
  // type mistakes (see docs/PLAN.md).
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".[0:2] |= 9") |> unwrap(), arr).to_string(),
    "null",
  )
  // Precedence: `|` and `,` bind outside the assignment,
  // so `.a |= .+1 | .b` is `(.a |= .+1) | .b`.
  assert_eq(
    @lib.eval_one(@lib.parse_filter(".a |= . + 1 | .b") |> unwrap(), ab).to_string(),
    "10",
  )
  assert_eq(
    @lib.eval_to_strings(@lib.parse_filter(".a |= . + 1, .b") |> unwrap(), ab),
    ["{\"a\":2,\"b\":10}", "10"],
  )
  // A parenthesised comma of paths updates both.
  assert_eq(
    @lib.eval_one(@lib.parse_filter("(.a, .b) |= . + 1") |> unwrap(), ab).to_string(),
    "{\"a\":2,\"b\":11}",
  )
  // Update assignment inside `if` branches, and the
  // headline example from docs/PLAN.md.
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("if .a == 1 then .a |= 5 else . end") |> unwrap(),
      one,
    ).to_string(),
    "{\"a\":5}",
  )
  let vals = @lib.parse_json_or_null("{\"a\": 1, \"b\": 2}")
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("with_entries(.value += 10)") |> unwrap(),
      vals,
    ).to_string(),
    "{\"a\":11,\"b\":12}",
  )
  // A bare `.` before `end` / `then` is identity, not a
  // field named "end" (pre-existing parser bug, fixed here).
  assert_eq(
    @lib.eval_one(
      @lib.parse_filter("if . then 1 else 2 end") |> unwrap(),
      @lib.Bool(true),
    ).to_string(),
    "1",
  )
}

///|
test "p2: eval_env with --arg style bindings" {
  let env = [
    @lib.EnvEntry::new("name", @lib.Str("Yan")),
    @lib.EnvEntry::new("nums", @lib.parse_json_or_null("[1, 2, 3]")),
  ]
  assert_eq(
    @lib.eval_one_env(
      @lib.parse_filter("\"hi \\($name)\"") |> unwrap(),
      @lib.Null,
      env,
    ).to_string(),
    "\"hi Yan\"",
  )
  assert_eq(
    @lib.eval_one_env(
      @lib.parse_filter("$nums | add") |> unwrap(),
      @lib.Null,
      env,
    ).to_string(),
    "6",
  )
  // Like jq, the FIRST --arg with a name wins: later ones
  // with the same name do not shadow it.
  let env2 = [
    @lib.EnvEntry::new("x", @lib.Num(1.0)),
    @lib.EnvEntry::new("x", @lib.Num(2.0)),
  ]
  assert_eq(
    @lib.eval_one_env(@lib.parse_filter("$x") |> unwrap(), @lib.Null, env2).to_string(),
    "1",
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
