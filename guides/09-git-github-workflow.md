# Git & GitHub 全流程操作指南

本指南覆盖从 propose 到 archive 的每一步 Git/GitHub 操作，以及各角色的职责边界。

---

## 分支模型总览

```
main ─────────────────────────────────────────────────────── (稳定基线)
  │    ↑ design/docs 直接提交       ↑ merge commit (--no-ff)
  │    │                            │
  │  module-designer               │
  │  prd-writer                    │
  │                                │
  └── <branch-prefix>/<change-id> ──●──●──●──●──●──●──── (feature branch)
       ↑ Claude Code                ↑ dispatch ↑ dispatch ↑ Claude Code
       创建 + 四件套               G0 push    G1 push    分形同步 push
```

**一个 change = 一个 branch = 一个 PR = 四件套 + 代码**

**设计层 / 产品层直接提交 main**：
- `module-designer` 产出 `design(M-NNN): ...` 直接落 main（建模块 + 拆 idea + roadmap）
- `prd-writer` 产出 `docs(PRD-NNN): ...` 直接落 main（PRD 是产品文档）
- 两者不开 feature branch，也不走 PR（没有代码变更）

> 分支前缀由 change-id 字符串前缀零 I/O 派生：feature→`feat/`、bug→`fix/`、chore→`chore/`、hotfix→`hotfix/`。下文示例以 feature 为主（`feat/<change-id>`），其他类型把 `feat/` 替换为对应前缀即可。详见 [11-task-types.md](./11-task-types.md)。

---

## 触发方式总览

```
人工触发（需要人开口，共 2 次）           自动触发（无需人工介入）
─────────────────────────────────────    ──────────────────────────────────
① 用户 → Claude Code:                    dispatch runner（每 5 分钟，任选其一）:
     "帮我规划 B-003"                       扫描 backlog → fetch → 认领
       → 创建 branch + 四件套               → 实现代码 → push
       → Draft PR + 更新 main backlog
                                          GitHub（事件驱动）:
② 用户 → Coding Agent:                     任何 push → CI 自动运行
     "review chat-ui-basic-route"           push → Draft PR 自动更新
       → 审查 + 本地 CI 修复 + gh pr ready    Ready → auto-merge.yml 启用 auto-merge
       → auto-merge → verify + archive
```

| 操作 | 触发方式 | 执行者 |
|------|----------|--------|
| 建模块 + 拆 idea + 写 roadmap AUTO 段 | 🙋 人工（/design） | Claude Code (module-designer) |
| 写 PRD + 更新 backlog/exploring | 🙋 人工（/prd B-NNN） | Claude Code (prd-writer) |
| 创建 feature branch | 🙋 人工（用户告知 Claude Code） | Claude Code |
| push 四件套 + 创建 Draft PR | 🙋 人工 | Claude Code |
| 更新 main backlog (proposed) | 🙋 人工 | Claude Code |
| **认领任务组（claim executing）** | 🤖 自动（runner 每 5 分钟） | change-dispatch |
| **实现代码 + push** | 🤖 自动 | change-dispatch |
| Draft PR 内容更新 | 🤖 自动（push 触发） | GitHub |
| CI 运行（test/lint/build） | 🤖 自动（push 触发） | GitHub Actions |
| 审查 + 本地 CI 修复 + gh pr ready | 🙋 人工（轮次 1） | Coding Agent (change-review) |
| 启用 auto-merge → required checks 绿后 merge | 🤖 自动（ready_for_review 触发） | GitHub Actions (auto-merge.yml) |
| verify + archive | 🙋 人工（轮次 2，/loop 发现 MERGED） | Coding Agent (change-review) |
| 删除 feature branch | 🙋 人工（归档时自动包含） | Coding Agent |

---

## 分阶段操作详解

### Stage 1 — 规划：创建 Branch + Draft PR

**执行者：Claude Code** | **分支：main → `<branch-prefix>/<change-id>`**

```bash
# 1. 基于最新 main 创建 feature branch
git checkout main && git pull origin main
git checkout -b feat/<change-id>

# 2. 写入四件套，标记 ready
mkdir -p openspec/changes/<change-id>/specs
# ... 写入 proposal.md, design.md, tasks.md, specs/, _DIR.md

# 3. 提交 + 推送
git add openspec/changes/<change-id>/
git commit -m "chore(<change-id>): add proposal, specs, design, and tasks

Change-ID: <change-id>"
git push -u origin feat/<change-id>

# 4. 创建 Draft PR
gh pr create --draft \
  --title "feat: <change-id> — <简短描述>" \
  --body "## Change: <change-id>
**Backlog Ref:** B-NNN

## Scope
<从 proposal.md 摘要>

## Task Groups
<从 tasks.md 摘要>

🤖 Managed by OpenSpec"

# 5. 回到 main，更新治理层
git checkout main
# 编辑 backlog.md: B-NNN → proposed, change-id, PR link
# 编辑 changes/_DIR.md
git add product/backlog.md openspec/changes/_DIR.md
git commit -m "chore: update backlog and index for <change-id>"
git push origin main
```

