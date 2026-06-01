---
name: change-review
description: Interactive AI skill (Claude Code or Codex) for reviewing dispatch-completed changes. Uses branch-centric model where review happens via PR. Handles PR review, fractal documentation sync on branch, PR merge to main, three-dimension verify, delta specs sync, archiving, and backlog status update. Use when dispatch runner has completed task groups (status review) or when manually triggered.
---

# Change Review & Archive

## Overview

接管 dispatch runner 执行完成后的全部收尾流程：PR 审查 → 分形同步（在 branch 上）→ PR 合并 → verify → sync specs → 归档 → 更新 backlog。

**Branch-Centric 模型：** 四件套和实现代码都在 feature branch 上，通过 PR 审查和合并。审查者可在 PR diff 中同时看到方案（四件套）和实现（代码），确保一致性。

**Announce at start:** "Running change-review: checking for changes ready for review."

## Bash 命令规范

为兼容 Claude Code / Codex 等不同执行环境的权限与审批模型，所有 Bash 操作必须遵循：

1. **每条命令独立调用** — 不在一条 Bash 中用 `&&`、`||`、`;` 串联多条命令
2. **管道可以用** — 单条命令内的管道（如 `git branch -r | grep feat/`）是允许的
3. **并行无依赖时分开调用** — 多条独立命令应作为多个并行 Bash tool call 发送

## 类型 → 分支前缀派生规则（单一事实源）

从 `change-id` 字符串前缀派生（零 I/O，全流程复用）：

| 判定顺序 | change-id 前缀 | type | branch 前缀 | commit type |
|---------|---------------|------|------------|-------------|
| 1 | `startsWith("hotfix-")` | hotfix | `hotfix/` | `fix` |
| 2 | `startsWith("chore-")` | chore | `chore/` | `chore` |
| 3 | `startsWith("fix-")`（严格 4 字符，排除 `fixture-*`） | bug | `fix/` | `fix` |
| 4 | 其余 | feature | `feat/` | `feat` |

下方 Step 1 / Step 3 / Step 6 所有命令中的 `<branch-prefix>` 和 `<commit-type>` 均按本规则派生。

示例：
```bash
# ❌ 错误：复合命令触发确认
git fetch origin && git branch -r | grep feat/ && gh pr list --state open

# ✅ 正确：拆分为独立调用
# Call 1: git fetch origin
# Call 2: git branch -r | grep feat/
# Call 3: gh pr list --state open --json number,headRefName,title,isDraft
```

---

## Step 1 — 发现待审查 Change

四种发现方式：

### 方式 A：扫描 Backlog + Feature Branch

读取 main 上 `product/backlog.md`，找到阶段为 `proposed` 且有 change-id 的条目（backlog 只有 4 阶段：idea/exploring/proposed/done；执行中 / 审查中的细粒度由 tasks.md YAML status 承担）。对每个 change-id：

```bash
git fetch origin <branch-prefix>/<change-id>
git show origin/<branch-prefix>/<change-id>:openspec/changes/<change-id>/tasks.md
```

筛选 YAML 头 `status: review` 的 change。

若 fetch feature branch 失败，但 main 上 backlog 仍为 `proposed`，不要直接放弃；进入方式 D 检查是否属于"已 merge 但未 archive"恢复场景。

### 方式 B：扫描 Draft PR

```bash
gh pr list --state open --draft --json number,headRefName,title
```

检查 Draft PR 对应的 feature branch 上的 tasks.md status。

### 方式 C：CI 状态驱动

dispatch push 后 CI 自动运行。CI 全绿 + tasks.md status 为 `review` 即可触发审查。

### 方式 D：Merged PR 恢复扫描（branch 已删除或 fetch 失败）

查询与 `<branch-prefix>/<change-id>` 对应的历史 PR：

```bash
gh pr list --state merged --head <branch-prefix>/<change-id> --json number,headRefName,mergedAt
```

若 PR 已 merged，且 main 上仍存在 `openspec/changes/<change-id>/tasks.md`，读取 main 上的 tasks.md。若 YAML 头 `status: review`，说明上一轮可能已合并 PR 但尚未完成 archive；直接进入轮次 2（Step 5 verify → Step 6 archive）。若 change 目录已移入 `openspec/changes/archive/` 且 tasks.md status 为 `done`，视为已完成并跳过。

