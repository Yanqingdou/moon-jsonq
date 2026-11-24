# moon-jsonq — MoonBit 版 jq（核心复现）

用 MoonBit 复现 `jq 1.7` 的核心：一个 JSON 查询库 + 命令行工具 `mq`。

> `jq` 是什么？JSON 的 `grep` / `sed`，在命令行里一行查 JSON 的工具：
> `echo '{"name":"Yan"}' | jq '.name'` → `"Yan"`

参加 **2026 MoonBit 国产基础软件生态开源大赛 · 11 月黑客松**（线上，数据处理方向）。
官网：https://moonbitlang.github.io/Hackathon2026/

## 一句话

```bash
# 真实 jq
echo '{"name":"Yan","score":95}' | jq '.name'
# "Yan"

# moon-jsonq 的 mq，一样能跑
echo '{"name":"Yan","score":95}' | mq '.name'
# "Yan"
```

## 现在能做什么（2026-11-24，可申报状态）

真正的命令行工具 `mq`，不是演示版：读 stdin / 文件，跑过滤器，逐行打印结果。

| 过滤器 | 例子 | 状态 |
|---|---|---|
| `.`、`.name`、`.a.b` | 字段访问 | ✅ |
| `.[0]`、`.[ -1]`、`.["k"]`、`.[expr]` | 数组索引，负数从后数 | ✅ |
| `.[]` | 遍历数组 / 对象值 | ✅ |
| `a \| b`、`a, b` | 管道、逗号，多输出 | ✅ |
| `a // b` | 空值 / 假值时用右边 | ✅ |
| `map(f)`、`select(f)` | 多输出按 jq 语义收集 / 过滤 | ✅ |
| `length`、`keys` | `keys` 按 jq 排序 | ✅ |
| `+ - * / %`、比较、`and` / `or` | `.a + 1`、`select(.score >= 90)`、`.[] * 2` | ✅ |
| `if-then-else-end`、`elif` | `if .a > 3 then "big" else "small" end` | ✅ |
| `sort`、`sort_by(f)`、`unique`、`min`、`max`、`add` | 按 jq 全序排序 | ✅ |
| `type`、`tostring`、`tonumber`、`not`、`empty` | 类型与转换 | ✅ |
| `[f]`、`{k: f, …}`、`{name}` | 数组 / 对象构造 | ✅ |
| 字面量 | `42`、`"hi"`、`true`、`null`、`[1,2]` | ✅ |

CLI 选项：`-r/--raw-output`、`--pretty`、`-c`、`-s/--slurp`、`-n/--null-input`、`-f/--from-file`、`-h`、`--version`。错误（坏过滤器 / 坏 JSON / 读不到文件）打印到 stderr，退出码 1；用法错误退出码 2。

## 已验证（2026-11-24，实测）

工具链：`moon 0.1.20261119`（官网下载，`cli.moonbitlang.com`）。

```bash
moon check   # 通过
moon test    # Total tests: 23, passed: 23, failed: 0
moon check --target native   # 通过（CLI 是 native-only，见下）
python3 tests/golden.py _build/native/debug/build/main/main.exe
# 45 cases, 0 failures — 对照真实 jq 1.7，见 tests/golden.py
# （另有 2 条已知 P2 跳过：切片 .[0:2]、split）

echo '{"name":"Yan","score":95}' | moon run --target native main -- '.name'
# "Yan"
```

注意：当前版本工具链已不再支持 `moon.mod.json` / `moon.pkg.json`，第一次跑 `moon fmt` 会自动迁移成 `moon.mod` / `moon.pkg`，这是正常的，不用手动改。

实测中学到的规则，写进代码里了：
- `pub` 类型是只读的，外部包不能构造；要让 `main` / 测试能构造 `JVal` / `Filter` / `ObjEntry`，必须用 `pub(all)`。
- `*_test.mbt` 是黑盒测试，跑在独立的测试包里，库里的符号要写 `@lib.Obj`、`@lib.eval` 这种带包前缀的形式，不能直接写 `Obj` / `eval`。
- `Array` 是引用类型，`push` 不用 `let mut`，只有重新赋值才需要 `mut`，否则 `moon check` 会报 unused_mut。
- MoonBit 里没有 `loop {}` 这种无限循环写法（那是函数式循环），无限循环用 `while true {}`；`break` 不能带值，要在循环后写返回值。
- `stdin` / 文件在该版本工具链里在实验性 async 包 `@stdio` / `@fs` 里，CLI 用 `async fn main` + `supported_targets = "-all+native"`，参考 core 里的 `filter` 测试程序；库本身保持纯函数、Wasm 兼容。
- `,` 的优先级：`a, b | c` 是 `(a, b) | c`，所以解析器里 `|` 在 `,` 之上；对象构造 `{k: v}` 里的 `,` 是分隔符不是逗号算子，值要用不含 `,` 的解析层级。
- `f + g` 是多输出的：`.[] + 10` 要对 `.[]` 的每个输出都算一次，`map(f)` 要收集 `f` 的全部输出（`select` 不输出的元素要丢掉）。

