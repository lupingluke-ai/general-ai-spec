---
name: change-dispatch
description: Agent-agnostic task dispatcher. Reads backlog on main to find active changes, atomically claims one task group from an isolated worker branch, implements it, and pushes it to the shared feature branch. Runnable by Codex, Claude Code, cron, GitHub Actions, or one-shot runners with the project toolchain and credentials installed.
---

# Change Auto-Dispatch

## Overview

自动扫描并领取就绪的 OpenSpec 任务组。**Runner 无关**表示协议不绑定某一种 agent；执行环境仍必须具备项目声明的 Node/pnpm/技术栈工具链、agent CLI、模型凭据、GitHub 写权限和网络访问。

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

## 类型 → 分支/提交前缀映射规则

type 的事实源是 `product/backlog.md` 的**类型列**（dispatch Step 1 扫描 backlog 时同一行直接读到，无需从 change-id 字符串反解析）。由 type 映射 branch / commit 前缀：

| type | branch 前缀 | commit type |
|------|------------|-------------|
| feature | `feat/` | `feat` |
| bug | `fix/` | `fix` |
| chore | `chore/` | `chore` |
| hotfix | `hotfix/` | `fix` |

`<branch-prefix>` 和 `<commit-type>` 全流程复用，禁止硬编码 `feat/`。**4 种类型走相同的 dispatch 路径**，无例外。

> change-id 的命名前缀（`fix-` / `chore-` / `hotfix-`）由 `prd-writer` 按 type 生成、`change-propose` 校验，仅作语义标签；dispatch / review 不解析它。

## Runner 配置（任选其一）

dispatch 对 runner 的要求包括：git、shell、项目技术栈工具链、依赖安装能力、可调用本 skill 的 agent CLI、模型凭据、GitHub 写权限和网络。触发频率由项目自行配置，需保证不会长期占用分支或压垮 CI。

### 方式 A — Claude Code `/loop`（推荐开发期）

```
/loop <interval> /change-dispatch
```

优点：零配置；启动/停止方便；可与 `change-propose` / `change-review` 的人工或定时触发协作。

### 方式 B — Codex Desktop Automation（推荐 24/7 无人值守）

```
Name:     change-dispatch
Schedule: <interval>
Worktree: yes (必须保持 detached；skill 自建唯一 worker branch)
Network:  allow github.com, allow registry.npmjs.org
Prompt:   使用 $change-dispatch 扫描并执行就绪的任务组
```

优点：headless；Codex 原生 worktree 隔离；不占 Claude Code 对话窗口。

### 方式 C — cron（服务器部署）

```cron
<cron> cd /path/to/repo && claude --dangerously-skip-permissions -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

或用 Codex CLI：

```cron
<cron> cd /path/to/repo && codex exec "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

优点：轻量；服务器 24/7；不依赖桌面客户端。

### 方式 D — GitHub Actions（零本地依赖）

init.sh 已生成可直接启用的 `.github/workflows/dispatch.yml`：固定安装 Node/pnpm 与指定版本 Codex CLI，使用完整 Git history，配置 Git author，并声明 `contents` / `pull-requests` 写权限。仓库必须配置：

- `OPENAI_API_KEY`
- `DISPATCH_GITHUB_TOKEN`：fine-grained PAT 或 GitHub App token，拥有 contents/pull requests write；不能使用默认 `GITHUB_TOKEN`，因为自动 push 必须继续触发 PR/CI workflows

workflow 使用 GitHub-hosted ephemeral runner 执行 `codex exec --ephemeral --dangerously-bypass-approvals-and-sandbox`；该高权限参数只允许在这种一次性隔离 runner 中使用。完整事实源是 `templates/github-workflows/dispatch.yml`。

### 方式 E — 一次性手动触发

```
/change-dispatch            # 在任意 Claude Code / Codex 对话里直接发
```

适用场景：排查 / 补跑 / 开发期试跑单轮。

### 并发与隔离

- **所有 runner 都使用唯一 worker branch**：不得把共享 feature branch 同时 checkout 到多个 worktree。
- **claim 的锁语义来自 fast-forward push**：worker 从同一个远端 SHA 出发，只有第一个 `HEAD:<feature-branch>` push 能成功；push 被拒者必须重新 fetch、重新选组，绝不能把失败的 claim rebase 后继续执行。
- **同机并发使用 detached worktree + 唯一 worker branch**：

