///|
/// Tests for `parser.mbt` — MVP subset only.
/// The full jq grammar is P1. These tests lock in what MVP
/// promises in the README, so a regression is caught by
/// `moon test` instead of by a reviewer.
test "parse_filter: identity and fields" {
  match @lib.parse_filter(".") {
    Ok(f) => {
      let user = @lib.Obj([@lib.ObjEntry::new("name", @lib.Str("Yan"))])
      assert_eq(@lib.eval(f, user)[0].to_string(), "{\"name\":\"Yan\"}")
    }
    Err(msg) => {
      println(msg)
      assert_eq(true, false)
    }
  }
  match @lib.parse_filter(".name") {
    Ok(f) => {
      let user = @lib.Obj([@lib.ObjEntry::new("name", @lib.Str("Yan"))])
      assert_eq(@lib.eval(f, user)[0].to_string(), "\"Yan\"")
    }
    Err(msg) => {
      println(msg)
      assert_eq(true, false)
    }
  }
}

///|
test "parse_filter: dotted pipe" {
  match @lib.parse_filter(".users[].name") {
    Ok(f) => {
      let data = @lib.Obj([
        @lib.ObjEntry::new(
          "users",
          @lib.Arr([@lib.Obj([@lib.ObjEntry::new("name", @lib.Str("a"))])]),
        ),
      ])
      assert_eq(@lib.eval(f, data)[0].to_string(), "\"a\"")
    }
    Err(msg) => {
      println(msg)
      assert_eq(true, false)
    }
  }
}

///|
test "parse_filter: newly supported filters parse Ok" {
  // These were Err in the MVP parser; the full parser handles them.
  match @lib.parse_filter("map(. * 2)") {
    Ok(_) => assert_eq(true, true)
    Err(_) => assert_eq(true, false)
  }
  match @lib.parse_filter(".[] | select(.score >= 90)") {
    Ok(_) => assert_eq(true, true)
    Err(_) => assert_eq(true, false)
  }
}

///|
test "parse_filter: update assignment parses" {
  for
    f in [
      ".a |= . + 1", ".a = 1", ".a += .b", ".a -= 1", ".a *= 2", ".a /= 2", ".a %= 3",
      ".a //= 5", ".a.b[0] |= 1", ".[] |= . + 1", ".[0:2] |= [9]", "(.a, .b) |= . + 1",
      ". |= {b: 2}", "with_entries(.value += 10)",
    ] {
    match @lib.parse_filter(f) {
      Ok(_) => assert_eq(true, true)
      Err(msg) => {
        println("parse failed for '" + f + "': " + msg)
        assert_eq(true, false)
      }
    }
  }
}

///|
test "parse_filter: update assignment needs a path on the left" {
  // A non-path LHS, a chained assignment, and an
  // unparenthesised assignment as an object value are all
  // syntax errors in jq, and here too — not wrong answers.
  for f in ["1 |= 2", ".a + 1 |= 2", ".a = .b = 1", "{x: .a |= 5}", ".a |= "] {
    match @lib.parse_filter(f) {
      Ok(_) => {
        println("unexpectedly parsed '" + f + "'")
        assert_eq(true, false)
      }
      Err(_) => assert_eq(true, true)
    }
  }
}

///|
test "parse_filter: unsupported returns Err, not a wrong filter" {
  match @lib.parse_filter("def foo: .; foo") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
  match @lib.parse_filter("..") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
  match @lib.parse_filter(".a |") {
    Ok(_) => assert_eq(true, false)
    Err(_) => assert_eq(true, true)
  }
}
