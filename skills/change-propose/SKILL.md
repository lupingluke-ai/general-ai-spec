---
name: change-propose
description: Propose an OpenSpec change — scan backlog or accept a specific B-NNN, check PRD readiness and dependencies, generate four-piece set (proposal/specs/design/tasks) on feature branch, create Draft PR, and update main indexes. Works both as one-shot (`/change-propose B-045`) and scheduled by a runner.
---

# Change Propose

## Overview

从 approved PRD 出发，生成四件套（proposal + delta specs + design + tasks），创建 feature branch 和 Draft PR，更新 main 索引。

**职责边界：** 只负责 propose 阶段。执行由 `change-dispatch`，审查/归档由 `change-review` 各自独立完成。

**Announce at start:** "Running change-propose: looking for changes to propose."

## Bash 命令规范

1. **每条命令独立调用** — 不用 `&&`、`||`、`;` 串联
2. **管道可以用** — 如 `git branch -r | grep feat/`
3. **并行无依赖时分开调用** — 多个独立 Bash tool call

## PRD YAML 前置条件

```yaml
---
id: PRD-NNN
type: feature | bug | chore | hotfix
backlog-ref: B-NNN
module-ref: M-NNN                 # 必填；归属模块
status: approved
created: YYYY-MM-DD
depends-on: [B-xxx, B-yyy]        # 前置 backlog 依赖，无则 []
change-id: kebab-case-name        # 预定义 change-id，按类型携带前缀
design-inputs:                    # 必填；至少包含模块文档路径
  - design/modules/M-NNN-<slug>.md
  # - design/inputs/...（可选追加）
---
```

缺少 `type`、`depends-on`、`change-id`、`module-ref` 或 `design-inputs` 的 PRD 会被跳过。`design-inputs` 必须包含一条指向 `design/modules/<M-NNN>-*.md` 的路径，否则视为缺失。

## 类型 → 分支/提交前缀派生规则（单一事实源）

**不读 backlog 也不读 PRD frontmatter**，直接从 `change-id` 字符串前缀派生（零 I/O）。判定按**严格顺序**：

| 判定顺序 | change-id 前缀匹配 | type | branch 前缀 | commit type | PR 标题前缀 |
|---------|-------------------|------|------------|-------------|------------|
| 1 | `startsWith("hotfix-")` | hotfix | `hotfix/` | `fix` | `fix` |
| 2 | `startsWith("chore-")` | chore | `chore/` | `chore` | `chore` |
| 3 | `startsWith("fix-")`（严格 4 字符，排除 `fixture-*`） | bug | `fix/` | `fix` | `fix` |
| 4 | 其余 | feature | `feat/` | `feat` | `feat` |

派生结果在 Phase 0/1/2 全程复用，禁止重新计算或硬编码 `feat/`。**4 种类型走完全相同的执行路径**，前缀差异仅用于语义标签（git log / release notes 过滤）。

---

## Phase 0 — 目标选定

### 有参数（`/change-propose B-045`）

直接定位 `product/backlog.md` 中的 B-045 条目，读取对应 PRD。

### 无参数（`/change-propose`）

扫描 `product/backlog.md`，筛选满足**全部**条件的条目：

1. 阶段为 `exploring`
2. 有 PRD 列值且 PRD 文件存在
3. PRD `status: approved`
4. PRD 有 `type`、`change-id`、`depends-on`、`module-ref`、`design-inputs` 字段
5. `design-inputs` 至少包含一条指向 `design/modules/<module-ref>-*.md` 的路径，且该文件存在
6. `depends-on` 中所有依赖条目阶段为 `done`
7. `<branch-prefix>/<change-id>` 远程分支不存在，或远程分支已存在但 backlog 仍停留在 `exploring`（发布恢复模式）

候选排序：无依赖优先 → backlog ID 小优先。每次最多 propose **1 个**。

无候选时输出 "No changes ready to propose." 并退出。

### 发布恢复模式（半发布自愈）

