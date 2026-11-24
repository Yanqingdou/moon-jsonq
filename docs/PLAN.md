# moon-jsonq 项目计划

- 方向：官网 02 数据处理（工具库 / 数据处理 / AI 应用 / 开发者工具 四选一）
- 复现对象：`jq 1.7` 核心
- 周期：2026 年 8 月 – 2027 年 7 月（全年滚动）；本期 11 月赛季 – 次年 1 月为第二季度
- 目标：11 月先拿月度支持 150 + 350 = 500 元，12–1 月冲季度一等奖 12,000 元

## 1. 为什么选 jq

见 README。补充一点：官网评分 4 项各 25 分，这个项目正好对得上：

| 评分项 | 怎么拿 |
|---|---|
| 工程深度与实现强度 | 词法器 + 解析器 + AST + 求值器，不是调包拼装 |
| 技术贡献与攻关 | 填补 MoonBit JSON 处理缺口，解决实质性解析 / 求值难题 |
| 生态增量 | 别人能直接拿这个库用，CLI、Wasm 演示都能复用 |
| 开发与验证能力 | 单元 + 快照 + jq 兼容测试 + 基准，有回归检查 |

## 2. 功能分级

### P0 — 11 月必须有（✅ 2026-11-24 已完成并验证）
`.`、`.name`、`.a.b`、`.[0]`、`.[]`、`|`、`,`、`map(f)`、`select(f)`、`length`、`keys`、字面量。

### P1 — 原定 12 月，2026-11-24 已提前完成大部分
✅ 算术 `+ - * / %`、比较 `== != < <= > >=`、`//`、`if-then-else`、`sort`、`sort_by`、`unique`、`min`、`max`、`add`、`type`、`tostring`、`tonumber`、`not`、`empty`、`and`/`or`、对象/数组构造 `{k: f}` / `[f]`、完整递归下降解析器、stdin / 文件输入、`--pretty`、`--raw-output`、`--slurp`、`--null-input`、`-f`、`keys` 排序、错误信息（`Result[Filter, String]` + CLI 退出码 1/2）。
✅ 2026-11-24 当天又提前完成了原定 12 月的剩余项：`group_by`、`reduce`、字符串插值（见 P2 备注）。

### P2 — 原定 1 月，2026-11-24 已提前完成
✅ 切片 `.[a:b]`（负索引、省略上下界、越界截断，数组与字符串）、`split(sep)`、字符串插值 `"\(expr)"`（含插值对象键）、`--arg` / `--argjson` CLI 选项、`$变量` 与 `as $x` 绑定、`reduce`、`group_by(f)`、`to_entries` / `from_entries` / `with_entries(f)`。
验证：`moon test` 31/31，黄金测试 107 条 vs jq 1.7 全部通过（见 `tests/golden.py`），共 11 个提交（3 个基础 + 8 个功能提交）。

### 仍未做（P3 / 未来）
- `def` 自定义函数、`test`（正则）、`..` 递归下降、`getpath` / `paths`、模块导入。
- **更新赋值** `.a |= …` / `.a = …` / `.a += …` 等：尚未实现，写了会明确报错（不是静默错答案）。jq 的典型写法 `with_entries(.value += 10)` 因此也暂不支持，需改用 `with_entries({key: .key, value: (.value * 10)})`。实现时注意 jq 的语义细节：`+=` 右侧用原始输入求值（`{"a":1,"b":10} | .a += .b` 得 11），`|` 侧用路径旧值；缺失路径会被创建（`.missing |= . + 1` 得 1）；`|= empty` 会删除该键。
- Wasm 在线演示、性能优化、jq 官方测试集抽测 50 条。

### 明确不做
完整 jq 1.7 全量语法、流式超大文件、正则全兼容。写进 README 的“非目标”。

## 3. 架构

- `lib/json.mbt`：`JVal`（Null / Bool / Num(Double) / Str / Arr / Obj），`ObjEntry`，`field`、`index`、`iterate`、`length`、`keys`、`to_string`。
- `lib/query.mbt`：`Filter` AST，`eval` 返回 `Array[JVal]`（多输出语义）。
- `lib/eval.mbt`：纯函数求值器，无 I/O、无全局状态，可在 Wasm 跑。
- `lib/parser.mbt`：词法器 + 递归下降解析器（优先级已对 jq 1.7 实测校准），`parse_filter` 返回 `Result[Filter, String]`。
- `lib/json_io.mbt`：`@json.parse` <-> `JVal` 桥接已实现并验证（moon 0.1.20261119，`Json::number/string/…` 构造器 + `parse`/`stringify`）。
- `main/main.mbt`：`mq` CLI，`async fn main`（native-only，`@stdio`/`@fs`），支持 stdin、文件、`-r`、`--pretty`、`-s`、`-n`、`-f`、`--arg` / `--argjson`。

## 4. 时间表

### 11 月 24–30 日：冲月度验收
- 24 日：脚手架 + 工具链安装验证（`moon test` 15/15）+ P1 大部分提前完成（`moon test` 23/23，黄金测试 45 条 vs jq 1.7 全部通过，见 `tests/golden.py`）；当天又把 P1 剩余项与全部 P2 功能做完（`moon test` 31/31，黄金测试 107 条，11 个提交）
- 25–27 日：补边界测试（`group_by` / `test` / `def` / `reduce` 选做）、README + 演示 + 录屏
- 28 日：推公开 GitHub 仓库，持续提交
- 29 日：官网填飞书问卷申报
- 30 日：改审核意见缓冲

官网写 11 月赛季“报名与验收截止时间以官方通知为准”，赛观写 11 月 30 日，按 30 日赶最保险。

### 12 月：冲季度奖
P1/P2 功能已提前做完。剩余工作：Wasm 演示和基准对比，`def` / 更新赋值 / 正则 `test` 三选一补一个差异化功能，写新手教程、速查表、差异表。

### 1 月：冲季度评选
修 Bug、补边界测试、优化错误提示和性能，准备终评材料。

## 5. 测试计划

- 单元测试：每个过滤器 ≥3 个例子，`moon test`。
- 快照测试：`jq` 手册例子 100+ 条黄金测试。
- 兼容测试：抽 `jq` 官方测试集 50 条，对比输出，不一致列差异表。
- 性能测试：1 万行 JSON，`map` / `select` 耗时，和 Python 简单对比。

## 6. 风险

- MoonBit 文件 / stdin API 不熟：已解决。stdin/文件在该版本工具链里在实验性 async 包 `@stdio` / `@fs` 里，`async fn main` + `supported_targets = "-all+native"`，参考 core 里的 `filter` 测试程序。库本身保持纯函数、Wasm 兼容。
- 想做全量 jq：最大坑，P0 之外一律砍掉。
- 最后一天才申报：审核不通过还能改，要留时间，29 日就报。
- Beta 语言 API 变化：`@json.Number` 等 payload 形状可能变，`json_io.mbt` 不要瞎猜，先 `moon doc` 确认。