如果没有待审查的 change，提示用户 "No changes ready for review."

### 状态机：分轮处理

review skill 与 auto-merge 协作，一个 change 可能跨多轮完成。每轮根据 PR 状态 / CI 状态决定行为（所有 type 统一）：

| PR 状态 | CI 状态 | tasks.md status | 本轮行为 |
|---------|---------|-----------------|---------|
| Draft | — | review | **轮次 1**：Step 2 审查 → Step 3 分形同步 → Step 3.5 本地 CI → Step 4 `gh pr ready` |
| Open (Ready) | 绿/pending | review | **跳过**：等 auto-merge 合并 |
| Open (Ready) | 红 | review | **回退**：`gh pr ready --undo` → 尝试修复 → push → 下一轮重走轮次 1 |
| MERGED | — | review | **轮次 2**：Step 5 verify → Step 6 archive |
| MERGED | — | done | **跳过**：已完成 |

检查 PR 状态：
```bash
gh pr view <pr-number> --json state,isDraft,statusCheckRollup
```

## Step 2 — PR Review（在 Feature Branch 上）

对待审查 change 的 PR 执行以下检查：

- [ ] **Spec 合规**：实现匹配 design.md 文件清单和技术方案
- [ ] **Delta Specs 合规**：实现覆盖 delta specs 中的 ADDED/MODIFIED 场景
- [ ] **范围合规**：只修改了 design.md 声明范围内的文件
- [ ] **测试通过**：CI 绿灯；如 CI 未运行或不可用，须本地依次运行 `pnpm test`、`pnpm lint`、`pnpm build` 且全部通过
- [ ] **分形文档合规**：新文件有头注释，新目录有 `_DIR.md`
- [ ] **Change-ID**：commit message 包含 `Change-ID: <change-id>`

**问题处理策略：**
- **可自动修复**（缺 _DIR.md、缺头注释、格式问题）→ Step 3 中自动修复，继续流程
- **不可自动修复**（设计偏离、测试持续失败、范围越界）→ STOP，输出问题报告，等待人工决策

## Step 3 — 分形文档同步（在 Feature Branch 上，**仅 change 独占部分**）

审查通过后，在 feature branch 上完成**change 独占**的分形同步：

```bash
git checkout <branch-prefix>/<change-id>
git pull origin <branch-prefix>/<change-id>
```

对照 design.md 中的 `_DIR.md` 清单逐条处理：

```bash
# 对 design.md 列出的每个 _DIR.md 路径执行：
git ls-tree origin/main -- <path-to-_DIR.md>
```

**分流规则（防止 feature branch 与 main 共享文件冲突）：**

| `git ls-tree origin/main` 命中？ | 归属 | 处理阶段 |
|---|---|---|
| ❌ 未命中（change 新建目录）| **change 独占** | **本步 Step 3 在 feature branch 上更新** |
| ✅ 命中（main 已存在的共享 `_DIR.md`）| **跨 change 共享** | **推迟到 Step 6.1.5 在 main 上更新** |

本步**只**处理 change 独占部分：

1. change 新建目录的 `_DIR.md`（`git ls-tree origin/main` 未命中的）
2. 新文件的 `@input/@output/@pos` 头注释
3. tasks.md：勾选「文档与分形同步」任务组的所有 checkbox，将其 `status: pending` 改为 `status: done`

**禁止**在本步修改：
- main 已存在的 `_DIR.md`（如顶层 `src/_DIR.md`、`src/features/_DIR.md` 等）
- `core/AGENTS.md` 禁改清单中的任何治理层文件（backlog.md / roadmap.md / modules/ / project.md / 主 specs / changes/_DIR.md）

命中 main 共享 `_DIR.md` 的待办项必须记录到 `.logs/review/<change-id>.md` 的"Step 6.1.5 待办"段，供归档阶段读取。日志格式：

```markdown
### [YYYY-MM-DD HH:mm] Step 3 待办 · change-review

- **类型**: main-shared-_DIR.md 需更新
- **级别**: SKIP（本步跳过，归档时处理）
- **文件**: src/features/_DIR.md
- **待追加子项**: voice/（新建目录）
- **处理**: 推迟到 Step 6.1.5 在 main 上更新
```