若远程 `<branch-prefix>/<change-id>` 已存在，但 main 上 backlog 仍为 `exploring` 且 Change 列为空，说明上一次运行可能已完成 branch/PR 创建，却在"更新 Main 索引 + 模块 + Roadmap"阶段失败。此时**不要跳过，也不要重写四件套**：

1. fetch 远程 feature branch
2. 读取远程 `openspec/changes/<change-id>/` 四件套并执行 Phase 2 的 Pre-flight
3. 若 Draft PR 不存在，则补建 Draft PR；若已存在，复用原 PR
4. 直接进入 Phase 2 的"更新 Main 索引 + 模块 + Roadmap"

若远程分支存在且 backlog 已为 `proposed` / `done`，才视为已处理并 SKIP。

> **粒度拆分不在本 skill 范围内**。拆分职责由 `module-designer` 在 `/design` 对话中承担（1 个 idea 拆成 N 条 backlog，各自 1 PRD → 1 change）。propose 阶段信任上游的粒度决定，不做二次检查，避免阻塞自动化流水线。

---

## Phase 1 — 生成四件套

### 1.1 创建 Feature Branch

按"类型 → 分支/提交前缀派生规则"取 `<branch-prefix>`：

```bash
git checkout main
git pull
git checkout -b <branch-prefix>/<change-id>    # feat/ | fix/ | chore/ | hotfix/
mkdir -p openspec/changes/<change-id>/specs
```

### 1.2 proposal.md

从 PRD 提炼，必须包含：

- **Backlog Ref** / **PRD Ref** / **Module Ref**（格式：`M-NNN — <模块名>`，来自 PRD frontmatter）
- **Intent**：从 PRD 背景与问题提炼
- **Scope**：覆盖 Must Have，不覆盖 Nice to Have；**必须落在模块边界的"承担"小节内**（越界时写 STOP 日志并跳过该 change）
- **Approach**：技术路线，含并行开发策略；可引用模块文档的"技术选型"与"对外接口"小节
- **Impact**：受影响目录、`_DIR.md` 清单、环境变量、Breaking Changes
- **复杂度估算**：S / M / L / XL
- **依赖说明**：从 PRD `depends-on` 映射 + 从模块文档 `depends-on` 继承的跨模块依赖（如有）

### 1.3 delta specs

在 `specs/` 下按领域分文件：

- **ADDED Requirements** — 从 PRD F-NNN 功能转化
- **MODIFIED Requirements** — 注明之前行为
- **REMOVED Requirements** — 注明移除原因

每个需求至少一个 Given/When/Then 场景，从 PRD 验收标准和用户故事推导。

### 1.4 design.md

**必须先读取项目现有代码**（`src/` 目录结构、已有组件、已有 API 路由）来确定具体文件路径和复用点。

必须包含：

- **Technical Approach**
- **新增/修改的目录与文件清单**
- **需要新增或更新的 `_DIR.md` 清单**
- **需要新增或更新头注释的关键文件清单**
- **API 设计**（如涉及）
- **并行开发设计**：G0/G1/G2 分组 + 文件冲突矩阵

### 1.5 _DIR.md

为 change 目录创建索引。

### 1.6 tasks.md

#### 依赖分析

先分析任务间依赖：

| 关系 | 定义 | 处理 |
|------|------|------|
| Independent | 不同文件 | 并行 |
| Read-conflict | 只读同一文件 | 并行 |
| Write-conflict | 写同一文件 | 串行或拆分 |
| Sequential | B 依赖 A 的输出 | A 先完成 |

输出并行计划表和文件冲突矩阵（写入 design.md）。

#### 格式

```markdown
---
status: ready
backlog-ref: B-NNN
depends-on: [change-id-1, ...]
---

# <change-id> Tasks

## G0 — <组名>
<!-- 执行模式: auto | 约束: 串行，必须先完成 | status: pending -->
- [ ] ...

## G1-A — <组名>
<!-- 执行模式: auto | 约束: G0 完成后，与 G1-B 并行 | status: pending -->
- [ ] ...

## 文档与分形同步
<!-- 执行模式: interactive | 约束: 自动化任务组全部完成后 | status: pending -->
- [ ] 更新受影响的 _DIR.md
- [ ] 验证新文件头注释
- [ ] 全量验证: pnpm test, pnpm lint, pnpm build

## Verify
<!-- 执行模式: interactive | 约束: 分形同步完成后 | status: pending -->
- [ ] 三维度验证

## 归档
<!-- 执行模式: interactive | 约束: Verify 完成后 | status: pending -->
- [ ] sync specs → archive → update backlog
```