```bash
# 在认领前创建隔离 worktree；WORKER_KEY 必须只含 ASCII 字母、数字、点、横线
git fetch origin <branch-prefix>/<change-id>
git worktree add --detach .worktrees/<worker-key> origin/<branch-prefix>/<change-id>
git -C .worktrees/<worker-key> switch -c worker/<change-id>/<group-id>/<claim-id>
# ... Step 3-8 都在该 worktree 内执行，push 使用 HEAD:<feature-branch> ...
# 完成或释放 claim 后，只清理自己的 worktree / worker branch
cd <repo-root>
git worktree remove .worktrees/<worker-key>
git branch -D worker/<change-id>/<group-id>/<claim-id>
```

> Codex Desktop Automation 自带 worktree 时，也必须保持 detached/唯一 worker branch 语义；不能让桌面 worktree直接 checkout 共享 feature branch。`.worktrees/` 已由 init.sh 写入 `.gitignore`。
- **跨 runner 混用**：只有全部 runner 都遵守相同的 fast-forward claim 协议时才安全。

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

对每个满足条件的条目，读取同一行的**类型列**得到 type，按映射规则取 `<branch-prefix>`（`feat/` | `fix/` | `chore/` | `hotfix/`），拼出 feature branch 名 `<branch-prefix>/<change-id>`。

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

在候选 worktree 创建后运行 `node scripts/validate-change.mjs --change <change-id> --type <type> --phase dispatch`；结构或状态校验失败时不 claim，写 STOP 日志。

筛选条件：
1. YAML 头 `status` 为 `ready` 或 `executing`
2. `depends-on` 中列出的所有前置 change 在 main 的 backlog 中状态为 `done`

**额外步骤 — Stale `executing` 回收（防止 worker 卡死导致永久锁死）：**

对每个 `status: executing` 的任务组，从该任务组注释读取 `claim-id`，再读取该组、该 claim 的最近 heartbeat/claim commit 时间戳：

```bash
# group-id 与 claim-id 都必须精确匹配，禁止使用跨任务组的宽泛 grep
last_claim_ts=$(git log origin/<branch-prefix>/<change-id> \
  --grep="heartbeat <group-id> <claim-id>" --format="%ct" -1 \
  -- openspec/changes/<change-id>/tasks.md)

# 无 heartbeat 时回退到该组的精确 claim commit
# git log --grep="claim <group-id> as executing \[<claim-id>\]" ...
# 两者都不存在 → STOP；不得把空时间戳按 epoch 处理

# 阈值读取 openspec/config.yaml automation.dispatch.stale-after-minutes（默认 150）
# worker 每 20 分钟更新一次 heartbeat；150 分钟覆盖最长 120 分钟任务及抖动
now=$(date +%s)
if (( now - last_claim_ts > stale_after_seconds )); then
  # 降级：status: executing → pending，清空 claim 字段，写日志
  # commit message: "chore(<change-id>): reclaim stale executing <group>"
  # 并在 .logs/dispatch/<change-id>.md 写 WARN 级别"stale executing reclaimed"
fi
```

**语义**：回收阈值必须大于配置允许的最长任务时长，并由 heartbeat 续租。reclaim 前再次 fetch 并确认远端仍是同一个 `claim-id`；旧 worker 后续 push 时必须检查 claim-id，发现所有权变化就停止，禁止继续 rebase/push。

**额外步骤 — 收敛检查（幂等，防止并行完成竞态导致 change 卡死）：**

对每个 YAML `status: executing` 的 change，若其**所有** `执行模式: auto` 任务组的 status 均已为 `done`，说明执行已完成但 YAML 状态未收敛（典型原因：多个 runner 并行完成各自任务组时，各自基于陈旧快照判断"未全完成"，都没有把 status 推进到 review）。此时：

在 `origin/<feature-branch>` 上创建 detached worktree + 唯一 `worker/<change-id>/converge/<claim-id>`，再次确认远端快照后只修改 tasks.md，commit 并以 `HEAD:refs/heads/<feature-branch>` fast-forward push。push 被拒说明状态已前进，丢弃本地 converge commit并留给下一轮；禁止 checkout 共享 feature branch。

收敛后该 change 跳过本轮领取（无 pending 任务组），继续扫描下一个 change。**此检查电平触发、重复执行无害**——即使某轮 runner 崩溃漏推状态，任意后续轮次都会把它补齐。

如果没有满足条件的 tasks.md，输出 "No ready tasks found." 并退出。

### Step 3 — 选择并认领任务组

