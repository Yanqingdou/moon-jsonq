# 申报清单 — 2026 MoonBit 黑客松 11 月赛季

官网：https://moonbitlang.github.io/Hackathon2026/

## 申报前（本机）

- [ ] 安装 MoonBit 工具链：https://www.moonbitlang.com/download/
- [ ] `moon version` 能跑通
- [x] `moon check` 通过（`moon check --target native`，CLI 是 native-only）
- [x] `moon test` 通过（23/23，2026-11-24）
- [x] 黄金测试通过：`python3 tests/golden.py` 45 条对照 jq 1.7，0 失败
- [x] 真实 CLI 能跑：`echo '{"name":"Yan"}' | moon run --target native main -- '.name'` → `"Yan"`；原生 binary：`moon build --target native main`
- [x] 把 `moon.mod` 里的 `yan/moon-jsonq` 改成 `Yanqingdou/moon-jsonq`，`main/moon.pkg` 里的 import 同步改名（2026-11-24 已改，待重跑验证）
- [ ] 把 `README.md` 里的仓库链接改成你的真实仓库地址

## 推到 GitHub

```bash
cd moon-jsonq
git init
git add .
git commit -m "moon-jsonq 0.2.0: real mq CLI — stdin/file, full parser, jq golden tests"
git branch -M main
git remote add origin https://github.com/Yanqingdou/moon-jsonq.git
git push -u origin main
```

- [ ] 仓库是 **公开** 的，不是私有
- [ ] README 在仓库首页能正常显示
- [ ] 不要最后一天一次性 push，要保留持续提交记录（官网验收要求）

## 官网申报

1. 打开 https://moonbitlang.github.io/Hackathon2026/
2. 点「点击报名」或「项目申报」，填飞书报名问卷
   - 参赛信息、公开仓库链接、一页项目说明
   - 项目方向选：数据处理
   - 项目简介可直接用 README 的“一句话”那段
3. 加入赛事交流群（官网 / 问卷里有入口）
4. **把群昵称改成自己的 GitHub ID，否则影响奖金发放**
5. 等资格审核，通过后有 150 元启动支持；开发完成并通过验收后再有 350 元

## 验收对照（官网 6 条）

- [ ] MoonBit 为主：核心全部 MoonBit
- [ ] 仓库公开：持续提交记录
- [ ] 能够运行：README 有 `moon run` / `moon test` / CLI 用法，每个例子可复制跑通
- [ ] 工作有效：本期新增工作，不是旧项目改名
- [ ] 开源合规：MIT 协议，README 写明复现 jq、参考手册、代码原创
- [ ] AI 可解释：能讲清词法、AST、求值器设计，不要只说“AI 写的”

## 截止

- 11 月赛季报名与验收：官网写“以官方通知为准”，赛观写 11 月 30 日。按 11 月 30 日赶，11 月 29 日申报最保险。