commit + push（仅 change 独占部分）：

```bash
git add -A
git commit -m "chore(<change-id>): fractal documentation sync (change-owned)

Backlog-Ref: B-NNN
Change-ID: <change-id>"
git push origin <branch-prefix>/<change-id>
```

## Step 3.5 — 本地 CI 验证 + 自动修复（在 Feature Branch 上）

**硬规则：本地 CI 不绿，禁止执行 Step 4。**

```bash
pnpm test
pnpm lint
pnpm build
```

如果全部通过 → 直接进入 Step 4。

如果任一失败 → 进入自动修复循环（最多 2 轮）：

1. 读取错误信息，定位问题文件和根因
2. 修复代码（TypeScript 编译错误、ESLint 违规、Next.js 构建限制、测试断言等）
3. Commit + push
4. 依次重跑 `pnpm test`、`pnpm lint`、`pnpm build`
5. 仍然失败 → 再尝试一轮

**可自动修复的错误类型：**
- TypeScript 编译错误（类型不匹配、缺少 import、非法 export）
- ESLint 错误（unused vars、格式问题）
- Next.js 构建限制（Route export、Suspense 边界）
- 测试断言失败（预期值变化）

**不可自动修复的错误类型（直接 STOP）：**
- 逻辑错误（功能行为不对）
- 大范围测试失败（>3 个测试文件）
- 依赖安装失败

2 轮修复后仍然失败 → STOP，PR 保持 Draft，写日志，等待人工介入。

## Step 3.8 — Rebase to Latest Main（消除 auto-merge 冲突）

**硬规则：`gh pr ready` 之前必须 rebase 到最新 main。** 这是 feature branch 在 propose 后可能经历 10+ 分钟甚至数小时，期间 main 可能有其他 change 归档 / 模块改动 / backlog 更新，不 rebase 直接进 auto-merge 会在远端 merge 阶段遇到冲突。

```bash
git fetch origin main
git checkout <branch-prefix>/<change-id>
git rebase origin/main
```

**冲突分三种情况：**

### 情况 A：无冲突（期望路径，Step 3 禁改清单生效后应为主流）

直接 force-push 更新远端：

```bash
git push --force-with-lease origin <branch-prefix>/<change-id>
```

`--force-with-lease` 安全保障：如果远端分支同时被另一轮 dispatch push 过（不该发生，但作为保险），force-push 会失败而不是覆盖。

### 情况 B：有冲突，但仅在"本 change 独占"的文件（src/ 新建路径等）

说明 main 期间有其他 change 修改了本 change 计划新建的同一文件——这通常意味着 change 设计阶段的"文件独占性"假设被破坏。

- 写日志（STOP 级别）
- 提示 Luke：两个 change 的 design.md 有范围重叠，需人工裁决（其一放弃 / 重新 propose / 接受合并）
- PR 保持 Draft，中止本次 review

### 情况 C：有冲突，落在治理层文件

说明 dispatch 或之前的 review 步骤违反了"feature branch 治理层禁改清单"（见 `core/AGENTS.md`）。

- 写日志（STOP 级别，类型："治理层禁改清单违反"）
- 提示 Luke + 中止
- 恢复手段：需要从 feature branch 的 git log 找到违规 commit 并 `git revert` 或 `git reset` 后重新 push（非自动化范畴）

### force-push 后

```bash
git push --force-with-lease origin <branch-prefix>/<change-id>
```

此步必然触发 Draft PR 内容更新 + CI 重新运行。CI 通过前不得进入 Step 4。等待方式：

若当前环境可查询远程 checks，则等待本次 push 触发的 CI 完成；CI 红 → 回到 Step 3.5 自动修复循环。CI 绿或本地 CI 已覆盖且远程 checks pending → Step 4。

## Step 4 — 标记 PR Ready（交给 auto-merge）

本地 CI 全绿后，将 Draft PR 标记为 Ready for Review：

```bash
gh pr ready <pr-number>
```

**不再直接 merge。** 合并由 GitHub Actions `auto-merge.yml` 负责：
1. `auto-merge.yml` 检测到 `ready_for_review` 事件
2. 执行 `gh pr merge --auto --merge`
3. 由 GitHub 在 required checks 通过后执行 merge commit（保留完整提交历史）