> **执行模式 tag 语义（runner-agnostic）：**
> - `执行模式: auto` = 需要 headless/自动化 runner 承接（实际 runner 可以是 Codex Automation、Claude Code `/loop`、cron、GitHub Actions 任选其一）
> - `执行模式: interactive` = 需要人类在回路的交互式工作（Claude Code / Codex 均可，由 change-review 或人工承接）
>
> dispatch 继续兼容旧 `执行工具: Codex` / `执行工具: Claude Code`，仅用于读取历史 tasks.md / 归档记录。

dispatch runner 从三个来源获取实现上下文：tasks.md 描述 + design.md 方案 + 代码库。

**关键约束：** ≤ 300 行，不内联代码，新 `.ts`/`.tsx` 需 `@input/@output/@pos` 头注释，新目录需 `_DIR.md`。

---

## 复盘检查点 — 四件套交叉一致性

Phase 1 完成后、Phase 2 pre-flight 前，**必须**执行以下交叉验证。

**日志写入是硬性要求：** 发现任何偏离（硬偏离或软偏离）时，**先写入** `.logs/propose/<change-id>.md`，**再**进行修正。即使自动修正成功也必须记录。如果整个复盘无偏离，写入一行 "复盘通过，无偏离" 作为执行凭证。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|--------|----------|---------|
| P1 | proposal.md Scope 只覆盖 PRD Must-Have | 对比 PRD Must-Have 段落（Full PRD 对比 Must Have / Nice to Have / Out of Scope；Lite PRD 只需验证 Must Have 至少 1 条且全覆盖） | 范围偏离 |
| P2 | proposal.md 的 Backlog Ref / PRD Ref 正确 | 与入参 B-NNN 和实际 PRD 文件名对比 | 一致性偏离 |
| P3 | delta specs 每个 Given/When/Then 可追溯到 PRD 验收标准 | 逐条比对 PRD AC 和 specs 场景（type=bug/chore/hotfix 允许 delta specs 为空，此时跳过 P3；若非空则必须每场景可追溯到 AC） | 范围偏离 |
| P4 | design.md 文件清单 = tasks.md 涉及的文件并集 | 提取两个清单做差集比对 | 一致性偏离 |
| P5 | tasks.md 并行组文件冲突矩阵 = design.md 中的矩阵 | 两处矩阵一致 | 一致性偏离 |
| P6 | tasks.md 行数 ≤ 300 且无内联代码块 | 行数统计 + 扫描 ``` 块 | 方案偏离 |
| P7 | proposal.md 的 Module Ref 与 PRD `module-ref` 一致，且 Scope 每条都落在模块边界的"承担"小节内 | 读 `design/modules/<M-NNN>-*.md` 的"模块边界"对比 proposal Scope | 范围偏离 |

**偏离处理：**
- **硬偏离**（P1 含 Out of Scope 功能、P2 引用错误、P7 Module Ref 不一致）→ 写日志 → 自动修正后重新检查
- **软偏离**（P4/P5 数值差异）→ 写日志 → 自动对齐两处清单
- **范围偏离**（P1 / P3 / P7 Scope 越界）→ 写 STOP 日志 → 跳过该 change → 提示 Luke 走 `/design review M-NNN` 扩边界 或 重写 PRD 把越界需求拆到新 backlog
- 所有偏离修正后再进入 Phase 2

---

## Phase 2 — Pre-flight + 发布

### Pre-flight 检查

- [ ] proposal.md 存在且含 Backlog Ref
- [ ] specs/ 至少一个文件，每个需求有 Given/When/Then
- [ ] design.md 存在且含文件清单
- [ ] tasks.md 存在，YAML 头 status 为 ready，≤ 300 行
- [ ] _DIR.md 存在
- [ ] 并行组内无文件写入冲突

### 提交 + 推送

普通模式执行本小节；发布恢复模式下若远程 branch 已存在且四件套 Pre-flight 通过，则跳过本小节，不重复提交 / push 四件套。

```bash
git add openspec/changes/<change-id>/
git commit -m "chore(<change-id>): add proposal, specs, design, and tasks

