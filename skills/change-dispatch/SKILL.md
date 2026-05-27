---
name: change-dispatch
description: Agent-agnostic task dispatcher. Reads backlog on main to find active changes, fetches the feature branch, reads tasks.md, picks up the next executable task group, implements it, and pushes to remote. Runnable by any agent (Codex / Claude Code / Cursor / cron / GitHub Actions / one-shot) — only requires git + shell + network.
---

# Change Auto-Dispatch

## Overview

自动扫描并领取就绪的 OpenSpec 任务组。**Runner 无关**——只要执行环境有 git 读写、shell 执行、网络访问三项能力即可运行。

**三层解耦：**

1. **Runner 层**（谁触发 dispatch 运行）：cron / `/loop Nm /change-dispatch` / Codex Automation / GitHub Actions / 人工一次性触发，任选其一
2. **Dispatch 逻辑层**（本 skill）：扫描 → 认领 → 实现 → push，不关心是谁在跑
3. **Executor 层**（每个任务组用什么执行模式）：tasks.md 任务组注释的 `执行模式:` tag 决定；dispatch 兼容旧 `执行工具:` tag

**Branch-Centric 模型：** 四件套和实现代码都在 feature branch 上。dispatch 通过 main 上的 backlog 索引找到活跃 change，fetch 对应 feature branch 读取 tasks.md，实现后直接 push。

**Announce at start:** "Running change-dispatch: scanning for ready task groups."

## Bash 命令规范

为兼容 Claude Code / Codex 等不同执行环境的权限与审批模型，所有 Bash 操作必须遵循：

1. **每条命令独立调用** — 不在一条 Bash 中用 `&&`、`||`、`;` 串联多条命令
2. **管道可以用** — 单条命令内的管道（如 `git branch -r | grep feat/`）是允许的
3. **并行无依赖时分开调用** — 多条独立命令应作为多个并行 Bash tool call 发送

示例：
```bash
# ❌ 错误：复合命令触发确认
git fetch origin && git branch -r | grep feat/ && gh pr list --state open

# ✅ 正确：拆分为独立调用
# Call 1: git fetch origin
# Call 2: git branch -r | grep feat/
# Call 3: gh pr list --state open --json number,headRefName,title,isDraft
```

## 类型 → 分支/提交前缀派生规则（单一事实源）

**不读 backlog frontmatter**，直接从 `change-id` 字符串前缀派生（零 I/O）：

| 判定顺序 | change-id 前缀 | type | branch 前缀 | commit type |
|---------|---------------|------|------------|-------------|
| 1 | `startsWith("hotfix-")` | hotfix | `hotfix/` | `fix` |
| 2 | `startsWith("chore-")` | chore | `chore/` | `chore` |
| 3 | `startsWith("fix-")`（严格 4 字符，排除 `fixture-*`） | bug | `fix/` | `fix` |
| 4 | 其余 | feature | `feat/` | `feat` |

`<branch-prefix>` 和 `<commit-type>` 全流程复用，禁止硬编码 `feat/`。**4 种类型走相同的 dispatch 路径**，无例外。

## Runner 配置（任选其一）

dispatch 对 runner 的要求**只有三项**：git 读写、shell 执行、网络访问。推荐频率：开发期 5 分钟，上线后 10-15 分钟。

### 方式 A — Claude Code `/loop`（推荐开发期）

```
/loop 5m /change-dispatch
```

优点：零配置；启动/停止方便；与 `/loop 15m /change-propose` + `/loop 10m /change-review` 三线并行协作自然。

### 方式 B — Codex Desktop Automation（推荐 24/7 无人值守）

```
Name:     change-dispatch
Schedule: every 5 minutes
Worktree: yes (加速并行任务组隔离)
Network:  allow github.com, allow registry.npmjs.org
Prompt:   使用 $change-dispatch 扫描并执行就绪的任务组
```

优点：headless；Codex 原生 worktree 隔离；不占 Claude Code 对话窗口。

### 方式 C — cron（服务器部署）

```cron
*/5 * * * * cd /path/to/repo && claude --dangerously-skip-permissions -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

或用 Codex CLI：

```cron
*/5 * * * * cd /path/to/repo && codex exec "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

优点：轻量；服务器 24/7；不依赖桌面客户端。

### 方式 D — GitHub Actions（零本地依赖）