**本轮 review 到此结束。** verify + archive 在下一轮处理。

### 异常兜底：远程 CI 红

下一轮 review 扫描时，如果发现 PR 为 Ready 但远程 CI 红：

```bash
gh pr ready --undo <pr-number>
```

退回 Draft → 尝试本地修复 → push → 下一轮重走 Step 3.5。

## 复盘检查点 A — 合并后全景一致性

auto-merge 合并完成后（轮次 2 开始时）、Verify 前，执行以下交叉验证。发现偏离时写入 `.logs/review/<change-id>.md`。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| R1 | PR 实际 diff 文件集 = design.md 完整文件清单 | `gh pr diff --name-only` 对比 design.md | 范围偏离 |
| R2 | 没有 `[NEEDS-FIX]` 标记残留在代码中 | grep 代码库 `NEEDS-FIX` | 方案偏离 |
| R3 | tasks.md 所有自动化任务组（`执行模式: auto`，兼容旧 `执行工具: Codex`）status 为 done | 解析 tasks.md HTML 注释 | 一致性偏离 |
| R4 | delta specs 每个 ADDED 场景有对应的新文件/新函数 | specs → 代码追溯 | 范围偏离 |

**偏离处理：**
- **R1 范围偏离** → 写日志 → STOP（需人工确认是否接受额外文件）
- **R2 NEEDS-FIX 残留** → 写日志 → 自动修复或 STOP
- **R3/R4 一致性偏离** → 写日志 → STOP（不应在此阶段出现）

---

## Step 5 — Verify（三维度，在 Main 上）

```bash
git checkout main
git pull
```

### 5.0 Main-side coherence prep

在执行三维度 Verify 前，先在 main 上同步会影响 Coherence 判断的治理层文档：

1. 更新 `openspec/project.md` 的 Directory Structure（如本 change 增删了顶层结构）
2. 读取 `.logs/review/<change-id>.md` 中的"Step 6.1.5 待办"记录，同步 main-shared `_DIR.md`
3. 若待办不存在或本 change 未触碰共享 `_DIR.md`，跳过

这一步只处理 verify 所需的一致性文档；delta specs sync、change archive、backlog done 仍在 Step 6 执行。

### Completeness（完备性）

- [ ] tasks.md 中自动化任务组与「文档与分形同步」任务组已完成；「Verify」与「归档」任务组可在本轮继续推进
- [ ] delta specs 中每个 ADDED/MODIFIED 场景都有对应实现
- [ ] delta specs 中每个 REMOVED 场景确认已不存在

### Correctness（正确性）

- [ ] 代码行为匹配 proposal.md 中的 Intent
- [ ] `pnpm test` 通过
- [ ] `pnpm lint` 通过
- [ ] `pnpm build` 通过

### Coherence（一致性）

- [ ] 实际目录结构匹配 design.md 的文件清单
- [ ] 所有新文件有 `@input/@output/@pos` 头注释
- [ ] 所有新目录有 `_DIR.md`
- [ ] `openspec/project.md` Directory Structure 已更新

完成后更新 tasks.md：勾选「Verify」任务组的所有 checkbox，将其 `status: pending` 改为 `status: done`。

## 复盘检查点 B — 归档前完整性

Step 5 Verify 完成后、归档前，执行以下检查。发现偏离时写入 `.logs/review/<change-id>.md`。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| R5 | tasks.md 中除「归档」任务组外的 checkbox 已勾选 | 统计 `- [ ]` 残留数，允许「归档」组在 Step 6.2 勾选 | 一致性偏离 |
| R6 | openspec/project.md Directory Structure 已包含新目录 | 对比实际 `src/` 结构 | 一致性偏离 |
| R7 | backlog.md 状态与实际一致 | 确认阶段为 `proposed`（归档前 backlog 应处于 proposed，归档后 Step 6.3.1 会写为 done）| 一致性偏离 |
| R8 | 归档前模块生命周期同步正确 | 当前 B-NNN 尚未写 done 时模块 status 应为 `active`（历史未归类跳过）；最终 `done` 判定在 Step 6.3.2 执行 | 一致性偏离 |
| R9 | 归档前 `design/modules/<M-NNN>-*.md` 的 `## 关联 Backlog` 小节中 B-NNN 行阶段 = `[proposed]` | 行级比对；Step 6.3.2 再更新为 `[done]` | 一致性偏离 |
| R10 | 归档前 `design/roadmap.md` AUTO:PROGRESS 中 B-NNN 行图标 = 📝 | 行级比对；Step 6.3.3 再更新为 ✅ | 一致性偏离 |

