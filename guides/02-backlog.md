# 管理产品 Backlog

## 位置

`product/backlog.md` — 所有开发工作的源头。每一条 backlog 必须归属一个模块（由 `module-designer` 分配 `M-NNN`）。

## 格式

按模块分节，每个模块一个表格；表格含"模块"列与"type"列：

```markdown
## 模块：M-001 记账核心

| ID | 需求 | 模块 | 类型 | 阶段 | PRD | Change | 备注 |
|---|---|---|---|---|---|---|---|
| B-001 | 手动记账（收入/支出） | M-001 | feature | done    | PRD-001 | manual-entry  | MVP |
| B-002 | 多账本管理            | M-001 | feature | done    | PRD-002 | multi-ledger  | |
| B-003 | AI 语音快速记账       | M-002 | feature | idea    | —       | —             | depends-on B-001 |
| B-004 | AI 截图识别记账       | M-003 | feature | idea    | —       | —             | |

## 模块：— 未归类

| ID | 需求 | 模块 | 类型 | 阶段 | PRD | Change | 备注 |
|---|---|---|---|---|---|---|---|
| B-999 | 历史遗留条目 | — | chore | idea | — | — | 可通过 /design review 追加模块 |
```

**"模块"列规则**：
- 新条目必须填 `M-NNN`，由 `module-designer` 在 `/design` 对话中分配
- 历史遗留条目可以保持 `—`（"未归类"节），自动化 skill 会跳过模块/roadmap 同步
- 不强制回填；迁入历史项目时保持现状即可

**"type"列规则**：
- feature / bug / chore / hotfix 四选一，由 `module-designer` 根据对话信号自动建议
- type 不可变；一经录入直至归档保持一致
- 详细语义见 [11-task-types.md](./11-task-types.md)

## 阶段说明

| 阶段 | 含义 | 谁触发 | 何时触发 |
|------|------|--------|----------|
| **idea** | 初步想法 | `module-designer` / 人工补录 | 使用 `/design` 建模块 + 拆 idea 时 |
| **exploring** | 调研中，PRD 生成中 | `prd-writer` | 使用 `/prd B-NNN` 时（同步首次激活模块 status: planning → active）|
| **proposed** | 已拆分为 change | `change-propose` | 四件套 + Draft PR 落盘后 |
| **done** | 已归档 | `change-review` | 合并前 Verify 通过、实现 PR 合并且 archive governance PR 生效后（若为模块最后一条，同步 active → done）|

> backlog 只保留 4 个"有明确写入者"的阶段（`idea / exploring / proposed / done`）。执行中 / 审查中的细粒度（dispatch 领取、组完成、PR review）由 `tasks.md` YAML 头的 `status` 字段（`draft / ready / executing / review / done`）承担——dispatch 禁碰 main 治理层，无法把细粒度反映到 backlog。

## 操作流程

### 1. 通过 `/design` 建模块 + 拆 idea（推荐路径）

```
你：/design
  或
你：/design review M-002        ← 追加到已有模块
  ↓
交互式 agent：（启动 module-designer）
  - 扫描 design/inputs/ 与 roadmap
  - 与你对话：建新模块还是挂老模块？划哪些 idea？type 是什么？
  ↓
module-designer 一次性落盘：
  - design/modules/M-NNN-<slug>.md（status: planning）
  - product/backlog.md 新增 N 条 B-NNN（阶段: idea，模块列: M-NNN）
  - design/roadmap.md 的 AUTO 段同步
```

**规则（module-designer 内部强校验）：**
- ID 格式为 `B-NNN`，全局唯一递增
- 每条需求"可独立交付"，大需求在对话中被拆分（硬拆信号见 module-designer SKILL）
- 阶段初始为 `idea`；"模块"列强制填 `M-NNN`
- type 由 module-designer 根据对话信号自动建议（默认 feature，bug/chore/hotfix 对应语义信号）

### 1'. 手动补录（仅历史项目迁入）

直接编辑 `product/backlog.md` 是允许的，但推荐只用于历史迁入：

```markdown
| B-999 | 历史遗留条目 | feature | — | idea | — | — | |
```

这种条目的"模块"列为 `—`，自动化 skill 会跳过模块/roadmap 同步。后续可通过 `/design review M-NNN` 将其追加到具体模块完成补录。

### 2. 生成 PRD（推荐）

需求不够清晰时，先生成 PRD：

```
你：帮我分析 B-005 的需求
交互式 agent：（使用 prd-writer 与你对话，澄清需求）
→ 生成 product/prd/PRD-005.md (status: reviewing)
→ backlog B-005 阶段更新为 exploring，PRD 列更新为 PRD-005
```

### 3. 审阅 PRD

```
你：看过了，approved
交互式 agent：PRD-005 status → approved
```

详细的 PRD 流程见 [03-prd.md](./03-prd.md)。

### 4. 触发规划

PRD approved 后，告诉 Claude Code 或 Codex：

```
你：基于 B-005 开始规划
交互式 agent：（读取 PRD-005 → 使用 change-propose 生成四件套）
→ backlog B-005 阶段更新为 proposed，关联 change-id
```

### 5. 自动执行

无需手动操作。dispatch runner（Codex Automation / `/loop <interval> /change-dispatch` / cron / GH Actions 任选其一）按配置间隔自动扫描：

```
change-dispatch 自动领取 → worktree 执行 → 完成后标记 review
→ backlog B-005 阶段保持 proposed（dispatch 不碰 main；细粒度看 tasks.md status）
```

### 6. 审查归档

dispatch 执行完成后，触发审查：

```
你：审查已完成的 change
交互式 agent：（使用 change-review 审查、合并、验证、归档）
→ backlog B-005 阶段更新为 done
```

## 拆分策略

**绑定约束（硬规则）**：`1 backlog : 1 PRD : 1 change-id : 1 模块`。

需要拆分工作量时，在 backlog 层新开 B-NNN，每条各自归属一个模块、各自走独立的 PRD → change 闭环：

```markdown
| B-003 | AI 语音记账 - 基础设施 | M-002 | feature | proposed | PRD-003 | ai-voice-infra | MVP |
| B-004 | AI 语音记账 - UI 输入   | M-002 | feature | idea     | —       | —              | depends-on B-003 |
| B-005 | AI 语音记账 - 历史集成 | M-002 | feature | idea     | —       | —              | depends-on B-003 |
```

拆分由 `module-designer` 在 `/design` 对话中完成（不再由 prd-writer 承担）。拆分信号：

- 需求包含多个独立用户价值 → 必须拆分
- 子需求之间有依赖序 → 必须拆分并标注 `depends-on`
- 预估功能需求 > 8 条 → 考虑拆分
- 跨越多个模块边界 → 必须按模块拆分

## 注意事项

- Backlog 由 `module-designer` 新建、`prd-writer` / `change-propose` / `change-review` 按阶段更新
- 不要删除已完成的条目，保留完整历史
- "模块"列记录 `M-NNN`，历史遗留为 `—`（自动化 skill 跳过同步）
- PRD 列记录关联的 PRD-NNN（严格 1:1）
- Change 列记录唯一的 change-id（严格 1:1）
- 需要拆分工作量时，回到 `/design` 由 `module-designer` 驱动，不在同一条 backlog 下塞多个 change
- backlog 条目的关联 change 归档后标记 `done`；模块最后一条 done 时，模块 status 同步 `active → done`