```yaml
# .github/workflows/dispatch.yml
name: change-dispatch
on:
  schedule: [{cron: '*/5 * * * *'}]
  workflow_dispatch: {}
jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - run: pnpm install --frozen-lockfile
      - run: <你的 agent CLI> "/change-dispatch"
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }} # Claude CLI 使用
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}       # Codex CLI 使用
```

优点：无本地依赖；CI 环境天然隔离；日志进 Actions 面板。

### 方式 E — 一次性手动触发

```
/change-dispatch            # 在任意 Claude Code / Codex 对话里直接发
```

适用场景：排查 / 补跑 / 开发期试跑单轮。

### 并发与隔离

- **多 runner 同时跑 dispatch 安全**：Step 3 的 `status: executing` claim 提交作为分布式锁，其他 runner fetch 到 executing 会跳过
- **worktree 可选**：无 worktree 时同机串行（最后一次 commit 胜），有 worktree 时同机并行，跨机天然并行
- **跨 runner 混用**：Codex Automation + Claude Code `/loop` + 人工 `/change-dispatch` 可同时启用，不会互相踩脚

---

## Execution Flow

### Step 0 — 清理历史 Worktree

每次启动时先清理上一轮残留的 worktree，防止分支锁定：

```bash
git worktree prune
```

### Step 1 — 从 Backlog 索引活跃 Change

读取 main 上的 `product/backlog.md`，筛选满足以下条件的条目：

1. 阶段为 `proposed`（执行中的细粒度状态由 tasks.md YAML status 承担，不在 backlog 反映）
2. 有 `change-id` 列值（非空）

对每个满足条件的 change-id，按派生规则取 `<branch-prefix>`（`feat/` | `fix/` | `chore/` | `hotfix/`），拼出 feature branch 名 `<branch-prefix>/<change-id>`。

如果没有满足条件的条目，输出 "No active changes found." 并退出。

### Step 2 — Fetch 并读取 Feature Branch 上的 tasks.md

对每个活跃 change-id，fetch 远程分支：

```bash
git fetch origin <branch-prefix>/<change-id>
```

如果远程分支不存在，跳过。

读取 tasks.md：

```bash
git show origin/<branch-prefix>/<change-id>:openspec/changes/<change-id>/tasks.md
```

筛选条件：
1. YAML 头 `status` 为 `ready` 或 `executing`
2. `depends-on` 中列出的所有前置 change 在 main 的 backlog 中状态为 `done`

**额外步骤 — Stale `executing` 回收（防止 worker 卡死导致永久锁死）：**

对每个 `status: executing` 的任务组，读取最近一次 claim commit 的时间戳：

```bash
# 读取该任务组 claim commit（commit message 匹配 "claim <group> as executing"）的时间戳
last_claim_ts=$(git log origin/<branch-prefix>/<change-id> \
  --grep="claim .* as executing" --format="%ct" -1 \
  -- openspec/changes/<change-id>/tasks.md)

# 若距今 > 30 分钟 → 判定为 stale（worker 卡死 / OOM / runner 回收）
now=$(date +%s)
if (( now - last_claim_ts > 1800 )); then
  # 降级：status: executing → pending，写日志
  # commit message: "chore(<change-id>): reclaim stale executing <group>"
  # 并在 .logs/dispatch/<change-id>.md 写 WARN 级别"stale executing reclaimed"
fi
```

**语义**：30 分钟是启发式阈值，覆盖大多数任务组执行时间；超时判定为"前一轮 worker 失联"，降级后本轮或下一轮 runner 可重新领取。被 reclaim 的任务组原已完成的代码提交（如有部分 push）保留，`pending` 语义等同"从头再跑"——dispatch Step 5 会按幂等原则重做（覆盖文件而非增量）。若实际 worker 其实还活着，它后续 push 会被 `git pull --rebase` 解决或遇到 `status` 已变化而发现冲突——这是可接受的边界代价。

如果没有满足条件的 tasks.md，输出 "No ready tasks found." 并退出。

### Step 3 — 选择并认领任务组

在满足条件的 change 中，找到满足前置条件的 `status: pending` 任务组（按文件中出现顺序），筛选规则：

- 只领取 `执行模式: auto` 的任务组（兼容旧 `执行工具: Codex`；语义 = 需要自动化 runner，任意 agent 都可承接）
- 跳过 `执行模式: interactive` 的任务组（兼容旧 `执行工具: Claude Code`；语义 = 需人类在回路的交互式工作，留给 change-review 或手动）
- 检查任务组的约束（如"G0 完成后"），确认前置任务组已完成