**偏离处理：**
- **R5 未勾选非归档 checkbox** → 写日志 → STOP（任务未完成不应归档）
- **R6 project.md 未更新** → 写日志 → 自动更新后继续
- **R7 backlog 状态异常** → 写日志 → STOP（状态流转异常）
- **R8 模块状态不一致** → 写日志 → 自动修正为归档前应有状态
- **R9 / R10 归档前状态未落盘** → 写日志 → 自动补齐为 proposed / 📝

**历史兼容跳过**：若 backlog 该行"模块"列为 `—`，R8 / R9 / R10 自动跳过。

---

## Step 6 — Archive with Sync（在 Main 上）

### 6.1 Sync delta specs

将 `openspec/changes/<change-id>/specs/` 合并到 `openspec/specs/`：

- **ADDED** → 追加到对应领域 spec 文件（不存在则新建）
- **MODIFIED** → 替换对应领域 spec 文件中的旧版本
- **REMOVED** → 从对应领域 spec 文件中删除

### 6.1.5 Confirm main-shared `_DIR.md` sync（从 Step 5.0 继承）

确认 `.logs/review/<change-id>.md` 中的"Step 6.1.5 待办"记录已在 Step 5.0 同步。若 Step 5.0 因历史 change 或缺少待办而跳过，本步也跳过。

若发现仍有未处理待办，则在 main 上补做：

1. 打开 main 上对应路径的 `_DIR.md`（此时 main 已包含 feature branch 合并后的内容）
2. 按待追加 / 更新 / 删除的子项操作（插入新条目、保序）
3. 修改后写回

此步**只在 main 上执行**，不开 feature branch、不走 PR。与 6.1 sync delta specs 并列，都是归档阶段的 main 侧写操作。

**为什么不在 Step 3 做：** feature branch 独立存在期间，同一个 `_DIR.md` 可能被多个并行 change 各自修改（比如 change-A 加 `voice/`、change-B 加 `billing/`）。如果都在 feature branch 上改，merge 时 git 会看到同一文件同一段双向修改 → 冲突。推迟到 main 上串行处理，由 `git-safe-push` 协议处理并发。

**历史兼容**：`.logs/review/<change-id>.md` 不存在"Step 6.1.5 待办"段（老 change 或 change 本身没新建顶层目录）→ 跳过本步。

### 6.2 Archive change

1. 勾选「归档」任务组的所有 checkbox，将其 `status: pending` 改为 `status: done`
2. 将 tasks.md YAML 头 `status` 设为 `done`
3. 确认 tasks.md 中所有 checkbox 已勾选
4. 移动 change 目录到 `openspec/changes/archive/`
5. 更新 `openspec/changes/_DIR.md`（移除活跃条目）
6. 更新 `openspec/project.md` Directory Structure

### 6.3 Update backlog + Module + Roadmap（实时同步）

#### 6.3.1 backlog 条目

更新 `product/backlog.md` 对应条目：
- 阶段 → `done`
- 确认 Change 列的 change-id 已归档（1:1 绑定，单值）

#### 6.3.2 模块文档 `design/modules/<M-NNN>-<slug>.md`

从 backlog 该行的"模块"列读到 `M-NNN`（由 `module-designer` 落盘、`prd-writer` 消费）：

- `## 关联 Backlog` 小节对应 B-NNN 行阶段 `[proposed] → [done]`
- `## 修订历史` 追加 `YYYY-MM-DD | B-NNN 归档 (<change-id>) | change-review`
- **模块生命周期判定**：读取 `product/backlog.md` 中所有"模块"列为 `M-NNN` 的 backlog 行
  - 若全部 `done` → frontmatter `status: active → done`
  - `## 修订历史` 额外记录 `YYYY-MM-DD | 模块完结（B-NNN 为最后一条归档）| change-review`
  - 否则保持 `active`