在满足条件的 change 中，找到满足前置条件的 `status: pending` 任务组（按文件中出现顺序），筛选规则：

- 只领取 `执行模式: auto` 的任务组（兼容旧 `执行工具: Codex`；语义 = 需要自动化 runner，任意 agent 都可承接）
- 跳过 `执行模式: interactive` 的任务组（兼容旧 `执行工具: Claude Code`；语义 = 需人类在回路的交互式工作，留给 change-review 或手动）
- 检查任务组的约束（如"G0 完成后"），确认前置任务组已完成

> **tag 语义说明**：主路径使用 `执行模式: auto | interactive`。旧 `执行工具: Codex` 视为 `auto`，旧 `执行工具: Claude Code` 视为 `interactive`，仅为兼容历史 tasks.md / 归档记录。

**选定后立即认领（claim）：** 默认每个 runner 每轮只认领第一个可执行任务组。claim 必须在唯一 worker branch/worktree 内构造，并通过对共享 feature branch 的 fast-forward push 获取所有权。

```bash
# 根工作区保持 main；从远端 tip 建唯一 worker worktree/branch
git fetch origin <branch-prefix>/<change-id>
git worktree add --detach .worktrees/<worker-key> origin/<branch-prefix>/<change-id>
git -C .worktrees/<worker-key> switch -c worker/<change-id>/<group-id>/<claim-id>

# 修改 tasks.md：
# - YAML status: ready → executing（若尚未进入 executing）
# - 当前任务组 status: pending → executing
# - 写入 claim-id / claimed-at / heartbeat-at

git add openspec/changes/<change-id>/tasks.md
git commit -m "chore(<change-id>): claim <group-id> as executing [<claim-id>]

Change-ID: <change-id>"
git push origin HEAD:refs/heads/<branch-prefix>/<change-id>

# 记录本轮实现 diff 的基线。后续 D1/D4/范围校验只比较 claim 之后的实现变更，
# 避免把 claim commit 对 tasks.md 的状态修改误判为范围外实现。
DISPATCH_BASE_SHA=$(git rev-parse HEAD)
```

push 成功才算取得 claim。push 被拒时，不得开始实现：fetch 远端、丢弃本地失败 claim、重新读取 tasks.md 并选择下一个 pending 组。最多重选 3 次；仍竞争失败则正常退出，等待下一轮。

**Claim 释放规则：** claim 之后、任务组完成之前触发 STOP 时，先 fetch 并验证远端 `claim-id` 仍属于本 worker，再将该组 `executing → pending`、清空 claim 字段，commit 后通过 `HEAD:<feature-branch>` fast-forward push。释放失败由 150 分钟 stale + heartbeat 协议兜底。释放动作只改 tasks.md；已推送的部分实现代码保留供下一轮幂等恢复。

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
   - **main 共享 `_DIR.md`**（命中 origin/main，如顶层 `src/_DIR.md` / `src/features/_DIR.md`）→ **本 step 跳过不动**，把待办追加到 **`openspec/changes/<change-id>/pending-sync.md`**（change 独占文件，随 branch 合并进 main），由 `change-review` 归档阶段（Step 5.0 / 6.1.5）在 main 上统一消费
7. 实现完成后由 Step 7.5 创建独立实现 commit，message 包含 `Change-ID: <change-id>`

**`pending-sync.md` 待办格式（不存在则创建，追加写入）：**

```markdown
# Pending main-side sync — <change-id>

<!-- main 共享 _DIR.md 的推迟更新清单。由 dispatch / review 在 feature branch 上追加，
     change-review 归档阶段在 main 上逐条执行并勾选。归档时随 change 目录移入 archive/。 -->

- [ ] src/features/_DIR.md — 追加条目: voice-entry.tsx（新建文件）· 记录方: dispatch · YYYY-MM-DD
```

> **为什么不写 `.logs/`**：日志是观测通道，不是数据通道。待办放在 change 目录内，天然随 branch → merge → main → archive 流转，review 在 main 上打开 `openspec/changes/<change-id>/pending-sync.md` 即可消费，无跨目录信箱错位风险。

### 复盘检查点 — 实现与设计一致性

Step 5 执行完成后、验证前，执行以下交叉验证。发现偏离时写入 `.logs/dispatch/<change-id>.md`。

