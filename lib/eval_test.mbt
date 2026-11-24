///|
/// Tests for `eval.mbt` — the filter evaluator.
/// These are the golden tests for the November MVP. Each test
/// is taken from the jq manual / README examples, so a reviewer
/// can check the expected output against real jq in seconds:
///   echo '<input>' | jq '<filter>'
test "eval: identity and field" {
  let user = @lib.Obj([
    @lib.ObjEntry::new("name", @lib.Str("Yan")),
    @lib.ObjEntry::new("score", @lib.Num(95.0)),
  ])
  assert_eq(
    @lib.eval(@lib.Identity, user)[0].to_string(),
    "{\"name\":\"Yan\",\"score\":95}",
  )
  assert_eq(@lib.eval(@lib.Field("name"), user)[0].to_string(), "\"Yan\"")
  assert_eq(@lib.eval(@lib.Field("score"), user)[0].to_string(), "95")
}

///|
test "eval: pipe .users[].name" {
  let data = @lib.Obj([
    @lib.ObjEntry::new(
      "users",
      @lib.Arr([
        @lib.Obj([@lib.ObjEntry::new("name", @lib.Str("a"))]),
        @lib.Obj([@lib.ObjEntry::new("name", @lib.Str("b"))]),
      ]),
    ),
  ])
  let f = @lib.Pipe([@lib.Field("users"), @lib.Iterate, @lib.Field("name")])
  let outs = @lib.eval(f, data)
  assert_eq(outs.length(), 2)
  assert_eq(outs[0].to_string(), "\"a\"")
  assert_eq(outs[1].to_string(), "\"b\"")
}

///|
test "eval: iterate .[]" {
  let arr = @lib.Arr([@lib.Num(1.0), @lib.Num(2.0), @lib.Num(3.0)])
  let outs = @lib.eval(@lib.Iterate, arr)
  assert_eq(outs.length(), 3)
  assert_eq(outs[2].to_string(), "3")
}

///|
test "eval: map with literal" {
  // map(.) on [1,2,3] is identity per element.
  // A fuller map(. * 2) needs arithmetic, which is P1.
  let arr = @lib.Arr([@lib.Num(1.0), @lib.Num(2.0)])
  let outs = @lib.eval(@lib.Map(@lib.Identity), arr)
  assert_eq(outs.length(), 1)
  assert_eq(outs[0].to_string(), "[1,2]")
}

///|
test "eval: select keeps truthy, drops falsy" {
  let good = @lib.Obj([@lib.ObjEntry::new("score", @lib.Num(95.0))])
  let bad = @lib.Obj([@lib.ObjEntry::new("score", @lib.Num(60.0))])
  // select(.) keeps any truthy input; objects are truthy in jq.
  assert_eq(@lib.eval(@lib.Select(@lib.Identity), good).length(), 1)
  // select on @lib.Null drops it.
  assert_eq(@lib.eval(@lib.Select(@lib.Identity), @lib.Null).length(), 0)
  let _ = bad
}

///|
test "eval: length and keys" {
  assert_eq(@lib.eval(@lib.Length, @lib.Str("hello"))[0].to_string(), "5")
  assert_eq(
    @lib.eval(@lib.Length, @lib.Arr([@lib.Num(1.0), @lib.Num(2.0)]))[0].to_string(),
    "2",
  )
  let o = @lib.Obj([
    @lib.ObjEntry::new("b", @lib.Num(2.0)),
    @lib.ObjEntry::new("a", @lib.Num(1.0)),
  ])
  assert_eq(@lib.eval(@lib.Keys, o)[0].to_string(), "[\"a\",\"b\"]")
}

///|
test "eval: comma produces two outputs" {
  let user = @lib.Obj([
    @lib.ObjEntry::new("name", @lib.Str("Yan")),
    @lib.ObjEntry::new("score", @lib.Num(95.0)),
  ])
  let outs = @lib.eval(
    @lib.Comma([@lib.Field("name"), @lib.Field("score")]),
    user,
  )
  assert_eq(outs.length(), 2)
  assert_eq(outs[0].to_string(), "\"Yan\"")
  assert_eq(outs[1].to_string(), "95")
}