**产物：**

| 位置 | 内容 |
|------|------|
| `<branch-prefix>/<change-id>` (remote) | 四件套，tasks.md status: ready |
| GitHub | Draft PR，CI 首次运行 |
| main (remote) | backlog: proposed，_DIR.md 索引 |

---

### Stage 2 — 执行：Dispatch Runner

**执行者：任意 runner（Codex Automation / `/loop` / cron / GH Actions），推荐 worktree 隔离** | **分支：`<branch-prefix>/<change-id>`**

```bash
# 1. 扫描（读 main backlog）
git show main:product/backlog.md
# → 找到 proposed 的 change-id（执行细粒度看 tasks.md status）

# 2. Fetch feature branch
git fetch origin feat/<change-id>

# 3. 读取 tasks.md，选择任务组
git show origin/feat/<change-id>:openspec/changes/<change-id>/tasks.md
# → 找到所有满足前置条件的 pending 自动化任务组（`执行工具: Codex`）

# 4. Checkout + 安装依赖
git checkout feat/<change-id>
git pull origin feat/<change-id>
pnpm install

# 5. 认领任务组（立即 push，作为分布式锁）
# 将当前任务组 status: pending → executing；若 YAML status 为 ready，同时改为 executing
git add openspec/changes/<change-id>/tasks.md
git commit -m "chore(<change-id>): claim G0 as executing

Change-ID: <change-id>"
git push origin feat/<change-id>

# 6. 逐个执行任务组（同一 session 内背靠背）
# ... 实现 G0 ...
git add -A && git commit -m "feat(<change-id>): complete G0

Change-ID: <change-id>"

# ... 如果 G1-A、G1-B 也就绪，继续执行 ...
# ... 实现 G1-A ...
git add -A && git commit -m "feat(<change-id>): complete G1-A

Change-ID: <change-id>"

# 7. 推送
git pull --rebase origin feat/<change-id>
git push origin feat/<change-id>
```

**自动触发效果：**

```
dispatch push
  ├─→ Draft PR 自动更新（展示最新 diff）
  └─→ GitHub CI 自动运行（test + lint + build）
```

---

### Stage 3 — 收尾：Review + Auto-Merge + Archive（两轮模式）

**轮次 1 执行者：Coding Agent (change-review skill)** | **分支：`<branch-prefix>/<change-id>`**
**合并执行者：GitHub Actions (auto-merge.yml)** | **触发：ready_for_review**
**轮次 2 执行者：Coding Agent (change-review skill)** | **分支：main**

```bash
# ══ 轮次 1 ══

# ── 1. 发现待审查 change ──
gh pr list --state open --draft                        # 方式 A: PR 列表
git fetch origin feat/<change-id>                      # 方式 B: 直接 fetch
gh pr view <pr-number> --json state,isDraft            # 判断 PR 状态

# ── 2. 审查 PR（在 feature branch 上）──
git checkout feat/<change-id> && git pull
# 逐项检查 spec 合规、范围合规、测试、分形文档
# 可自动修复的问题直接修复，不可修复的 STOP

# ── 3. 分形文档同步（在 feature branch 上）──
# 补充 _DIR.md、头注释，更新 tasks.md 中 Claude Code 任务组状态
git add -A
git commit -m "chore(<change-id>): fractal documentation sync

Change-ID: <change-id>"
git push origin feat/<change-id>

# ── 3.5 本地 CI 验证 + 自动修复（最多 2 轮）──
pnpm test && pnpm lint && pnpm build
# 失败 → 分析错误 → 修复 → commit + push → 重试
# 2 轮仍失败 → STOP

# ── 4. PR Ready（委托 auto-merge）──
gh pr ready <pr-number>
# 不直接 merge！auto-merge.yml 负责启用 GitHub auto-merge

# ══ auto-merge.yml 自动执行 ══
# gh pr merge --auto --merge                          # required checks 绿后 merge commit

# ══ 轮次 2（/loop 下一轮发现 MERGED）══

# ── 5. Verify 三维度（在 main 上）──
git checkout main && git pull origin main
# Completeness + Correctness + Coherence

# ── 6. 归档 + 清理 ──
# sync delta specs → openspec/specs/
# 移动 change → archive/
# 更新 backlog → done
git add -A
git commit -m "chore(<change-id>): archive change and sync specs"
git push origin main
git push origin --delete feat/<change-id>
git branch -d feat/<change-id>
```

