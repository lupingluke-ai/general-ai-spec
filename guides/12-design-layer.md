# 设计层：从灵感到模块化 Backlog

本指南覆盖 `design/` 目录的职责、`module-designer` skill 的使用路径、以及设计层与下游（backlog / PRD / change）的衔接。

---

## 为什么要设计层

在加入设计层之前，所有需求直接以 `B-NNN` 的形式录入 `product/backlog.md`。这种方式在需求量小时可控，但一旦规模扩大就暴露三个问题：

1. **缺少"模块"这一中间抽象**——散落的 backlog 条目无法回答"系统由哪些模块组成"
2. **灵感到可执行 backlog 之间的收敛过程没有沉淀**——brainstorming / figma / 访谈的原始信息散落各处
3. **跨 backlog 的依赖和边界难以追踪**——change-propose 阶段频繁出现"scope 越界"

设计层用 3 个抽象解决这些问题：

| 层 | 路径 | 职责 |
|---|---|---|
| **L0 原始输入** | `design/inputs/` | brainstorming / figma / interviews 等原始资产，纯人工录入永久保留 |
| **L1 模块设计** | `design/modules/M-NNN-*.md` | 模块边界、对外接口、技术选型、关联 backlog，由 `module-designer` 生成和维护 |
| **全局蓝图** | `design/roadmap.md` | 愿景 + 架构 + 依赖 + 进度四合一，AUTO 段从 backlog + modules 全量重渲染 |

每条 backlog 必须归属一个模块（`M-NNN`）。每个 PRD 必须引用模块文档。这把"一条 idea"锚定到系统结构上，change-propose 就可以以模块边界为范围约束。

---

## 五层架构全景

```
L0 design/inputs/         ← 人工录入（brainstorming / figma / interviews）
      │
      ▼ module-designer（/design）
L1 design/modules/        ← 模块边界 + 对外接口 + 关联 backlog
      │
      ▼ module-designer 同步拆 idea
L2 product/backlog.md     ← B-NNN + 模块列 = M-NNN + 阶段 = idea
      │
      ▼ prd-writer（/prd B-NNN）
L3 product/prd/PRD-NNN.md ← 引用模块文档 + design-inputs
      │
      ▼ change-propose
L4 openspec/changes/      ← 四件套 + feature branch + Draft PR
      │
      ▼ change-dispatch + change-review
完成
```

**横切全景**：`design/roadmap.md` 的三段 AUTO 区：

| AUTO 段 | 内容 | 维护方 |
|---|---|---|
| `AUTO:ARCHITECTURE` | 模块清单（ID / 名 / 状态 / 依赖） | 从 `design/modules/*.md` frontmatter 全量重渲染 |
| `AUTO:DEPENDENCIES` | 模块依赖图（ASCII 或邻接表） | 从模块 `depends-on` 全量重渲染 |
| `AUTO:PROGRESS` | 按模块分组的 backlog 进度 | 从 `product/backlog.md` 全量重渲染 |

任何写 main 状态的 skill 都使用同一套渲染规则；AUTO 段是派生视图，不是独立事实源。

---

## 目录结构

```
design/
├── _DIR.md                     ← 设计层总说明
├── roadmap.md                  ← 全局蓝图（人工段 + AUTO 段混合）
├── inputs/
│   ├── _DIR.md
│   ├── brainstorming/          ← 头脑风暴笔记
│   ├── figma/                  ← figma 链接 + 截图说明
│   └── interviews/             ← 用户访谈记录
└── modules/
    ├── _DIR.md
    ├── M-001-chat-assistant.md ← 模块设计文档
    ├── M-002-voice-entry.md
    └── ...
```

---

## 模块生命周期

```
planning ──► active ──► done
              │
              └──► deprecated（人工显式标记）
```

| 状态 | 含义 | 谁回写 | 触发条件 |
|---|---|---|---|
| `planning` | 模块刚建，尚无 backlog 进入 exploring | `module-designer` | 首次建模块时 |
| `active` | 至少一条关联 backlog 进入 exploring+ | `prd-writer` | 首次激活（把模块首条 backlog 推进到 exploring）|
| `done` | 所有关联 backlog 已 done | `change-review` | 归档最后一条 backlog 时判定 |
| `deprecated` | 模块废弃，新需求不再落入 | 人工 | `/design review M-NNN` 显式标记 |

---

## 典型操作路径

### 路径 A：新灵感 → 新模块（冷启动）

```
你：/design
  ↓
交互式 agent：（启动 module-designer）
  - 扫描 design/inputs/ 发现新素材
  - 读 design/roadmap.md 了解既有架构
  - 与你对话：这个灵感属于新模块还是已有模块？边界如何划？
  ↓
module-designer 落盘：
  - 新建 design/modules/M-NNN-<slug>.md（status: planning）
  - 同步把 idea 拆到 product/backlog.md（N 条 B-NNN，阶段: idea，模块列: M-NNN）
  - 更新 design/roadmap.md 的 AUTO:ARCHITECTURE / AUTO:DEPENDENCIES / AUTO:PROGRESS
  - commit: design(M-NNN): <模块名> + N backlog ideas
```

### 路径 B：老模块追加需求

```
你：/design review M-002
  ↓
交互式 agent：（module-designer 增量模式）
  - 读 M-002 模块文档 + 关联 backlog
  - 与你对话：追加哪些需求？是否需要扩边界？
  ↓
module-designer 落盘：
  - 更新 M-002 的 "## 关联 Backlog" 小节
  - 在 backlog 追加新行
  - 从 backlog + modules 全量重渲染 roadmap 三段 AUTO 区
```

### 路径 C：brainstorming 优先

