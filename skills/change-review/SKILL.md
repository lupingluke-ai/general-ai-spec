---
name: change-review
description: Interactive AI skill (Claude Code or Codex) for reviewing dispatch-completed changes. Uses branch-centric review, performs hard checks and three-dimension Verify before merge, then publishes specs/archive/backlog updates through a recoverable governance PR. Use when dispatch runner has completed task groups (status review) or when manually triggered.
---

# Change Review & Archive

## Overview

接管 dispatch runner 执行完成后的全部收尾流程：PR 审查 → 分形同步（在 feature branch 上）→ 本地 CI → rebase → **三维 Verify → 合并实现 PR → main-side sync → governance archive PR → 更新 backlog**。

**Branch-Centric 模型：** 四件套和实现代码都在 feature branch 上，通过 PR 审查和合并。审查者可在 PR diff 中同时看到方案（四件套）和实现（代码），确保一致性。

**可恢复闭环：** 所有可能阻止交付的硬检查都在实现 PR 合并前完成。required checks 尚未完成时启用 auto-merge 并结束本轮；实现 PR 合并后，归档与共享治理文件通过确定性 `governance/change-review/<change-id>` PR 发布。重跑本 skill 会同时检查实现 PR 与 governance PR，因而不会重复 sync、move 或提交。

**Announce at start:** "Running change-review: checking for changes ready for review."

## Bash 命令规范

为兼容 Claude Code / Codex 等不同执行环境的权限与审批模型，所有 Bash 操作必须遵循：

1. **每条命令独立调用** — 不在一条 Bash 中用 `&&`、`||`、`;` 串联多条命令
2. **管道可以用** — 单条命令内的管道（如 `git branch -r | grep feat/`）是允许的
3. **并行无依赖时分开调用** — 多条独立命令应作为多个并行 Bash tool call 发送

## 类型 → 分支前缀映射规则

type 的事实源是 `product/backlog.md` 的**类型列**（Step 1 方式 A 扫描 backlog 时同一行直接读到）；方式 B/D 从 PR 的 `headRefName` 分支前缀直接得到。由 type 映射 branch / commit 前缀：

| type | branch 前缀 | commit type |
|------|------------|-------------|
| feature | `feat/` | `feat` |
| bug | `fix/` | `fix` |
| chore | `chore/` | `chore` |
| hotfix | `hotfix/` | `fix` |

下方 Step 1 / Step 3 / Step 6 所有命令中的 `<branch-prefix>` 和 `<commit-type>` 均按本规则映射，不从 change-id 字符串反解析。

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

若实现 PR 已 merged，且 main 上仍存在 `openspec/changes/<change-id>/tasks.md`，读取 main 上的 tasks.md。若 YAML 头 `status: review`，说明三维 Verify 已在合并前通过、但 archive 尚未完成；进入**恢复模式**（Step 5 main-side prep → Step 6 archive）。若 change 目录已移入 `openspec/changes/archive/` 且 tasks.md status 为 `done`，继续检查远端 feature branch 并做幂等清理。

如果没有待审查的 change，提示用户 "No changes ready for review."

### 状态机：断点续跑

默认单轮闭环（Step 2 → Step 6 一次调用走完）。每次启动先根据 PR 状态 / tasks.md status 推断断点（所有 type 统一）：

| PR 状态 | CI 状态 | tasks.md status | 本次行为 |
|---------|---------|-----------------|---------|
| Draft | — | review | **完整闭环**：Step 2 审查 → Step 3 分形同步 → Step 3.5 CI → Step 3.8 rebase → Step 3.9 Verify → Step 4 合并 → Step 5-6 governance archive |
| Open (Ready) | 绿 | review | 确认最新 SHA 已通过 Step 3.9，再补执行合并 → 继续 Step 5-6 |
| Open (Ready) | 红 | review | 回 Step 3.5 修复循环 → push → 重走 Step 3.8 起 |
| Open (Ready) | pending + `autoMergeRequest` 非空 | review | `--auto` 已挂起等待 checks → 本次跳过，等下次扫描 |
| Open (Ready) | pending + `autoMergeRequest` 为空 | review | 上次可能中断在 `gh pr ready` 后 → 进入 Step 4 恢复合并；即时合并被 required checks 拒绝时再启用 `--auto` |
| MERGED | — | review | **恢复模式**：先检查 `governance/change-review/<change-id>`；PENDING 等待，READY 从 Step 5 main-side prep → Step 6 archive 续跑 |
| MERGED | — | done | **幂等收尾**：归档已完成；若远端 feature branch 仍存在则删除，然后跳过 |