**系统治理产物例外：** `openspec/changes/<change-id>/pending-sync.md` 是 Step 5 为推迟 main 共享 `_DIR.md` 更新而生成的 change-owned 数据通道，不属于实现文件清单。D1 / D4 / Step 6 做范围差集前必须先排除该文件，但仍要校验其中每条待办都能追溯到 design.md 声明的受影响目录或文件。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| D1 | 本轮新增/修改的实现文件（排除上述 `pending-sync.md`）⊆ design.md 当前任务组文件清单 **且不命中 Feature Branch 治理层禁改清单** | `git diff --name-only` 排除系统治理产物后，对比 design.md + 禁改清单（见 `core/AGENTS.md`）| 范围偏离 / 治理违规 |
| D2 | design.md 当前任务组声明的文件都被 touch 了 | design.md 清单 - git diff 文件集 = 遗漏 | 范围偏离 |
| D3 | tasks.md 当前任务组每个 checkbox 都有对应实现 | 逐项检查 checkbox 描述与实际代码变更 | 范围偏离 |
| D4 | 未修改其他任务组的独占文件 | `git diff --name-only` 不含其他 G 组的独占文件 | 范围偏离 |
| D5 | 新建 `.ts`/`.tsx` 文件有 `@input/@output/@pos` 头注释 | grep 新文件头部 | 方案偏离 |
| D6 | 新建目录有 `_DIR.md` | 检查新增目录列表 | 方案偏离 |
| D7 | **change 独占**目录的 `_DIR.md` 包含新文件条目（main 共享 `_DIR.md` 不在本检查范围，已由 Step 5 Item 6 推迟到 review 阶段）| 对比新建文件与**独占**目录 `_DIR.md` 内容（先用 `git ls-tree origin/main` 筛掉共享项）| 方案偏离 |
| D8 | commit message 包含 `Change-ID: <change-id>` | 检查 `git log` 最近提交 | 一致性偏离 |

**偏离处理：**
- **硬偏离**（D1 修改了完全不相关的文件、D4 侵入其他任务组）→ 写日志 → STOP
- **治理违规**（D1 命中禁改清单中的**治理层文件**：`product/backlog.md` / `design/roadmap.md` / `design/modules/*.md` / `openspec/specs/**.md` / `openspec/project.md` / `openspec/changes/_DIR.md`）→ 写日志 → **STOP 立即终止**（不做自动还原，会让 main 状态更乱）→ 提示用户人工回滚
- **main 共享 `_DIR.md` 被修改**（非治理层违规，但本应由 Step 5 Item 6 推迟）→ 写日志 WARN → 自动 `git restore <共享 _DIR.md>` 撤销该文件的本轮修改 → 把"待追加子项"补写进 `openspec/changes/<change-id>/pending-sync.md` → 继续；避免直接 STOP 让整个 change 卡死
- **软偏离**（D2 遗漏一个文件、D5/D6/D7 缺头注释或 _DIR.md 条目）→ 写日志 → 自动补全后继续
- **数据偏离**（D8 commit message 格式）→ 写日志 → 下次 commit 修正

**D1 禁改清单判定（实现参考）：**

```bash
# 本轮实现 diff 文件集（claim commit 之后的变更）
diff_files=$(git diff --name-only "$DISPATCH_BASE_SHA")

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
    git restore --source="$DISPATCH_BASE_SHA" -- "$f"
    # 并把"待追加子项"写进 openspec/changes/<change-id>/pending-sync.md
  fi
done
```

---

### Step 6 — 范围校验

复盘检查点完成后，执行自动化范围校验：

1. 运行 `git diff --name-only "$DISPATCH_BASE_SHA"` 获取本轮所有实现变更文件
2. 排除 `openspec/changes/<change-id>/pending-sync.md`，并单独验证其中待办可追溯到 design.md
3. 与 design.md 中当前任务组的文件清单对比
4. **超出清单的文件**：如果是合理的修复（测试基线、类型修正），记录 WARN 并说明原因；否则记录 STOP
5. **清单内遗漏的文件**：记录 WARN 并尝试补全

### Step 7 — 验证

```bash
pnpm test
pnpm lint
pnpm build
```

如果测试/lint/build 失败，尝试自动修复。若实现项已完成但验证仍失败，提交当前实现并在 commit message 中标注 `[NEEDS-FIX]`，写入 `.logs/dispatch/<change-id>.md`，交给 `change-review` 的本地 CI 修复循环处理；若实现本身未完成或代码处于不可提交状态，则 STOP，不更新任务组为 done。

### Step 7.5 — 提交实现并清洁工作区