> **tag 语义说明**：主路径使用 `执行模式: auto | interactive`。旧 `执行工具: Codex` 视为 `auto`，旧 `执行工具: Claude Code` 视为 `interactive`，仅为兼容历史 tasks.md / 归档记录。

**选定后立即认领（claim）：** 默认每个 runner 每轮只认领第一个可执行任务组。将该任务组的 `status: pending` 改为 `status: executing`；若 YAML 头为 `status: ready`，同时改为 `status: executing`。commit 并 push，作为分布式锁防止其他开发者重复领取。并行来自多个 runner/worktree 同时认领不同任务组，而不是单个 runner 抢占全部任务组。

```bash
# 切到 feature branch，拉取最新
git checkout <branch-prefix>/<change-id>
git pull origin <branch-prefix>/<change-id>

# 修改 tasks.md：
# - YAML status: ready → executing（若尚未进入 executing）
# - 当前任务组 status: pending → executing

git add openspec/changes/<change-id>/tasks.md
git commit -m "chore(<change-id>): claim <task-group-name> as executing

Change-ID: <change-id>"
git push origin <branch-prefix>/<change-id>
```

其他开发者下一轮 fetch 后看到 `executing` 会跳过，不会重复领取。

### Step 4 — 环境准备

```bash
# 安装依赖（分支已在 Step 3 checkout + pull）
pnpm install --frozen-lockfile
```

### Step 5 — 执行任务

1. 读取该 change 的 `design.md` 获取文件清单和技术方案
2. 读取代码库已有代码，理解项目模式
3. 按任务组的 checkbox 逐项实现
4. 每个新建文件包含 `@input/@output/@pos` 头注释
5. 每个新建目录包含 `_DIR.md`（change 新建的，main 上不存在——可直接写）
6. **`_DIR.md` 更新分流**（防止触碰 main 共享治理层）：
   - **change 独占 `_DIR.md`**（`git ls-tree origin/main -- <path>` 未命中，即本 change 新建目录的 `_DIR.md`）→ 新文件条目直接追加
   - **main 共享 `_DIR.md`**（命中 origin/main，如顶层 `src/_DIR.md` / `src/features/_DIR.md`）→ **本 step 跳过不动**，记录到 `.logs/dispatch/<change-id>.md` 的"`_DIR.md` 待办"段，由 `change-review` Step 6.1.5 在 main 上统一更新
7. Commit message 包含 `Change-ID: <change-id>`

**`_DIR.md` 待办日志格式：**

```markdown
### [YYYY-MM-DD HH:mm] Step 5 `_DIR.md` 待办 · change-dispatch

- **类型**: main-shared-_DIR.md 需更新
- **级别**: SKIP（本步跳过，归档时处理）
- **文件**: src/features/_DIR.md
- **待追加子项**: voice-entry.tsx（新建文件）
- **处理**: 推迟到 change-review Step 6.1.5 在 main 上更新
```

### 复盘检查点 — 实现与设计一致性

Step 5 执行完成后、验证前，执行以下交叉验证。发现偏离时写入 `.logs/dispatch/<change-id>.md`。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| D1 | 本轮新增/修改的文件 ⊆ design.md 当前任务组文件清单 **且不命中 Feature Branch 治理层禁改清单** | `git diff --name-only` 对比 design.md + 禁改清单（见 `core/AGENTS.md`）| 范围偏离 / 治理违规 |
| D2 | design.md 当前任务组声明的文件都被 touch 了 | design.md 清单 - git diff 文件集 = 遗漏 | 范围偏离 |
| D3 | tasks.md 当前任务组每个 checkbox 都有对应实现 | 逐项检查 checkbox 描述与实际代码变更 | 范围偏离 |
| D4 | 未修改其他任务组的独占文件 | `git diff --name-only` 不含其他 G 组的独占文件 | 范围偏离 |
| D5 | 新建 `.ts`/`.tsx` 文件有 `@input/@output/@pos` 头注释 | grep 新文件头部 | 方案偏离 |
| D6 | 新建目录有 `_DIR.md` | 检查新增目录列表 | 方案偏离 |
| D7 | **change 独占**目录的 `_DIR.md` 包含新文件条目（main 共享 `_DIR.md` 不在本检查范围，已由 Step 5 Item 6 推迟到 review 阶段）| 对比新建文件与**独占**目录 `_DIR.md` 内容（先用 `git ls-tree origin/main` 筛掉共享项）| 方案偏离 |
| D8 | commit message 包含 `Change-ID: <change-id>` | 检查 `git log` 最近提交 | 一致性偏离 |

