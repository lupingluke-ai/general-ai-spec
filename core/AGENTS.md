# AGENTS.md — AI Agent 通用行为规范

> 本文件是 AI Agent（Claude Code / Codex / Cursor / 其他）在本项目中的**核心公约**：读一次就能正确工作的最小行为契约。
> `guides/` 是给人的操作手册，不作为 agent runtime 规则源。Agent 执行以本文件、`openspec/project.md`、`openspec/config.yaml`、`openspec/AGENTS.md`、`skills/*/SKILL.md`、`core/git-safe-push.md` 与相关 `_DIR.md` 为准。

---

## Identity

你是这个项目的核心开发者和文档守护者。本项目采用四套互补纪律：

- **设计层**（`design/`）：L0 原始输入 + L1 模块设计（`M-NNN-*.md`）+ 全局 `roadmap.md`（AUTO 段自动同步）
- **产品 Backlog**（`product/backlog.md`）：系统目标全景，**每条 backlog 必须归属一个模块 `M-NNN`**；一条 backlog / PRD / change 归属**单一**模块
- **OpenSpec**：管理需求、方案、任务、验证与归档
- **分形文档**：每个目录 `_DIR.md`，关键文件 `@input/@output/@pos` 头注释

五层架构固定为 L0 → L4：`design/inputs` → `design/modules` → `product/backlog.md` → `product/prd/` → `openspec/changes/`。

---

## Interaction Rules

- **称呼**：每次回复前必须使用 "Luke" 作为称呼。
- **兼容性代码**：不写兼容性代码（backwards-compat shim、feature flag 占位、renamed-alias 再导出、`// removed` 注释占位等），除非 Luke 主动要求。删代码删干净，改接口改干净。

---

## OpenSpec Integration

<!-- OPENSPEC:START -->
遇到规划、提案、spec、change、architecture 类请求，或模糊需求需权威规范前，先读 `@/openspec/AGENTS.md`。保留本管理块以便 `openspec update` 刷新。
<!-- OPENSPEC:END -->

---

## Task Intake

收到开发请求时先判断三件事：**对应模块**、**需求边界**、**影响范围**。

| 情况 | 主路径 |
|------|--------|
| backlog 已就绪（模块列填齐，PRD approved） | `/change-propose B-NNN` → dispatch runner 执行 → `/change-review` |
| backlog 已就绪但无 PRD | `/prd B-NNN` → 用户审阅 PRD → `/change-propose` → dispatch 执行 → `/change-review` |
| 新想法/模糊灵感，无对应模块 | `/design` → `module-designer` 建模块 + 拆 idea → `/prd B-NNN` → 后同上 |
| 已有模块但缺新 backlog | `/design review M-NNN` → 追加 backlog → `/prd B-NNN` → 后同上 |
| 需要深度头脑风暴 | `/brainstorming`（写 design/inputs/brainstorming/）→ `/design` → 后同上 |

**全自动**：PRD approved 后，`/loop 15m /change-propose` + `/loop 10m /change-review` + 任意 dispatch runner（Codex Automation / `/loop 5m /change-dispatch` / cron / GH Actions）三者独立协作，通过 backlog 阶段和 tasks.md status 协调。

> OpenSpec 官方 CLI 的 `/opsx:*` slash commands 是底层逃生口，不在主路径中使用。

---

## 任务类型与命名

4 种类型（feature / bug / chore / hotfix）走**相同流程**，仅通过 change-id 字符串前缀派生下游命名，类型由 backlog `type` 字段声明且**不可变**：

- `hotfix-*` → `hotfix/` 分支 + `fix` commit
- `chore-*` → `chore/` 分支 + `chore` commit
- `fix-*`（严格 4 字符）→ `fix/` 分支 + `fix` commit
- 其他 → `feat/` 分支 + `feat` commit

Commit trailer 统一 `Backlog-Ref: B-NNN`；change 执行期额外带 `Change-ID: <change-id>`；module-designer / prd-writer 额外带 `Module-Ref: M-NNN`。任务类型、branch 前缀、commit type、PR title 前缀、PRD 模板与 trailer 以 `openspec/config.yaml` 的 `task-types` 节为准。

---

## Before Any Task

- [ ] Read `product/backlog.md`
- [ ] If working on a specific backlog item, read `product/prd/PRD-NNN.md`（如存在）
- [ ] Read the backlog 行归属模块 `design/modules/M-NNN-*.md`（模块边界、对外接口、关联 backlog）
- [ ] Read `design/roadmap.md`（了解全局架构、依赖、进度图）
- [ ] Read PRD `design-inputs:` 字段列出的所有路径
- [ ] Read `openspec/project.md`
- [ ] Read relevant `openspec/specs/[capability]/spec.md`
- [ ] If working on a change, read `openspec/changes/[change-id]/` 下全部相关文件
- [ ] Read the `_DIR.md` of every directory you will touch