**历史兼容**：若 backlog 该行"模块"列为 `—`（未归类），跳过 6.3.2 整个小节的模块/roadmap 更新。

#### 6.3.3 Roadmap

更新 `design/roadmap.md`：

- `AUTO:PROGRESS` 段：目标 B-NNN 行图标 `📝 proposed → ✅ done`
- `AUTO:ARCHITECTURE` 段：若本次导致模块 status 变化（`active → done`），替换对应行
- 非本行原样保留

**AUTO 段并发约定（本 skill 负责）：**
- 只改本次 B-NNN 对应的 AUTO:PROGRESS 行（proposed → done）
- 只在本次导致模块 status 变化时触碰 AUTO:ARCHITECTURE 对应行
- 其他 backlog 和其他模块原样保留

### 6.4 Commit + Push（走 git-safe-push 协议）

```bash
git add -A
```

```bash
git commit -m "chore(<change-id>): archive change and sync specs

Backlog-Ref: B-NNN
Module-Ref: M-NNN
Change-ID: <change-id>
Backlog-Stage: done"
```

**推送走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push + 分段冲突策略）：

```bash
# Round 1
git push origin main
# 被拒 → git pull --rebase origin main → 回到 push
# rebase 冲突 → 按 git-safe-push 冲突解决策略处理
# 3 轮仍失败 → STOP，写日志（类型："archive push 失败"）
```

冲突落在本 skill 范围内可自动处理的段：
- `product/backlog.md` / `design/roadmap.md` AUTO 段 / `design/modules/M-NNN.md` 的 `## 关联 Backlog` / `## 修订历史`
- `openspec/changes/_DIR.md`（change-id 主键行）

冲突落在主 specs（`openspec/specs/**.md`）→ **STOP**（spec 合并涉及语义，禁止自动化；需人工检查 change 的 delta specs 是否与 main 上已有的另一 change 同步产生的 delta 冲突）。

> `git add -A` 会包含 `openspec/specs/` 同步、`openspec/changes/archive/<change-id>/` 归档目录、`product/backlog.md`、`design/modules/<M-NNN>-*.md`、`design/roadmap.md`、Step 6.1.5 更新的共享 `_DIR.md`、`.logs/review/<change-id>.md`（如有）全部变更。

### 6.5 Clean up branch（archive push 成功后）

只有 Step 6.4 的 main push 成功后，才删除远程 feature branch：

```bash
git push origin --delete <branch-prefix>/<change-id>
```

若删除失败，追加 WARN 到 `.logs/review/<change-id>.md`，并按 `core/git-safe-push.md` 做一次仅包含日志的补充提交；不得回滚已完成的 archive。这样即使 archive push 曾失败，下一轮 review 仍可通过 feature branch 或 merged PR 恢复扫描继续处理。

---

## 与其他 Skill 的关系

```
module-designer (interactive agent: Claude Code / Codex)
  → 设计：design-inputs → M-NNN module 文档 (status: planning) → 拆 B-NNN 到 backlog (阶段: idea)

prd-writer (interactive agent: Claude Code / Codex)
  → 产品定义：backlog(idea, 模块=M-NNN) → PRD (status: reviewing → approved)
  → 首次激活：模块 status planning → active + backlog 阶段 idea → exploring

change-propose (interactive agent: Claude Code / Codex)
  → 技术规划：PRD approved → 四件套 on branch → Draft PR → backlog: proposed

change-dispatch (any runner — Codex Automation / Claude Code `/loop` / cron / GH Actions)
  → 执行：scan backlog → fetch branch → implement → push → PR 自动更新 + CI 运行

change-review (interactive agent: Claude Code / Codex)  ← 本 skill
  → 轮次 1：PR review → fractal sync → 本地 CI + 自动修复 → gh pr ready
  → (GitHub Actions auto-merge: 启用 --auto --merge → required checks 绿后 merge commit)
  → 轮次 2：verify on main → archive → backlog done
  → 归档收尾：模块 ## 关联 Backlog 行 [proposed] → [done]；若该模块最后一条 backlog done → 模块 status active → done；roadmap AUTO:PROGRESS/ARCHITECTURE 同步
```