检查 PR 状态：
```bash
gh pr view <pr-number> --json state,isDraft,statusCheckRollup,autoMergeRequest
```

## Step 2 — PR Review（在 Feature Branch 上）

对待审查 change 的 PR 执行以下检查：

首先在 feature branch 运行 `node scripts/validate-change.mjs --change <change-id> --type <type> --phase review`，结构、terminal groups、auto 状态或 optional specs marker 不合法时 STOP。

- [ ] **Spec 合规**：实现匹配 design.md 文件清单和技术方案
- [ ] **Delta Specs 合规**：实现覆盖 delta specs 中的 ADDED/MODIFIED 场景
- [ ] **范围合规**：实现文件匹配 design.md；change 四件套、tasks 状态与 `pending-sync.md` 作为治理产物单独校验
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
git pull --ff-only origin <branch-prefix>/<change-id>
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

命中 main 共享 `_DIR.md` 的待办项必须追加到 **`openspec/changes/<change-id>/pending-sync.md`**（change 独占文件，与 dispatch 共用同一通道，随 PR 合并进 main），供归档阶段（Step 5.0 / 6.1.5）读取。格式：

```markdown
- [ ] src/features/_DIR.md — 追加条目: voice/（新建目录）· 记录方: review · YYYY-MM-DD
```

commit + push（仅 change 独占部分，按实际存在路径显式暂存）：