---

## 全生命周期 Git 操作一览

> 🙋 = 人工触发（用户与 Claude Code 交互）　🤖 = 自动触发

```
时间线    触发  操作者          Git / GitHub 操作                  效果
──────────────────────────────────────────────────────────────────────────────
T+0min   🙋   Claude Code     checkout -b feat/X                  —
              Claude Code     commit 四件套 + push                 —
              Claude Code     gh pr create --draft                 Draft PR 出现
              Claude Code     checkout main + commit + push        backlog: proposed
         🤖  GitHub CI        (push 触发)                          CI 首次运行
──────────────────────────────────────────────────────────────────────────────
T+5min   🤖  change-dispatch   fetch + checkout + pull             —
              change-dispatch   claim: executing → commit + push    PR 更新（lock）
              change-dispatch   pnpm install                        —
              change-dispatch   实现 G0/G1-A/G1-B → commit × N     —
              change-dispatch   push                                PR 更新
         🤖  GitHub CI        (push 触发)                          CI 运行
──────────────────────────────────────────────────────────────────────────────
T+30min  🙋  Coding Agent     fetch + checkout + pull             —
              (review skill)  审查 PR + 分形同步 → commit + push   PR 更新（轮次 1）
              Coding Agent    本地 CI 验证 + 自动修复              确保构建通过
              Coding Agent    gh pr ready                          PR → Ready
         🤖  auto-merge.yml  gh pr merge --auto --merge            启用 auto-merge
              GitHub         required checks 绿后 merge commit      merge → main
──────────────────────────────────────────────────────────────────────────────
T+40min  🤖  Coding Agent     检测 MERGED（轮次 2）               —
              (review skill)  checkout main + verify               三维度验证
              Coding Agent    归档 → commit + push main            backlog: done
              Coding Agent    push origin --delete feat/X          branch 删除
──────────────────────────────────────────────────────────────────────────────
```

---

## 分支状态流转图

```
                    Claude Code 创建
                         │
                         ▼
feat/<change-id>    [created] ──push──→ [remote + Draft PR]
                                              │
                                       dispatch push ×N
                                              │
                                              ▼
                                     [PR 更新 + CI 运行]
                                              │
                                     Coding Agent 审查 + 分形同步 + 本地 CI 修复 + push
                                              │
                                              ▼
                                     [gh pr ready → auto-merge → verify → archive]
                                              │
                                              ▼
feat/<change-id>                      [deleted] ✂️
```

---

## Runner 配置

dispatch 可被任何 runner 触发，选一种即可。完整清单见 `skills/change-dispatch/SKILL.md` 的「Runner 配置」，以下是最常用两种：

**Codex Desktop Automation**（24/7 无人值守）
```
Name:     change-dispatch
Schedule: every 5 minutes
Worktree: yes
Network:  allow github.com, allow registry.npmjs.org
Prompt:   使用 $change-dispatch 扫描并执行就绪的任务组
```

**Claude Code `/loop`**（开发期零配置）
```
/loop 5m /change-dispatch
```

---

## 异常处理速查

| 场景 | 原因 | 解决 |
|------|------|------|
| dispatch push 被拒 (non-fast-forward) | 并行任务组或 Claude Code 先 push 了 | `git pull --rebase` 后重试（feature branch） |
| main push 被拒 (non-fast-forward) | 并发 push | 走 `core/git-safe-push.md`（3 轮 pull-rebase-push）；3 轮失败 STOP |
| auto-merge 合并时冲突 | feature branch 基线滞后 / 治理层被误写 | `gh pr ready --undo` → Step 3.8 rebase origin/main（force-with-lease）→ 重新 `gh pr ready` |
| CI 失败 | 代码问题 | dispatch 标记 `[NEEDS-FIX]`，Claude Code review 时修复 |
| `gh pr merge` 失败 | PR 还是 Draft 状态 | 先 `gh pr ready <number>` |
| worktree 锁定分支 | 上一轮 dispatch 未清理 worktree | `git worktree remove --force <path>` |
| feature branch 不存在 | Claude Code 尚未 push | dispatch 跳过，等下一轮 |
| `pnpm install` 失败 | 网络或 registry 问题 | 重试，或检查 Network 配置 |

---

## 关键规则