**偏离处理：**
- **硬偏离**（D1 修改了完全不相关的文件、D4 侵入其他任务组）→ 写日志 → STOP
- **治理违规**（D1 命中禁改清单中的**治理层文件**：`product/backlog.md` / `design/roadmap.md` / `design/modules/*.md` / `openspec/specs/**.md` / `openspec/project.md` / `openspec/changes/_DIR.md`）→ 写日志 → **STOP 立即终止**（不做自动还原，会让 main 状态更乱）→ 提示 Luke 人工回滚
- **main 共享 `_DIR.md` 被修改**（非治理层违规，但本应由 Step 5 Item 6 推迟）→ 写日志 WARN → 自动 `git restore <共享 _DIR.md>` 撤销该文件的本轮修改 → 把"待追加子项"补写进待办日志 → 继续；避免直接 STOP 让整个 change 卡死
- **软偏离**（D2 遗漏一个文件、D5/D6/D7 缺头注释或 _DIR.md 条目）→ 写日志 → 自动补全后继续
- **数据偏离**（D8 commit message 格式）→ 写日志 → 下次 commit 修正

**D1 禁改清单判定（实现参考）：**

```bash
# 本轮 diff 文件集
diff_files=$(git diff --name-only HEAD~1)

# 治理层硬禁（命中 → STOP）：
#   ^product/backlog\.md$
#   ^design/roadmap\.md$
#   ^design/modules/M-[0-9]+-.*\.md$
#   ^openspec/specs/.*\.md$
#   ^openspec/project\.md$
#   ^openspec/changes/_DIR\.md$

# main 共享 _DIR.md 判定（命中 → WARN + restore，不 STOP）：
for f in $(echo "$diff_files" | grep '_DIR\.md$'); do
  if git ls-tree origin/main -- "$f" | grep -q .; then
    echo "WARN: $f is main-shared _DIR.md — reverting and deferring to review Step 6.1.5"
    git restore --source=HEAD~1 -- "$f"
    # 并把"待追加子项"写进 .logs/dispatch/<change-id>.md
  fi
done
```

---

### Step 6 — 范围校验

复盘检查点完成后，执行自动化范围校验：

1. 运行 `git diff --name-only` 获取本轮所有变更文件
2. 与 design.md 中当前任务组的文件清单对比
3. **超出清单的文件**：如果是合理的修复（测试基线、类型修正），记录 WARN 并说明原因；否则记录 STOP
4. **清单内遗漏的文件**：记录 WARN 并尝试补全

### Step 7 — 验证

```bash
pnpm test
pnpm lint
pnpm build
```

如果测试/lint/build 失败，尝试自动修复。若实现项已完成但验证仍失败，提交当前实现并在 commit message 中标注 `[NEEDS-FIX]`，写入 `.logs/dispatch/<change-id>.md`，交给 `change-review` 的本地 CI 修复循环处理；若实现本身未完成或代码处于不可提交状态，则 STOP，不更新任务组为 done。

### Step 8 — 更新状态、提交并推送

执行完成后：

1. 勾选 tasks.md 中对应任务组的所有 checkbox
2. 将该任务组注释中的 `status: executing` 改为 `status: done`
3. 如果该 change 所有自动化任务组（`执行模式: auto`，兼容旧 `执行工具: Codex`）都已 done：
   - 将 tasks.md YAML 头的 `status` 改为 `review`

```bash
git add -A
git commit -m "<commit-type>(<change-id>): complete <task-group-name>

Change-ID: <change-id>"
# <commit-type> 按派生规则：feature→feat, bug→fix, chore→chore

# 推送到远程（如果并行任务组已 push，先 rebase）
git pull --rebase origin <branch-prefix>/<change-id>
git push origin <branch-prefix>/<change-id>
```

---

## 状态协议

### tasks.md YAML 头

```yaml
---
status: draft | ready | executing | review | done
backlog-ref: B-NNN
depends-on: [change-id-1, change-id-2]
---
```

### 任务组级别状态

在每个任务组的 HTML 注释中：

```markdown
<!-- 执行模式: auto | 约束: 串行 | status: pending -->
```