```bash
git add -- <changed-change-owned-paths...> openspec/changes/<change-id>/tasks.md
# pending-sync.md 与 review 日志仅在实际存在/修改时分别执行 git add
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

如果全部通过 → 进入 Step 3.8。

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

## Step 3.8 — Rebase to Latest Main（消除合并冲突窗口）

**硬规则：Step 4 合并之前必须 rebase 到最新 main。** feature branch 在 propose 后可能经历 10+ 分钟甚至数小时，期间 main 可能有其他 change 归档 / 模块改动 / backlog 更新，不 rebase 直接合并会在 merge 阶段遇到冲突。

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
- 提示用户：两个 change 的 design.md 有范围重叠，需人工裁决（其一放弃 / 重新 propose / 接受合并）
- PR 保持 Draft，中止本次 review

### 情况 C：有冲突，落在治理层文件

说明 dispatch 或之前的 review 步骤违反了"feature branch 治理层禁改清单"（见 `core/AGENTS.md`）。

- 写日志（STOP 级别，类型："治理层禁改清单违反"）
- 提示用户并中止
- 恢复手段：需要从 feature branch 的 git log 找到违规 commit 并 `git revert` 或 `git reset` 后重新 push（非自动化范畴）

### force-push 后

```bash
git push --force-with-lease origin <branch-prefix>/<change-id>
```

此步必然触发 Draft PR 内容更新 + 远程 CI 重新运行（如有）。本地 CI 三件套已在 Step 3.5 保证通过，因此**无需等待远程 checks**即可进入 Step 4——若仓库配置了 required checks 且尚未完成，Step 4 的即时合并会被拒并自动走 `--auto` 兜底路径。若可查询远程 checks 且发现红灯（本地绿远程红，多为环境差异）→ 回到 Step 3.5 自动修复循环。

## Step 3.9 — 合并前全景一致性与三维 Verify

所有可能产生 STOP 的硬检查都必须在 PR 合并前执行。发现偏离时写入 `.logs/review/<change-id>.md`，修复后重新运行 Step 3.5、3.8、3.9。

R1 只比较**实现文件集**。change 治理产物（`openspec/changes/<change-id>/`）和本 change 审计日志（`.logs/{propose,dispatch,review}/<change-id>.md`）由 Pre-flight、状态与日志格式检查单独验证，不计入 design.md 的实现文件差集。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| R1 | PR 实际实现文件集 = design.md 完整文件清单 | `gh pr diff --name-only` 排除 change 治理产物后对比 design.md | 范围偏离 |
| R2 | 没有 `[NEEDS-FIX]` 标记残留在代码中 | grep 代码库 `NEEDS-FIX` | 方案偏离 |
| R3 | tasks.md 所有自动化任务组（`执行模式: auto`，兼容旧 `执行工具: Codex`）status 为 done | 解析 tasks.md HTML 注释 | 一致性偏离 |
| R4 | delta specs 每个 ADDED/MODIFIED 场景都有实现位置与测试/验证证据；REMOVED 场景确认行为不存在 | specs → 代码与测试追溯表 | 范围偏离 |

**偏离处理：**
- **R1 范围偏离** → 写日志 → STOP（需人工确认是否接受额外文件）
- **R2 NEEDS-FIX 残留** → 写日志 → 自动修复或 STOP
- **R3/R4 一致性偏离** → 写日志 → STOP（不应在此阶段出现）

### Completeness（完备性）

- [ ] 所有 auto 任务组与「文档与分形同步」已完成
- [ ] 每个 delta 场景都有实现与验证证据；optional empty specs 有 `specs/README.md` 理由
- [ ] pending-sync.md 每条待办都能追溯到 design.md，且将在归档 governance PR 消费

### Correctness（正确性）

- [ ] 代码行为匹配 proposal Intent
- [ ] `pnpm test`、`pnpm lint`、`pnpm build` 全绿

### Coherence（一致性）

- [ ] 实际实现文件与 design.md 清单一致
- [ ] 新文件头注释、新目录 `_DIR.md` 完整
- [ ] main-shared `_DIR.md` 与 `openspec/project.md` 的变更已进入 pending-sync/main-side prep 计划

通过后勾选「Verify」任务组并设为 done，运行 `node scripts/validate-change.mjs --change <change-id> --type <type> --phase premerge`；校验通过后只暂存 tasks.md 与实际存在的 review 日志，commit/push feature branch。push 后重新确认 required checks 针对最新 SHA 运行。

## Step 4 — 合并 PR（单轮闭环的关键步）

Step 3.9 全部通过后，标记 Ready 并合并：

```bash
gh pr ready <pr-number>
gh pr merge <pr-number> --merge
```

合并策略固定为 merge commit。即时合并被 required checks 拒绝时启用 `gh pr merge <pr-number> --auto --merge`；PENDING 时结束本轮，下一轮从 MERGED 恢复。需要人工 approving review 时保持 PENDING，不绕过保护规则；只有明确拒绝、权限不足或不可恢复冲突才 STOP。

---

## Step 5 — Main-side Coherence Prep（合并后、可恢复）

```bash
git checkout main
git pull --ff-only origin main
scripts/governance-publish.sh --check --skill change-review --scope <change-id>
```

返回 PENDING 时立即结束，不重复 sync/archive；返回 MERGED 时确认 archive 已在 origin/main，进入幂等分支清理；READY 时继续。

在 main 工作区准备最终治理层文档，所有修改稍后通过 archive governance PR 一次发布：

1. 更新 `openspec/project.md` 的 Directory Structure（如本 change 增删了顶层结构）
2. 读取 **`openspec/changes/<change-id>/pending-sync.md`**（PR 合并后已在 main 上；dispatch 与 review 在执行期共同追加）：逐条在 main 上更新对应的 main-shared `_DIR.md`，完成一条勾选一条
3. 若 `pending-sync.md` 不存在（本 change 未触碰共享 `_DIR.md`，或历史 change），跳过

若工作区已有上次中断留下的 archive 变更，先检查变更是否全部落在 6.4 allowlist：是则直接恢复暂存/发布；存在范围外 tracked 修改则 STOP。未跟踪且与 allowlist 无关的用户文件保持不动。

## 复盘检查点 B — 归档前完整性

Step 3.9 Verify 已完成；main-side prep 后、归档前执行以下检查。发现偏离时写入 `.logs/review/<change-id>.md`。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| R5 | tasks.md 中除「归档」任务组外的 checkbox 已勾选 | 统计 `- [ ]` 残留数，允许「归档」组在 Step 6.2 勾选 | 一致性偏离 |
| R6 | openspec/project.md Directory Structure 已包含新目录 | 对比实际 `src/` 结构 | 一致性偏离 |
| R7 | backlog.md 状态与实际一致 | 确认阶段为 `proposed`（归档前 backlog 应处于 proposed，归档后 Step 6.3.1 会写为 done）| 一致性偏离 |
| R8 | 归档前模块生命周期同步正确 | 当前 B-NNN 尚未写 done 时模块 status 应为 `active`（历史未归类跳过）；最终 `done` 判定在 Step 6.3.2 执行 | 一致性偏离 |

**偏离处理：**
- **R5 未勾选非归档 checkbox** → 写日志 → STOP（任务未完成不应归档）
- **R6 project.md 未更新** → 写日志 → 自动更新后继续
- **R7 backlog 状态异常** → 写日志 → STOP（状态流转异常）
- **R8 模块状态不一致** → 写日志 → 自动修正为归档前应有状态

**历史兼容跳过**：若 backlog 该行"模块"列为 `—`，R8 自动跳过。

> backlog 阶段是唯一状态源；roadmap AUTO 段与模块文档不再存储阶段镜像（AUTO 段由 Step 6.3.3 从 backlog 全量重渲染，模块 `## 关联 Backlog` 行不带阶段标签），因此无需归档前的镜像比对检查点。