**上游依赖（硬前置）：**
- 每个 change-id 必须由 `change-propose` 产出，其 backlog 行"模块"列必须为 `M-NNN`（历史遗留为 `—` 时跳过模块同步）
- `design/modules/<M-NNN>-*.md` 必须存在（由 `module-designer` 落盘）；缺失则 STOP

**下游触发：** 本 skill 归档后状态流稳定，无自动下游；可人工触发，或由配置好的 runner 定期扫描。

## 问题日志

review 过程中遇到 STOP/WARN 级别时，**必须**追加记录到 `.logs/review/<change-id>.md`。

### 级别定义

| 级别 | 含义 | 行为 |
|------|------|------|
| **STOP** | 无法继续，需人工处理 | 写日志 → 终止当前 change 处理 → 继续扫描下一个 |
| **WARN** | 已自动降级处理 | 写日志 → 继续执行 |
| **SKIP** | 条件不满足，正常跳过 | 不写日志 |

### STOP 场景

| 场景 | 触发条件 |
|------|---------|
| 设计偏离 | 实现文件不匹配 design.md |
| 范围越界 | 修改了 design.md 未声明的文件 |
| 合并冲突 | PR 与 main 冲突 |
| 本地 CI 修复失败 | Step 3.5 自动修复 2 轮后仍红 |
| 远程 CI 红 | Ready 后远程 CI 失败，已 undo + 尝试修复仍失败 |
| Verify 完备性失败 | tasks.md 有未完成项 |
| Verify 正确性失败 | test/lint/build 不通过 |
| Verify 一致性失败 | 目录结构不匹配 design.md |
| Specs 合并失败 | delta specs 无法合入主 specs |
| 模块文档缺失 | backlog "模块"列为 `M-NNN`，但 `design/modules/M-NNN-*.md` 不存在（模块文档被误删） |
| 模块生命周期冲突 | 读 backlog 该模块全部行得出"全 done"，但模块 frontmatter status 仍为 `planning`（缺少 active 过渡，状态机异常） |
| 复盘硬偏离 | R1/R3/R4/R5/R7 检查不通过 |

### WARN 场景

| 场景 | 触发条件 |
|------|---------|
| 本地 CI 自动修复成功 | Step 3.5 修复后 CI 恢复绿灯 |
| 远程 CI 回退 | Ready 后远程 CI 红，已 `gh pr ready --undo` |
| 分形文档自动补充 | 自动补了缺失的 `_DIR.md` 或头注释 |
| 分支删除失败 | 归档后无法删除远端分支 |
| 模块状态自动修正 | R8 发现模块 status 不一致，已按"全 done → done，否则 active"重算并写回 |
| 模块关联行自动补齐 | R9 发现 `## 关联 Backlog` 该行归档前阶段未落盘，已补齐为 `[proposed]` |
| Roadmap AUTO:PROGRESS 自动补齐 | R10 发现归档前图标未落盘，已补齐为 📝 |
| 历史兼容跳过 | backlog "模块"列为 `—`，跳过 6.3.2 / R8-R10 |
| 复盘软偏离 | R6 project.md 未更新，已自动修正 |

### 格式

```markdown
### [YYYY-MM-DD HH:mm] 步骤名 · change-review

- **类型**: 测试失败 / lint 错误 / 构建错误 / 范围越界 / 设计偏离 / 合并冲突 / NEEDS-FIX 修复 / 复盘偏离 / 其他
- **级别**: STOP / WARN
- **现象**: 一句话描述
- **上下文**: 根因或相关信息
- **处理**: 自动修复 / STOP 等待人工 / 重试后通过 / 自动修正
```

**不记录**：正常通过的步骤、SKIP 级别跳过。

---

## 触发方式

- **手动**：用户告诉 Claude Code 或 Codex "审查已完成的 change"
- **定期**：通过 Claude Code `/loop` 或其他定时 runner 定期扫描 `status: review`
- **PR 事件**：dispatch push 后 CI 全绿，PR 自动更新，用户或交互式 agent 发现后触发
- **通知**：dispatch runner 完成后（Codex Automation 会有 inbox 通知，其他 runner 见 `.logs/dispatch/` 日志），用户手动触发
