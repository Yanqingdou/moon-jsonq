# 例子 — moon-jsonq vs 真实 jq

每条都写了真实 `jq` 命令和期望输出，方便对照。
`mq` 是本项目的 CLI，2026-11-24 已验证：下面每条用 `mq` 跑和 `jq -c` 结果一致（`tests/golden.py`，45 条）。

## 1. 取字段

```bash
echo '{"name":"Yan","score":95}' | jq '.name'
# "Yan"
```

## 2. 取嵌套字段

```bash
echo '{"a":{"b":42}}' | jq '.a.b'
# 42
```

## 3. 数组索引

```bash
echo '[10,20,30]' | jq '.[0]'
# 10
echo '[10,20,30]' | jq '.[-1]'
# 30
```

## 4. 遍历

```bash
echo '[1,2,3]' | jq '.[]'
# 1
# 2
# 3
```

## 5. 管道

```bash
echo '{"users":[{"name":"a"},{"name":"b"}]}' | jq '.users[].name'
# "a"
# "b"
```

## 6. 逗号（多输出）

```bash
echo '{"name":"Yan","score":95}' | jq '.name, .score'
# "Yan"
# 95
```

## 7. length

```bash
echo '"hello"' | jq 'length'
# 5
echo '[1,2,3]' | jq 'length'
# 3
```

## 8. keys

```bash
echo '{"b":2,"a":1}' | jq 'keys'
# ["a", "b"]  — mq 同样会排序，见 lib/json.mbt
```

## 9. select

```bash
echo '[{"name":"a","score":95},{"name":"b","score":60}]' | jq '.[] | select(.score >= 90)'
# {"name": "a", "score": 95}
```

## 10. map

```bash
echo '[1,2,3]' | jq 'map(. * 2)'
# [2, 4, 6]
```

## 11. 算术与比较

```bash
echo '{"a":6,"b":2}' | jq '.a + .b, .a * .b, .a > .b'
# 8
# 12
# true
```

## 12. // 与 if

```bash
echo '{"a":null}' | jq '.a // "x"'
# "x"
echo '{"a":5}' | jq 'if .a > 3 then "big" else "small" end'
# "big"
```

## 13. sort / unique / add

```bash
echo '[3,1,2,2]' | jq 'sort, unique, add'
# [1,2,2,3]
# [1,2,3]
# 8
```

## 14. 对象构造

```bash
echo '{"a":1}' | jq '{b: .a, c: 2}'
# {"b":1,"c":2}
```

## 15. 原生 mq 用法

```bash
# 构建原生可执行文件
moon build --target native main
# _build/native/debug/build/main/main.exe

echo '{"name":"Yan"}' | mq '.name'          # "Yan"
echo '{"name":"Yan"}' | mq -r '.name'       # Yan（不带引号）
mq '.users[].name' examples/data.json
echo '1
2
3' | mq -s 'add'                             # 6
mq -n '[1,2,3] | map(. * 2)'                # [2,4,6]
```