## 快速开始

```bash
# 1. 安装 MoonBit 工具链（按官网 https://www.moonbitlang.com/download/）
#    官方命令：curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
#    先把脚本下到本地看一眼再跑更稳妥；如果在 root 容器里 tar 报
#    "Cannot change ownership to uid 1001"，改用
#    tar --no-same-owner -xf moonbit-*.tar.gz 解包，再 chmod +x ~/.moon/bin/*
# 2. 检查
moon version

# 3. 跑测试（库的核心逻辑）
moon test

# 4. 跑真正的 CLI（native，stdin 需要 async 包）
echo '{"name":"Yan"}' | moon run --target native main -- '.name'
# "Yan"

# 5. 构建原生可执行文件 mq
moon build --target native main
# _build/native/debug/build/main/main.exe
echo '{"name":"Yan"}' | _build/native/debug/build/main/main.exe -r '.name'
# Yan
```

## 项目结构

```
moon-jsonq/
├── moon.mod            # 模块：Yanqingdou/moon-jsonq 0.1.0（由 moon.mod.json 迁移而来）
├── lib/
│   ├── moon.pkg        # lib 包
│   ├── json.mbt        # JVal 类型、字段/索引/长度/打印、jq 全序比较
│   ├── query.mbt       # Filter AST（含算术/比较/if/构造/sort 等）
│   ├── eval.mbt        # 求值器 eval / eval_one（多输出语义）
│   ├── parser.mbt      # 词法器 + 递归下降解析器
│   ├── json_io.mbt     # @json.parse <-> JVal 桥接
│   ├── json_test.mbt
│   ├── eval_test.mbt
│   ├── parser_test.mbt
│   └── review_test.mbt # 月度验收新增测试
├── main/
│   ├── moon.pkg        # 可执行包，native-only，import lib + @env/@stdio/@fs
│   └── main.mbt        # mq CLI（async fn main）
├── tests/
│   └── golden.py       # 对照真实 jq 1.7 的黄金测试（45 条）
├── examples/
│   ├── 01-basic.md     # 15 个例子（jq 对照，已验证）
│   └── data.json       # 演示数据
├── docs/
│   ├── PLAN.md         # 完整项目计划、时间表、评分对照
│   └── SUBMIT.md       # 申报清单
└── LICENSE             # MIT
```

## 例子

`examples/01-basic.md` 里有 15 条，每条都写了真实 `jq` 命令和期望输出，`tests/golden.py` 已对照验证：

```bash
echo '{"users":[{"name":"a"},{"name":"b"}]}' | jq '.users[].name'
# "a"
# "b"

echo '[1,2,3]' | jq '.[]'
# 1
# 2
# 3
```

## 未完成，要诚实写出来

1. **`def` / `reduce` / `group_by` / `test`（正则）还没有。** 写了会明确报 `Err`（“not supported yet (P2)”），不会静默给错答案。见 `docs/PLAN.md`。
2. **切片 `.[a:b]`、字符串插值 `"\(…)"`、字符串函数（`split` 等）还没有。** 同样明确报错，见黄金测试里的 SKIP。
3. **`$变量`、模块导入、`--arg` / `--argjson` 还没有。** P2。
4. **没有 Wasm 在线演示。** P2（12–1 月）。
5. **数字格式：** 大整数 / 科学计数法按 `Double` 打印，和 jq 在极端值上可能有差异；`NaN` / `Infinity` 没有 JSON 写法，按 `@json` 的约定处理。

## 为什么复现 jq，而不是做个新工具

- 定位明确：MoonBit 已有 `bobzhang/moonjq`（语言作者的完整 jq 实现，MoonBash 在用）和 JSONPath 库，本项目不声称“首创”；它是独立从零写的实现，侧重开箱即用的 `mq` 命令行和对照真实 jq 行为的黄金测试。
- 有标准答案：`jq` 手册有几百个例子，测试不用自己编。
- 技术深度够：要写词法器、解析器、AST、求值器，不是拼几个库，符合官网“工程深度 / 技术贡献”两项 25 分的要求。
- MoonBit 有优势：原生 JSON 类型 + 模式匹配，写解析器和求值器正好对口。

## 许可证与来源

- 本项目代码为原创，MIT 协议。
- 复现对象：`jq 1.7`（https://jqlang.org/），参考其手册和测试用例，代码不复制 `jq` 的 C 源码。
- MoonBit 语言与工具链：https://www.moonbitlang.com/

## 申报

见 `docs/SUBMIT.md`：官网填飞书问卷 → 加交流群并把群昵称改成 GitHub ID → 公开仓库持续提交。