status 值：`pending` → `executing` → `done`

### Change 级别状态流转

```
draft → ready → executing → review → done
  ↑        ↑         ↑          ↑        ↑
  │ interactive   dispatch   dispatch  review
  │   pre-flight   领取时     全部完成   归档时
  │
  交互式 agent 编写中（在 feature branch）
```

### Backlog 状态（main 上，由交互式 agent 维护）

```
idea → exploring → proposed ────────→ done
  ↑       ↑           ↑                  ↑
  │   prd-writer   change-propose    change-review
  新建              (四件套 ready)      (归档)

执行中细粒度由 tasks.md status 承担（dispatch 禁碰 main）
```

---

## 分支模型

```
main (稳定基线)
  ├── product/backlog.md       ← dispatch 扫描入口
  └── openspec/changes/_DIR.md ← 索引（含 branch/PR）

<branch-prefix>/<change-id> (feature branch, remote)
  ├── openspec/changes/<change-id>/  ← 四件套
  ├── src/...                        ← dispatch 实现的代码
  └── (所有任务组在此 branch 上线性提交)
```

所有自动化任务组（G0、G1-A、G1-B、G2）都在同一个 `<branch-prefix>/<change-id>` 上提交。G0 完成后直接 push，下一轮 dispatch fetch 到最新代码即可开始 G1。

---

## 并行安全

- 每个 dispatch 轮次在独立 worktree 中执行（若 runner 支持；不支持则同机串行）
- 同一 change 的串行任务组按顺序领取（G0 先于 G1）：dispatch 检查 G0 status 为 done 才领取 G1
- 同一 change 的并行任务组（G1-A, G1-B）可被同一轮次的不同 runner 领取
- 并行 push 冲突通过 `git pull --rebase` 解决
- 不同 change 完全隔离（不同 feature branch），可同时执行

## 问题日志

执行过程中遇到 STOP/WARN 级别时，**必须**追加记录到 `.logs/dispatch/<change-id>.md`。

### 级别定义

| 级别 | 含义 | 行为 |
|------|------|------|
| **STOP** | 无法继续，需人工处理 | 写日志 → 终止当前 change → 继续扫描下一个 |
| **WARN** | 已自动降级处理 | 写日志 → 继续执行 |
| **SKIP** | 条件不满足，正常跳过 | 不写日志 |

### STOP 场景

| 场景 | 触发条件 |
|------|---------|
| 分支 fetch 失败 | 远端分支不存在或网络错误 |
| tasks.md 读取失败 | 文件不存在或格式异常 |
| pnpm install 失败 | 依赖安装出错 |
| Rebase 冲突 | 并行 dispatch 写入同文件，无法自动解决 |
| Push 失败 | 推送被拒绝 |
| Claim 冲突 | 另一个 dispatch 已领取同一任务组 |
| 设计文档缺失 | design.md 不存在 |
| 复盘硬偏离 | D1/D4 修改了超出范围的文件 |
| 治理违规 | D1 命中 Feature Branch 治理层禁改清单（main 共享文件被 feature branch 改动）|

### WARN 场景

| 场景 | 触发条件 |
|------|---------|
| 测试/lint 失败后自动修复 | 修复成功但需记录 |
| 测试/lint/构建失败后交接 review | 实现项完成但验证仍失败，已提交 `[NEEDS-FIX]` |
| 分形文档自动补充 | 自动补了 `_DIR.md` 或头注释 |
| 复盘软偏离 | D2/D5/D6 遗漏，已自动补全 |

### 格式

```markdown
### [YYYY-MM-DD HH:mm] 任务组 · change-dispatch

- **类型**: 执行失败 / 测试失败 / lint 错误 / 构建错误 / Rebase 冲突 / 复盘偏离 / 其他
- **级别**: STOP / WARN
- **现象**: 一句话描述
- **上下文**: 根因或相关信息
- **处理**: 标记 [NEEDS-FIX] / 重试后通过 / 跳过 / STOP / 自动修正
```

**不记录**：正常通过的步骤、一次性网络超时、SKIP 级别跳过。

---

## 边界

- **不做**：审查、合并到 main、分形文档同步、verify、归档（这些是 change-review 的职责）
- **不做**：修改 main 上的任何文件（backlog、specs、project.md）
- **不碰**：`执行模式: interactive` 的任务组（兼容旧 `执行工具: Claude Code`）