从 design.md 当前任务组文件清单生成显式暂存列表，只暂存：该组实现文件、change 独占 `_DIR.md`、`pending-sync.md`，以及本轮确实写入的 `.logs/dispatch/<change-id>.md`。禁止 `git add -A`。

```bash
git add -- <design-declared-files-and-existing-change-owned-_DIRs...>
# 下列可选路径仅在本轮实际存在/修改时分别执行 git add：
# openspec/changes/<change-id>/pending-sync.md
# .logs/dispatch/<change-id>.md
git commit -m "<commit-type>(<change-id>): implement <group-id>

Change-ID: <change-id>"
git status --porcelain
```

不存在的可选文件不要传给 `git add`。`git status --porcelain` 非空即 STOP：先识别并处理未暂存文件，不得带着脏工作区进入 rebase。

### Step 8 — 更新状态、提交并推送

**硬规则：先 rebase 拉齐并行状态，再做"全 done"判定。** 判定必须基于 rebase 后的 tasks.md，否则并行 runner 各自基于陈旧快照判断"未全完成"，会导致所有组都 done 但 YAML status 永远停在 executing（由收敛检查兜底，但不应依赖兜底）。

执行完成后（实现代码已在 Step 7.5 提交，工作区已验证干净）：

```bash
# 1. 先拉齐并行任务组的最新状态
git fetch origin <branch-prefix>/<change-id>
git rebase origin/<branch-prefix>/<change-id>
```

2. 基于 **rebase 后的** tasks.md：
   - 勾选当前任务组的所有 checkbox
   - 将该任务组注释中的 `status: executing` 改为 `status: done`
   - 校验 `claim-id` 仍等于本 worker，随后把 `claim-id/claimed-at/heartbeat-at` 清回 `none`
   - 如果该 change 所有自动化任务组（`执行模式: auto`，兼容旧 `执行工具: Codex`）**此刻**都已 done：将 tasks.md YAML 头的 `status` 改为 `review`

```bash
# 3. 只提交当前任务组状态；本轮日志实际存在时再单独暂存
git add openspec/changes/<change-id>/tasks.md
# git add .logs/dispatch/<change-id>.md  # 仅当存在
git commit -m "<commit-type>(<change-id>): complete <group-id>

Change-ID: <change-id>"
# <commit-type> 按类型映射：feature→feat, bug→fix, chore→chore, hotfix→fix

git push origin HEAD:refs/heads/<branch-prefix>/<change-id>
# push 被拒（又有并行 push）→ 回到 1 重试，最多 3 轮
# tasks.md rebase 冲突 → 按任务组主键合并：保留双方各自任务组的状态更新，
#   合并后重新执行第 2 步的"全 done"判定
# 每轮 rebase 后重新验证 tasks.md 中 claim-id 仍属于本 worker；所有权变化 → STOP
# 3 轮仍失败 → STOP，写日志（已完成的实现 commit 保留在 worker branch，下一轮恢复）
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
<!-- 执行模式: auto | 约束: 串行 | status: pending | claim-id: none | claimed-at: none | heartbeat-at: none -->
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

- 同机多实例并发时每轮必须在独立 worktree 中执行（见"并发与隔离"）；无 worktree 则同机同一时刻只运行一个实例
- 同一 change 的串行任务组按顺序领取（G0 先于 G1）：dispatch 检查 G0 status 为 done 才领取 G1
- 同一 change 的并行任务组（G1-A, G1-B）可被同一轮次的不同 runner 领取
- 并行 push 被拒后，worker fetch + rebase 到最新远端，并按 group-id 合并 tasks 状态；claim push 竞争失败是例外，必须重新选组而不是 rebase 失败 claim
- 不同 change 完全隔离（不同 feature branch），可同时执行

## 问题日志

执行过程中遇到 STOP/WARN 级别时，**必须**追加记录到 `.logs/dispatch/<change-id>.md`。

### 级别定义

| 级别 | 含义 | 行为 |
|------|------|------|
| **STOP** | 无法继续，需人工处理 | 写日志 → 执行 Claim 释放规则（若已 claim）→ 终止当前 change → 继续扫描下一个 |
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

- **不做**：审查、合并到 main、main-shared 分形文档的最终同步、verify、归档（change-owned `_DIR.md` 与 pending-sync 仍按 Step 5 维护）
- **不做**：修改 main 上的任何文件（backlog、specs、project.md）
- **不碰**：`执行模式: interactive` 的任务组（兼容旧 `执行工具: Claude Code`）