---

## Step 6 — Archive with Sync（在 Main 上）

### 6.1 Sync delta specs

将 `openspec/changes/<change-id>/specs/` 合并到 `openspec/specs/`：

- **ADDED** → 追加到对应领域 spec 文件（不存在则新建）
- **MODIFIED** → 替换对应领域 spec 文件中的旧版本
- **REMOVED** → 从对应领域 spec 文件中删除

### 6.1.5 Confirm main-shared `_DIR.md` sync（从 Step 5.0 继承）

确认 `openspec/changes/<change-id>/pending-sync.md` 中的待办已在 Step 5.0 全部勾选。若文件不存在或全部已勾选，本步跳过。

若发现仍有未勾选待办，则在 main 上补做：

1. 打开 main 上对应路径的 `_DIR.md`（此时 main 已包含 feature branch 合并后的内容）
2. 按待追加 / 更新 / 删除的子项操作（插入新条目、保序）
3. 修改后写回，并在 `pending-sync.md` 中勾选该条

此步在本地 `main` 快照上准备，不回写 feature branch；它与 6.1 sync delta specs 一起进入 Step 6.4 的 governance PR。`pending-sync.md` 在 6.2 归档时随 change 目录移入 `archive/`，保留完整处理痕迹。

**为什么不在 Step 3 / dispatch 直接改共享 `_DIR.md`：** feature branch 独立存在期间，同一个 `_DIR.md` 可能被多个并行 change 各自修改（比如 change-A 加 `voice/`、change-B 加 `billing/`）。如果都在 feature branch 上改，merge 时 git 会看到同一文件同一段双向修改 → 冲突。推迟到 main 上串行处理，由 `git-safe-push` 协议处理并发。

**历史兼容**：change 目录无 `pending-sync.md`（老 change 或 change 本身没新建顶层目录）→ 跳过本步。

### 6.2 Archive change

1. 勾选「归档」任务组的所有 checkbox，将其 `status: pending` 改为 `status: done`
2. 将 tasks.md YAML 头 `status` 设为 `done`
3. 确认 tasks.md 中所有 checkbox 已勾选
4. 移动 change 目录到 `openspec/changes/archive/`
5. 更新 `openspec/changes/_DIR.md`（移除活跃条目）
6. 更新 `openspec/project.md` Directory Structure

### 6.3 Update backlog + Module + Roadmap（全量重渲染）

#### 6.3.1 backlog 条目

更新 `product/backlog.md` 对应条目：
- 阶段 → `done`
- 确认 Change 列的 change-id 已归档（1:1 绑定，单值）

#### 6.3.2 模块文档 `design/modules/<M-NNN>-<slug>.md`

从 backlog 该行的"模块"列读到 `M-NNN`（由 `module-designer` 落盘、`prd-writer` 消费）：

- `## 修订历史` 追加 `YYYY-MM-DD | B-NNN 归档 (<change-id>) | change-review`
- **模块生命周期判定**：读取 `product/backlog.md` 中所有"模块"列为 `M-NNN` 的 backlog 行
  - 若全部 `done` → frontmatter `status: active → done`
  - `## 修订历史` 额外记录 `YYYY-MM-DD | 模块完结（B-NNN 为最后一条归档）| change-review`
  - 否则保持 `active`

> `## 关联 Backlog` 行不携带阶段标签（阶段唯一存于 backlog.md），本步不改该小节。

**历史兼容**：若 backlog 该行"模块"列为 `—`（未归类），只跳过 6.3.2 的模块文档更新；6.3.3 仍从全量 backlog 重渲染 Roadmap。

#### 6.3.3 Roadmap（全量重渲染）

backlog（6.3.1）与模块文档（6.3.2）落盘后运行 `node scripts/render-roadmap.mjs --write`，暂存前运行 `--check`。渲染器按以下规则生成三段 AUTO 区：

- `AUTO:ARCHITECTURE`：遍历 `design/modules/*.md` frontmatter 生成模块表
- `AUTO:DEPENDENCIES`：由模块 `depends-on` 生成邻接表
- `AUTO:PROGRESS`：遍历 `product/backlog.md` 按模块分节生成进度行（💡/🔎/📝/✅ 按阶段列映射）