Backlog-Ref: B-NNN
Change-ID: <change-id>"
```

> commit 首词统一用 `chore`（四件套本身是治理文档，不是功能代码）。实现阶段的 commit 按派生 `<commit-type>` 使用 `feat|fix|chore`。

```bash
git push -u origin <branch-prefix>/<change-id>
```

### 创建 Draft PR

PR 标题前缀按派生 `<pr-type>`（feat/fix/chore）：

发布恢复模式下先查询是否已有 Draft PR；已有则复用 PR number，不重复创建。只有远程 branch 存在但 PR 缺失时，才补建 Draft PR。

```bash
gh pr create --draft --base main --head <branch-prefix>/<change-id> \
  --title "<pr-type>(<change-id>): <简短描述>" \
  --body "$(cat <<'EOF'
## Summary
- Backlog: B-NNN | PRD: PRD-NNN | Change: <change-id>
- 四件套 ready，等待 dispatch runner 领取

## Artifacts
- proposal.md / specs/ / design.md / tasks.md

🤖 Proposed by change-propose
EOF
)"
```

### 更新 Main 索引 + 模块 + Roadmap

本小节是 propose 的 durable checkpoint。无论普通模式还是发布恢复模式，只有本小节 push main 成功后，dispatch / review 才能从 backlog 的 `proposed` 状态接手。

```bash
git checkout main
git pull origin main
```

**1. `product/backlog.md`**：目标 B-NNN 阶段 → `proposed`；Change 列写入 `<change-id>`

**2. `openspec/changes/_DIR.md`**：追加索引条目（含 branch + PR link）

**3. `design/modules/<M-NNN>-*.md`**：
  - `## 关联 Backlog` 小节对应 B-NNN 行阶段 `[exploring] → [proposed]`
  - `## 修订历史` 追加 `YYYY-MM-DD | B-NNN 四件套就绪 (<change-id>) | change-propose`
  - **若 frontmatter `status: planning`，升级为 `active`**（本 skill 的模块激活兜底；正常路径下 prd-writer 已经做过，但若出现某些 backlog 绕过 prd-writer 的场景，此处兜底）

**4. `design/roadmap.md`**：
  - `AUTO:ARCHITECTURE` 段：若模块 status 本次变化则替换对应行
  - `AUTO:PROGRESS` 段：目标 B-NNN 行图标 `🔎 exploring → 📝 proposed`
  - 非本行保持原样（其他模块与其他 backlog 由各自 skill 维护）

```bash
git add product/backlog.md
git add openspec/changes/_DIR.md
git add design/modules/<M-NNN>-<slug>.md
git add design/roadmap.md
git commit -m "chore: update backlog, module, roadmap for <change-id>

Backlog-Ref: B-NNN
Module-Ref: M-NNN
Change-ID: <change-id>
Backlog-Stage: proposed"
```

**推送走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push + 分段冲突策略）：

```bash
# Round 1
git push origin main
# 被拒（non-fast-forward）→ git pull --rebase origin main → 回到 push
# rebase 冲突：
#   - product/backlog.md / design/roadmap.md AUTO:* / design/modules/*.md 常见段 → 按协议自动合并后续 push
#   - 主 specs / 模块边界等策略不覆盖段 → STOP + 日志
# 3 轮仍失败 → STOP，写日志到 .logs/propose/<change-id>.md
```

**AUTO 段并发约定（本 skill 负责）：**
- 只修改本次 B-NNN 的 AUTO:PROGRESS 行（exploring → proposed）
- 只在本次导致 module status 变化时触碰 AUTO:ARCHITECTURE 的对应行
- 其余行原样保留（与其他 skill 并发时由 git-safe-push 协议按 B-NNN/M-NNN 主键合并）