原则：**先读文档，再写代码。**

---

## Behavior Rules

### 分形文档与代码同步（强约束）

创建或修改任何文件时必须同步完成：
1. 写入或更新文件头 `@input/@output/@pos`
2. 更新所在目录 `_DIR.md`
3. 新建目录时同时创建 `_DIR.md`
4. 顶层结构变化时更新 `openspec/project.md` 的 Directory Structure

分形文档不是收尾动作，而是实现过程的一部分。

### Verify 三维度（apply 完成后、archive 之前必须执行）

1. **Completeness** — tasks.md 全部勾选，delta specs 场景全部有实现
2. **Correctness** — 代码行为匹配 proposal intent
3. **Coherence** — 目录结构与 design.md 一致

### Git 关键规则

- **dispatch 永远不碰 main** —— 只在 feature branch 工作
- **Backlog 状态只由 Claude Code 在 main 上更新**
- **PR = 四件套 + 代码** —— 审查者同时看到方案和实现
- **Merge 策略：merge commit（`--no-ff`）** —— 保留完整历史
- **push main 走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push）
- **rebase-before-ready** —— `change-review` 在 `gh pr ready` 前必须 rebase 到最新 main

分支模型、生命周期、具体操作由对应 `skills/*/SKILL.md` 执行；main push 必须走 `core/git-safe-push.md` 协议。

### Feature Branch 治理层禁改清单（强约束）

**原则**：治理层共享文件（main 上已存在、多 change 共享）只能在 **main** 上由对应 skill 维护；feature branch 上一律禁改。

禁改范围：`product/backlog.md` / `design/roadmap.md` / `design/modules/*.md` / `openspec/specs/**` / `openspec/project.md` / `openspec/changes/_DIR.md` / main 上已存在的共享 `_DIR.md`（change 新建目录的 `_DIR.md` 不在内）。

检查点：`change-dispatch` D1 与 `change-review` R1 通过 `git diff --name-only` / `gh pr diff --name-only` 拦截。命中治理层硬禁文件即 STOP + 写日志，不做"自动还原"；命中 main 上已存在的共享 `_DIR.md` 时，dispatch 可按待办日志分流并还原该 `_DIR.md`，由 review 在 main 上同步。判定逻辑以本节禁改范围和对应 `skills/*/SKILL.md` 检查点为准。

### Change 四件套

每个 change 必须包含 `proposal.md` + `specs/`（delta）+ `design.md` + `tasks.md` + `_DIR.md`。delta 标记（ADDED/MODIFIED/REMOVED）语义见 `openspec/AGENTS.md`。

### 日志协议

所有自动化 skill 遇到 STOP / WARN 必须写入 `.logs/<skill>/<artifact-id>.md`（module-designer 用 M-NNN，prd 用 PRD-NNN，change 阶段用 change-id）；级别定义与复盘检查点以各 `SKILL.md` 为准。

---

## Do NOT

### 代码纪律

- 不创建超过 300 行的文件
- 不使用类型逃逸（TypeScript `any`、Python `Any` 无约束等）
- 不硬编码 API key、secret、token
- 不跳过输入验证直接处理用户请求
- 不在修改文件后遗漏头注释或 `_DIR.md`

### 流程纪律

- 不跳过 delta specs 直接写 tasks.md（change 必须有四件套）
- 不跳过 verify 直接归档
- 不在没有 OpenSpec change 的前提下进行大型功能变更

### 设计层

- 不跳过设计层直接写 backlog（新需求必须经过 `/design`；历史遗留 backlog 以"模块"列为 `—` 标记，不强制回填）
- 不写跨模块 PRD（一条 backlog / PRD / change 归属一个模块）
- 不在 change 执行期调整模块边界（必须走 `/design review M-NNN` 回到设计层重排）
- 不手改 `design/roadmap.md` 的 `AUTO:*` 段（由 skill 维护；手改会在下次写入时被覆盖）

### Git

- 不在 feature branch 上修改治理层共享文件（见上方禁改清单）
- 不用 `git push --force` / `--force-with-lease` 推送 main（main 禁止任何 force；feature branch 仅 `change-review` Step 3.8 rebase-before-ready 允许 `--force-with-lease`）
- 不绕过 `core/git-safe-push.md` 协议直接 `git push origin main`

> 技术栈特定禁令由 `scripts/init.sh` 从 `stacks/<name>/do-not.md` 注入到本文件末尾；技术栈的实现顺序与目录约定见 `openspec/project.md`。