1. **dispatch 永远不碰 main** — 只在 feature branch 上 commit + push
2. **Backlog 只由 Claude Code 在 main 上更新** — dispatch 不修改治理层
3. **Merge 策略固定为 merge commit** — `gh pr merge --auto --merge` 启用后由 GitHub 以 merge commit 合并（`--no-ff`）
4. **一个 change 一个 branch** — 所有任务组（G0/G1-A/G1-B/G2）在同一个 `<branch-prefix>/<change-id>` 分支上（G 是任务组逻辑标签，不是分支名）
5. **PR = 方案 + 代码** — Draft PR 从规划阶段就存在，贯穿整个生命周期
6. **设计层 / 产品层不开 feature branch** — `module-designer`、`prd-writer` 直接向 main 提交（design / docs 前缀）
7. **push main 走 `core/git-safe-push.md` 协议** — 3 轮 pull-rebase-push + 分段冲突策略（见下）
8. **Rebase-before-ready** — `change-review` 在 `gh pr ready` 前必须 rebase feature branch 到最新 main（消除 auto-merge 阶段冲突窗口）
9. **main 禁止任何 force 推送** — `--force-with-lease` 仅 `change-review` Step 3.8 rebase-before-ready 允许

---

## 多人协同 / 自动化并发下的三类冲突与防护

```
类型 1  feature branch 写了 main 共享文件（治理层）
       → 多 change 各自修改 → auto-merge 阶段物理行冲突
       → 防护：Feature Branch 治理层禁改清单（见 core/AGENTS.md）
              dispatch D1 / review R1 双检查点拦截；Step 3 只处理 change-owned 分形文档

类型 2  同一 main 文件被并发 push（多 runner 叠加：/loop + Codex Automation + 人工）
       → 第二个 push 被拒（non-fast-forward）
       → 防护：core/git-safe-push.md — 3 轮 pull-rebase-push，
              按文件类型（backlog / roadmap AUTO / modules）主键合并

类型 3  auto-merge 阶段 main 又前进了（别的 change 先合并）
       → base 改变，PR 变成"需要更新"
       → 防护：Step 3.8 rebase-before-ready，gh pr ready 前强制 rebase
              origin/main + force-with-lease feature branch
```

### Feature Branch 治理层禁改清单（摘要）

| 文件 / 模式 | 只能在 main 上由谁写 |
|---|---|
| `product/backlog.md` | module-designer / prd-writer / change-propose / change-review |
| `design/roadmap.md` | 同上 |
| `design/modules/*.md` | module-designer（主写）等 |
| `openspec/specs/**.md`（主 specs） | change-review（归档 sync） |
| `openspec/project.md` | change-review（归档时更新 Directory Structure） |
| `openspec/changes/_DIR.md` | change-propose（加行）/ change-review（删行） |
| 存在于 main 的共享 `_DIR.md` | change-review 归档阶段（Step 6.1.5） |

判定"共享 `_DIR.md`"的方法：`git ls-tree origin/main -- <path>` 命中则属于共享。

完整清单和执行检查点见 `core/AGENTS.md` 的 "Feature Branch 治理层禁改清单"。

---

## Commit 前缀登记表

每个 skill 产出 commit 时使用固定前缀，便于 `git log --grep=` 按阶段过滤：

| Skill | 前缀 | 典型 commit message | 落地分支 |
|---|---|---|---|
| `module-designer` | `design(M-NNN): ...` | `design(M-002): voice-entry + 3 backlog ideas` | main |
| `prd-writer` | `docs(PRD-NNN): ...` | `docs(PRD-003): draft PRD for B-003` | main |
| `prd-writer` (approved) | `docs(PRD-NNN): approved` | `docs(PRD-003): approved` | main |
| `change-propose` | `chore(<change-id>): ...` | `chore(ai-voice-entry): add proposal, specs, design, tasks` | feature branch |
| `change-dispatch` | `<type>(<change-id>): ...` | `feat(ai-voice-entry): complete G0` | feature branch |
| `change-review` (fractal) | `chore(<change-id>): ...` | `chore(ai-voice-entry): fractal documentation sync` | feature branch |
| `change-review` (archive) | `chore(<change-id>): ...` | `chore(ai-voice-entry): archive change and sync specs` | main |

**统一 Trailer**：
- `Backlog-Ref: B-NNN` — 所有类型必含
- `Module-Ref: M-NNN` — module-designer / prd-writer / openspec-* skill 必含（历史遗留无模块则省略）
- `Change-ID: <change-id>` — change 层 commit 必含
- `PRD-Status` / `Backlog-Stage` — 状态跃迁类 commit 额外记录

> `<type>` 从 change-id 前缀派生：`feat`（默认）/ `fix`（hotfix-/fix-）/ `chore`（chore-），与 PR title / branch 前缀保持一致。
