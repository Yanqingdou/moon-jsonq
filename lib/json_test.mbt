///|
/// Tests for `json.mbt` — JVal helpers and printing.
/// Run with: `moon test`
/// These tests use only `JVal` literals, so they do not depend
/// on `@json.parse` or on file/stdin I/O.
test "field: present and missing" {
  let user = @lib.Obj([
    @lib.ObjEntry::new("name", @lib.Str("Yan")),
    @lib.ObjEntry::new("score", @lib.Num(95.0)),
  ])
  assert_eq(user.field("name").to_string(), "\"Yan\"")
  // jq: `.missing` on an object is `null`, not an error.
  assert_eq(user.field("missing").to_string(), "null")
  // `.name` on a number is also `null` in our MVP.
  assert_eq(@lib.Num(1.0).field("name").to_string(), "null")
}

///|
test "index: positive, negative, out of range" {
  let arr = @lib.Arr([@lib.Num(1.0), @lib.Num(2.0), @lib.Num(3.0)])
  assert_eq(arr.index(0).to_string(), "1")
  assert_eq(arr.index(-1).to_string(), "3")
  assert_eq(arr.index(99).to_string(), "null")
}

///|
test "length: string, array, object, null" {
  assert_eq(@lib.Str("hello").length().to_string(), "5")
  assert_eq(@lib.Arr([@lib.Num(1.0), @lib.Num(2.0)]).length().to_string(), "2")
  assert_eq(@lib.Null.length().to_string(), "0")
}

///|
test "to_string: object and array" {
  let v = @lib.Obj([
    @lib.ObjEntry::new("name", @lib.Str("Yan")),
    @lib.ObjEntry::new("score", @lib.Num(95.0)),
  ])
  assert_eq(v.to_string(), "{\"name\":\"Yan\",\"score\":95}")
  let a = @lib.Arr([@lib.Num(1.0), @lib.Num(2.0), @lib.Num(3.0)])
  assert_eq(a.to_string(), "[1,2,3]")
}

///|
test "is_truthy: jq rules" {
  assert_eq(@lib.Null.is_truthy(), false)
  assert_eq(@lib.Bool(false).is_truthy(), false)
  assert_eq(@lib.Bool(true).is_truthy(), true)
  // In jq, 0 and "" are truthy. Our MVP matches jq here.
  assert_eq(@lib.Num(0.0).is_truthy(), true)
  assert_eq(@lib.Str("").is_truthy(), true)
}