```
1. 在 design/inputs/brainstorming/<topic>.md 写灵感（纯人工）
   或：使用 /brainstorming skill 生成
2. /design
   → module-designer 自动读取 inputs/ 作为素材
```

### 路径 D：历史项目迁入（不强制回填）

历史 backlog（无"模块"列或标记为 `—`）不强制回填模块。自动化 skill 对这些行：

- `prd-writer`：Step 2.2 module-ref 必填校验时提示用户补齐，否则拒绝生成 PRD
- `change-propose`：Phase 0 筛选时跳过并写日志
- `change-review`：Step 6.3.2 跳过模块文档同步，但仍全量重渲染 roadmap
- `module-designer`：`/design review M-NNN` 时可以把历史条目追加到"## 关联 Backlog"，完成手工补录

---

## 维护边界

| 文件 | 维护方 | 说明 |
|---|---|---|
| `design/_DIR.md` | 人工 | 设计层总说明，偶尔更新 |
| `design/roadmap.md`（人工段：愿景 / 原则 / 里程碑） | 人工 | 季度重审 |
| `design/roadmap.md`（AUTO 段） | 写 main 状态的 skill | 从事实源全量重渲染，**勿手改** |
| `design/inputs/**` | 人工 | 原始设计资产永久保留，skill 只读 |
| `design/modules/M-NNN-*.md`（frontmatter / 人工段） | `module-designer` | 建模块 + `/design review` |
| `design/modules/M-NNN-*.md` 的 `## 关联 Backlog` | `module-designer` | 维护归属和 backlog 级依赖，不保存阶段 |
| `design/modules/M-NNN-*.md` 的 `## 修订历史` | 多个 skill | 按各阶段追加历史记录 |

---

## 并发写入约定

`design/roadmap.md` 的 AUTO 段不做行级多写者合并：

1. 先合并事实源：`product/backlog.md` 按 B-NNN、`design/modules/*.md` 按 M-NNN / frontmatter / 修订历史处理冲突
2. AUTO 段冲突任取一侧
3. 从合并后的 backlog + modules 重新全量渲染三段 AUTO 区
4. 保留 AUTO 边界外的愿景、原则、里程碑等人工内容

因为派生视图可以重建，所以不再依赖“每个 skill 只改自己那一行”的脆弱约定。具体渲染与 rebase 规则见 `core/git-safe-push.md`。

---

## Commit 前缀登记

| 前缀 | 产出 skill | 示例 |
|---|---|---|
| `design(M-NNN): ...` | `module-designer` | `design(M-001): chat-assistant + 3 backlog ideas` |
| `docs(PRD-NNN): ...` | `prd-writer` | `docs(PRD-003): draft PRD for B-003` |
| `<type>(<change-id>): ...` | `change-propose/dispatch/review` | `feat(chat-ui-basic-route): apply proposal` |

所有设计层 / 产品层 / change 层 commit 都应包含 `Module-Ref: M-NNN` trailer，便于 `git log --grep='Module-Ref: M-NNN'` 拉出某模块完整开发历史。

---

## 复盘与日志

`module-designer` 运行时可能触发的偏离写到 `.logs/module-designer/<M-NNN>.md`：

- **范围偏离**：idea 落在了与 module 边界不一致的承担项上
- **并发偏离**：事实源发生编号碰撞或无法按主键自动合并
- **拆分偏离**：idea 粒度与"独立用户价值"原则冲突

偏离处理策略见 `skills/module-designer/SKILL.md` 复盘检查点。

---

## 常见问题

### Q: 设计层是否可以跳过？

不建议。新需求必须经过 `/design` 至少一次（即使只是增量 `/design review`）来保证"模块列"填齐。历史遗留 backlog 不强制，但自动化 skill 会跳过这些行的模块/roadmap 同步。

### Q: 一个 backlog 可以属于多个模块吗？

不行。`1 backlog : 1 模块` 是硬约束。如果需求同时覆盖多个模块，应该拆成多条 backlog 分别归属。跨模块 PRD 同样被禁止。

### Q: 模块边界调整怎么处理？

小幅调整：`prd-writer` / `change-propose` 对话中发现需要扩边界 → 回到 `/design review M-NNN` 调整 module 文档 → 回到原 skill 继续。

大幅越界：本质上这条需求属于另一个模块 → 拒绝当前对话 → 拆到新 backlog 挂到对应模块。

**硬约束**：不在 change 执行期调整模块边界（必须回到设计层重排）。

### Q: 模块 status 的状态机在哪里实现？

分布在三个 skill 中，通过读 backlog 当前状态反向推导，无共享可变状态：

- `module-designer` 首次建模块：`— → planning`
- `prd-writer` 首次激活：读 backlog 所有该模块的行，若除当前 B-NNN 外其余都在 idea，本次推进即首次激活，`planning → active`
- `change-review` 归档时：读 backlog 所有该模块的行，若全部 done，`active → done`

### Q: `/design` 和 `/brainstorming` 的关系？

- `/brainstorming` 是上游：产出原始灵感写到 `design/inputs/brainstorming/`
- `/design` 是下游：消费 inputs/ 素材，产出模块 + backlog

可以先 `/brainstorming` 再 `/design`，也可以直接 `/design`（module-designer 会提示用户是否需要先录入灵感）。

---

## 与其他指南的关系

- `guides/02-backlog.md` — backlog 的"模块"列如何使用
- `guides/03-prd.md` — PRD 如何引用模块文档 + design-inputs
- `guides/04-propose.md` — change-propose 如何校验模块边界
- `guides/09-git-github-workflow.md` — commit 前缀登记
- `skills/module-designer/SKILL.md` — module-designer 的完整技术规约