### 输出

```
✅ Proposed: <change-id> (type=<type>)
   Branch: <branch-prefix>/<change-id>
   PR: #<number>
   Backlog: B-NNN → proposed
   Next: change-dispatch 将自动领取并执行
```

---

## 安全边界

### 不做

- **不执行代码** — dispatch skill（任意 runner）的职责
- **不审查/合并/归档** — change-review 的职责
- **不创建/修改 PRD** — prd-writer 的职责
- **不重写已有四件套** — branch 已存在且 backlog 已 `proposed` / `done` 则跳过；branch 已存在但 backlog 仍为 `exploring` 时只执行发布恢复，不改四件套内容

### 跳过 / 等待条件（不报错）

| 条件 | 原因 |
|------|------|
| PRD 缺 `type` / `change-id` / `depends-on` / `module-ref` / `design-inputs` | 需人工补充（prd-writer 或 /design review）|
| PRD `design-inputs` 不含模块文档路径或路径不存在 | 模块文档失联，需人工修复 |
| PRD `module-ref` 指向的 `design/modules/<M-NNN>-*.md` 不存在 | 模块被删或未落盘 |
| PRD status ≠ approved | 需求未批准 |
| 依赖条目未 done | 前置未完成，等待下一轮扫描；显式 `/change-propose B-NNN` 时只提示等待，不写 STOP |
| `<branch-prefix>/<change-id>` 已存在且 backlog 已为 `proposed` / `done` | 已 proposed / 已归档 |
| backlog 阶段已为 proposed/done | 已处理 |
| change-id 前缀与 PRD type 不一致 | 前缀派生与声明矛盾（如 type=feature 但 change-id 以 `fix-` 开头） |

## 问题日志

记录到 `.logs/propose/<change-id>.md`。遇到 STOP/WARN 级别时必须写入，SKIP 不写。

### 级别定义

| 级别 | 含义 | 行为 |
|------|------|------|
| **STOP** | 无法继续，需人工处理 | 写日志 → 终止当前 change → 继续扫描下一个 |
| **WARN** | 已自动降级处理 | 写日志 → 继续执行 |
| **SKIP** | 条件不满足，正常跳过 | 不写日志 |

### STOP 场景

| 场景 | 触发条件 |
|------|---------|
| PRD 缺字段 | `type` / `change-id` / `depends-on` / `module-ref` / `design-inputs` 缺失 |
| 模块文档缺失 | `design/modules/<M-NNN>-*.md` 不存在 |
| Scope 越界 | proposal.md Scope 超出模块"承担"边界（P7 硬偏离）|
| type 与前缀不一致 | PRD `type` 字段与 change-id 派生 type 冲突 |
| Git 操作失败 | checkout/commit/push 任一失败 |
| PR 创建失败 | `gh pr create` 失败 |
| Pre-flight 失败 | 6 项检查任一不通过 |

### 格式

```markdown
### [YYYY-MM-DD HH:mm] 步骤名 · change-propose

- **类型**: PRD 缺字段 / 四件套失败 / Git 失败 / PR 创建失败 / Pre-flight 失败 / 复盘偏离
- **级别**: STOP / WARN
- **现象**: 一句话
- **上下文**: 根因
- **处理**: 跳过 / 重试通过 / STOP / 自动修正
```

## 与其他 Skill 的关系

```
module-designer → 模块设计 + idea 拆分 + 落 backlog（带模块列）→ module: planning
prd-writer      → PRD approved + module: active（首次激活时）
change-propose← 本 skill  → 四件套 + Draft PR → backlog: proposed + module 文档同步
change-dispatch → 代码执行 → tasks: review
change-review → 审查 + 归档 → backlog: done + module: done（最后一条归档时）
```

## 触发方式

- `/change-propose` — 扫描 backlog，propose 下一个就绪条目
- `/change-propose B-NNN` — 直接 propose 指定条目
- runner 定时触发 `/change-propose` — 自动扫描