人工段（愿景 / 原则 / 里程碑）原样保留。重渲染幂等——即使上游 skill 曾漏更新某行，本次渲染自动拉齐。

### 6.4 Governance PR 发布归档

只暂存本 change 的明确路径，禁止全仓 `git add -A`：

```bash
git add -A -- openspec/changes/<change-id>
git add -A -- openspec/changes/archive/<change-id>
git add -- openspec/specs/
git add -- openspec/changes/_DIR.md
git add -- openspec/project.md
git add -- product/backlog.md
git add -- design/modules/<M-NNN>-<slug>.md
git add -- design/roadmap.md
git add -- <pending-sync 中实际更新的共享 _DIR.md...>
git add -- .logs/review/<change-id>.md
```

不存在的可选日志或 pending-sync 路径不要传给 `git add`。把原归档 commit message 写入仓库外临时文件，调用：

```bash
scripts/governance-publish.sh \
  --skill change-review --scope <change-id> \
  --title "chore(<change-id>): archive and sync specs" \
  --commit-file <temp-message-file> -- \
  openspec/changes/<change-id> openspec/changes/archive/<change-id>/ \
  openspec/specs/ openspec/changes/_DIR.md openspec/project.md \
  product/backlog.md design/modules/<M-NNN>-<slug>.md design/roadmap.md \
  <updated-shared-_DIR.md...> .logs/review/<change-id>.md
```

MERGED 后进入 6.5；PENDING 时本轮结束，下轮先 `--check`，不得重复执行 sync/move；STOP 时按语义冲突策略处理。

冲突落在本 skill 范围内可自动处理的段：
- `product/backlog.md` / `design/roadmap.md` AUTO 段 / `design/modules/M-NNN.md` 的 `## 关联 Backlog` / `## 修订历史`
- `openspec/changes/_DIR.md`（change-id 主键行）

冲突落在主 specs（`openspec/specs/**.md`）→ **STOP**（spec 合并涉及语义，禁止自动化；需人工检查 change 的 delta specs 是否与 main 上已有的另一 change 同步产生的 delta 冲突）。

> 发布器会拒绝任何超出 allowlist 的 staged 文件，因此用户未跟踪文件和其他 change 不会被归档提交带入。

### 6.5 Clean up branch（governance PR 合并后）

只有 Step 6.4 返回 MERGED、确认 archive 已在 `origin/main` 后，才删除远程 feature branch：

```bash
git push origin --delete <branch-prefix>/<change-id>
```

若删除失败，记录 WARN 并保留分支供下轮幂等清理；不得回滚已完成的 archive，也不得为单纯清理警告再制造治理 PR。

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
  → PR review → fractal sync → 本地 CI + 自动修复 → rebase → pre-merge Verify
  → 实现 PR merge（checks 未完成时 auto-merge）
  → main-side prep → governance archive PR → backlog done
  → 任一步中断均由实现 PR + governance PR 状态恢复
  → 归档收尾：模块修订历史追加；若该模块最后一条 backlog done → 模块 status active → done；roadmap AUTO 段全量重渲染
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
| 合并被拒且无法兜底 | checks 与所需 approval 已满足后仍因权限/策略明确拒绝，或存在不可恢复冲突；单纯等待人工 review 是 PENDING |
| 远程 CI 红 | `--auto` 兜底后 checks 失败，Step 3.5 修复 2 轮仍红 |
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
| 退化为 --auto 兜底 | required checks 未跑完，即时合并被拒，已启用 GitHub auto-merge 等待 |
| 分形文档自动补充 | 自动补了缺失的 `_DIR.md` 或头注释 |
| 分支删除失败 | 归档后无法删除远端分支 |
| 模块状态自动修正 | R8 发现模块 status 不一致，已按"全 done → done，否则 active"重算并写回 |
| 历史兼容跳过 | backlog "模块"列为 `—`，跳过 6.3.2 / R8 |
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

- **手动**：用户告诉 Claude Code 或 Codex "审查已完成的 change"；若 required checks 或 governance PR 仍在等待，下一次触发会从 durable checkpoint 续跑
- **定期（推荐，全自动闭环必需）**：`/loop <interval> /change-review` 或其他定时 runner 定期扫描 `status: review`；兜底路径（--auto 等待 checks）与中断恢复都依赖下一次扫描续跑
- **PR 事件**：dispatch push 后 CI 全绿，PR 自动更新，用户或交互式 agent 发现后触发
- **通知**：dispatch runner 完成后（Codex Automation 会有 inbox 通知，其他 runner 见 `.logs/dispatch/` 日志），用户手动触发
