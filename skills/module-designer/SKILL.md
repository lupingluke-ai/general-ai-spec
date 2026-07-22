---
name: module-designer
description: Interactive AI skill (Claude Code or Codex) for designing product modules AND decomposing them into backlog idea entries in a single conversation. Reads design/inputs (brainstorming / figma / interviews), builds the module design document (modules/M-NNN-<slug>.md), splits the module into N backlog entries with auto-suggested types, and writes both the module and the decomposed backlog. Also syncs design/roadmap.md AUTO sections in real time. Use when the user wants to design a new module, revise an existing one, or decompose a big idea into actionable backlog entries.
---

# Module Designer

## Overview

把"模块设计"和"idea 拆分"合并到一次对话里完成。读设计输入（brainstorming / figma / 访谈）→ 与用户在对话收敛模块边界 → 自动拆分为 N 条 backlog idea（每条自动建议 type）→ 生成 module 文档 + 写入 backlog → 全量重渲染 roadmap。

**职责边界：** 只负责 L0→L1→L2 的设计层工作。PRD 生成由 `prd-writer`，技术规划由 `change-propose`，执行/审查由 `change-dispatch` / `change-review`。

**Announce at start:** "Running module-designer: designing module and decomposing into backlog."

## When to Use

- 用户说"帮我设计一个 XX 模块" / "帮我把这个想法拆一下"
- 用户触发 `/design "<主题>"`（新建模块）
- 用户触发 `/design M-NNN`（对已有模块增量更新）
- 用户触发 `/design review M-NNN`（复盘重排，允许较大幅度修改）
- 有新的 `design/inputs/**` 素材需要转化为模块+idea

## Bash 命令规范

1. **每条命令独立调用** — 不用 `&&`、`||`、`;` 串联
2. **管道可以用** — 如 `git log | head`
3. **并行无依赖时分开调用** — 多个独立 Bash tool call

## 输出物清单

单次运行产出（全部落 `main` 分支——设计层文档不走 feature branch）：

1. `design/modules/M-NNN-<slug>.md`（新建或增量更新）
2. `product/backlog.md`（新增 N 行 idea，含"模块"列 + 自动建议的 type）
3. `design/roadmap.md` 的 3 段 AUTO 区（ARCHITECTURE + DEPENDENCIES + PROGRESS）
4. `.logs/module-designer/M-NNN.md` 复盘日志

---

## Phase 0 — 同步远程

在读任何文件之前，先同步远程状态：

```bash
git checkout main
git pull origin main
```

**目的：**
- 保证 M-NNN / B-NNN 编号分配不冲突
- 保证读到最新的 backlog 和 roadmap
- 保证不在过时基线上设计

**失败处理：** 冲突时提示用户先解决再继续。

---

## Phase 1 — 输入定位

根据触发参数分派：

| 触发 | 动作 |
|---|---|
| `/design "<主题>"` | 新建模式：分配下一个 M-NNN，等 Phase 2 对话收敛 slug |
| `/design M-NNN` | 增量模式：读 `design/modules/M-NNN-*.md` 现状 |
| `/design review M-NNN` | 复盘模式：允许修改已有模块边界/依赖；禁止改已归档 backlog |

### M-NNN 分配（全局递增）

```bash
ls design/modules/ | grep -oE 'M-[0-9]+' | sort -Vu | tail -1
```

取最大值 +1；无已有模块时从 `M-001` 起。

### B-NNN 预分配（全局递增）

在 Phase 3 对话确定要拆几条 idea 后，按顺序从当前 backlog 最大 B-NNN 之后预留：

```bash
grep -oE 'B-[0-9]+' product/backlog.md | sort -Vu | tail -1
```

若无输出则从 `B-001` 起。初始化模板不得包含真实 `B-NNN` 占位编号，避免污染首次分配。

---

## Phase 2 — 上下文收集（必读）

读取以下内容，任一缺失走降级路径（见"降级策略"）：

1. `design/roadmap.md` — 现有架构视图
2. `design/modules/*.md` — 已有模块设计（避免边界重叠）
3. `design/inputs/**` — 所有原始输入
   - `brainstorming/` — 最新的相关灵感笔记
   - `figma/` — 原型链接与交互说明
   - `interviews/` — 用户访谈
   - 由用户在对话中指明要引用哪些，或自动取最新 7 天内与主题相关的
4. `product/backlog.md` — 已有 backlog（避免重复；增量模式下读已关联条目）
5. `openspec/specs/*.md` — 已有 specs（避免需求已被覆盖）

**降级策略：**
- `design/inputs/` 空 → 对话时主动追问 用户 "是否已经做过头脑风暴？内容在哪？" 补录到 `inputs/brainstorming/<date>-<topic>.md` 后继续
- `design/roadmap.md` 不存在 → 从 `templates/roadmap.md.tmpl` 复制一份后继续（首次使用场景）

---

## Phase 3 — 对话（模块设计 + idea 拆分合并进行）

**单次对话同时收敛两件事。** 不要分两次对话。

### 3.1 模块设计收敛

向用户提问/确认：

1. **模块定位**：解决什么问题、服务什么场景
2. **模块边界**：承担 / 不承担（明确 out of scope 避免蔓延）
3. **对外接口**：与其他模块 M-XXX 的交互点
4. **技术选型**：前端/后端/第三方的初步选型
5. **依赖关系**：`depends-on: [M-XXX]`
6. **status**：默认 `planning`；若已有 backlog 进入 exploring 则直接 `active`

### 3.2 idea 拆分（结构化评估）

**硬拆信号（必须拆）：**
- 跨越多个模块 → 当前 skill 内只能处理本模块范围；跨模块部分提示用户另开 `/design`
- 预估 FR（功能需求）> 8 条
- 包含多个独立用户价值（每个都能独立上线）
- 有明确的依赖序（先做 A 才能做 B）

**不拆信号（保持单条 backlog）：**
- 单一用户价值 + FR ≤ 8 + 技术边界清晰

**每条 idea 必须确定：**
- 需求描述（一句话）
- 归属模块：固定为当前 M-NNN（跨模块部分另开 /design）
- **type 自动建议**（feature / bug / chore / hotfix）
- 预估复杂度（S / M / L）
- 依赖（`depends-on: [B-XXX]`，可以是同一 /design 内的其他 idea 或已存在 backlog）

### 3.3 type 自动建议规则

按以下启发式为每条拆出的 idea 建议 type，用户在对话中确认：

| 信号 | 建议 type |
|---|---|
| 引入新能力 / 新页面 / 新业务流程 | `feature` |
| 修复既有行为偏差 | `bug` |
| 重构 / 升级依赖 / 构建配置 / 文档 | `chore` |
| P0/P1 线上紧急 | `hotfix` |

**默认 `feature`**；用户明确反对时切换。

### 3.4 对话终态

对话最终输出（用户一次性确认）：

```
M-NNN <模块名> (status: planning)
├── 定位/边界/接口/技术选型/依赖 已敲定
└── 拆出 N 条 idea：
    - B-XXX <描述>  [type]  [复杂度]  [depends-on]
    - B-YYY <描述>  [type]  [复杂度]  [depends-on]
    ...
```

用户确认后进入 Phase 4。中途发现需要调整的，循环回 3.1 / 3.2。

**禁止做的事：**
- 禁止跳过用户直接落盘
- 禁止一次对话处理多个模块（跨模块必须另开 `/design`）
- 禁止在 `review` 模式下删除已归档的 backlog

---

## Phase 4 — 生成 module 文档 + 落 backlog

**顺序：先写 module 文档 → 再写 backlog → 最后 roadmap（原子性先后）。**

### 4.1 写 design/modules/M-NNN-<slug>.md

从 `templates/module.md.tmpl` 派生：
- frontmatter：`id` / `slug` / `status` / `depends-on` / `design-inputs`（至少引用 Phase 2 实际读取的 inputs）
- `## 关联 Backlog` 小节：按 B-NNN 顺序列出本 /design 拆出的所有 idea，并保留 backlog 级依赖
  - 格式：`- B-NNN <需求描述> [depends-on: B-XXX, B-YYY | none]`
  - **不携带阶段标签**——阶段唯一存于 `product/backlog.md`，本小节只维护"归属关系 + 依赖"
- `## 拆分理由`：简要记录对话关键考虑（为什么拆成这 N 条、依赖关系为何如此）
- `## 修订历史`：首行写 `YYYY-MM-DD | 首次创建 | module-designer`

**增量模式（`/design M-NNN`）：**
- 保留现有 `## 关联 Backlog` 老行，只 append 新拆出的
- `## 修订历史` 追加一行

**review 模式（`/design review M-NNN`）：**
- 允许修改 frontmatter 的 `depends-on` / `design-inputs`
- 禁止删除 `## 关联 Backlog` 中已 `done` 的条目行（可改描述但不删行）

### 4.2 写 product/backlog.md

- 为每条 idea 分配全局递增 B-NNN
- 按模块分节。若 `## 模块：M-NNN <名>` 小节不存在则新建；存在则 append
- 每行格式：

```markdown
| B-NNN | <需求描述> | M-NNN | <type> | idea | — | — | <备注，空> |
```

- backlog 级 `depends-on` 关系**不进 backlog 表**；落在本次拆出的 idea 之间或指向既有 backlog 的依赖，由 PRD 的 `depends-on` 字段在 prd-writer 阶段写入。本 skill 必须先记录到 module 文档 `## 关联 Backlog` 行尾的 `[depends-on: ...]` 中，prd-writer 读取时再消费。

### 4.3 历史兼容

- 不强制回填已存在 backlog 的"模块"列。只新建行填模块。
- 老 backlog 若未来要补模块，人工手改或 `/design review M-NNN` 时在对话中追加。

---

## Phase 5 — 重渲染 design/roadmap.md AUTO 段

**三段 AUTO 区全部从事实源全量重渲染**（渲染规则见 `core/git-safe-push.md` 的"AUTO 段重渲染"；所有写 main 状态的 skill 使用同一规则），用 markdown 注释边界精确定位，不动人工段：

### 5.1 AUTO:ARCHITECTURE

位于 `<!-- AUTO:ARCHITECTURE_START -->` 和 `<!-- AUTO:ARCHITECTURE_END -->` 之间。

遍历 `design/modules/*.md` 的 frontmatter，整段重写为模块表。行格式：

```markdown
| M-NNN | <模块名> | <status> | [M-NNN](./modules/M-NNN-<slug>.md) | <depends-on 列表> | <created> |
```

### 5.2 AUTO:DEPENDENCIES

位于 `<!-- AUTO:DEPENDENCIES_START -->` 和 `<!-- AUTO:DEPENDENCIES_END -->` 之间。

由各模块 frontmatter 的 `depends-on` 整段重写为邻接表：

```
M-001 → (无)
M-002 → M-001
M-003 → M-001
M-004 → M-002, M-003
```

### 5.3 AUTO:PROGRESS

位于 `<!-- AUTO:PROGRESS_START -->` 和 `<!-- AUTO:PROGRESS_END -->` 之间。

遍历 `product/backlog.md`，按模块分节整段重写。每条 backlog 一行，格式：

```markdown
### M-NNN <模块名>
- 💡 B-XXX <需求描述>
- 🔎 B-YYY <需求描述>
...
```

阶段图标按 backlog 阶段列映射：`💡 idea | 🔎 exploring | 📝 proposed | ✅ done`（backlog 4 阶段；执行细粒度看 tasks.md status）

> **重渲染即幂等**：AUTO 段是 backlog + modules 的派生视图，不存储独立状态。无需"每个 skill 只改自己那行"的行级并发约定——并发冲突时任取一侧后重新渲染即可（见 git-safe-push）。

---

## 复盘检查点 — 设计一致性

Phase 5 完成后、Commit 前，**必须**执行以下交叉验证。

**日志写入是硬性要求：** 发现任何偏离（硬偏离或软偏离）时，**先写入** `.logs/module-designer/M-NNN.md`，**再**修正。无偏离时写一行 "复盘通过，无偏离" 作为执行凭证。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|---|---|---|
| P1 | 所有新建 B-NNN 的"模块"列均 = M-NNN | 扫 backlog 新增行 | 一致性偏离 |
| P2 | module frontmatter 的 `depends-on` 中每个 M-XXX 在 roadmap AUTO:ARCHITECTURE 段存在 | 交叉比对 | 一致性偏离 |
| P3 | 模块依赖无环 | 构建邻接表做拓扑排序 | 硬偏离 |
| P4 | 每条新建 idea 至少可追溯到一个 `design-inputs` 路径 | 对比 Phase 2 读到的输入 | 范围偏离 |
| P5 | `## 关联 Backlog` 的 B-NNN 列表 = `product/backlog.md` 中该模块下本次新增的 B-NNN 集合 | 两处集合对比 | 一致性偏离 |
| P6 | 重渲染后的 AUTO:PROGRESS 段与 backlog 全量一致（每条 B-NNN 一行、图标与阶段列匹配） | 渲染结果与 backlog 逐行比对（渲染是全量的，可直接全局比对） | 一致性偏离 |
| P7 | 每条新建 idea 的 `depends-on` 对话结果已写入 module `## 关联 Backlog` 行尾 | 对比 Phase 3.4 确认结果与 module 行尾 `[depends-on: ...]` | 一致性偏离 |

**偏离处理：**
- **硬偏离**（P3 环依赖）→ 停止写入，回 Phase 3 让用户调整依赖后重跑
- **软偏离**（P1/P2/P5/P6/P7 数值不一致）→ 写日志 → 自动对齐
- **范围偏离**（P4 找不到 inputs 追溯）→ 写日志 + 在 `## 修订历史` 注明"缺 inputs 追溯"+ 继续（不阻塞，用户可补录 inputs）

---

## Phase 6 — Commit + Push

**在 `main` 分支**直接提交（设计层文档不走 feature branch）：

```bash
git add design/modules/M-NNN-<slug>.md
git add design/roadmap.md
git add product/backlog.md
git add .logs/module-designer/M-NNN.md
```

```bash
git commit -m "design(M-NNN): <模块名> + N backlog ideas

Module-Ref: M-NNN
Status: planning
Backlogs: B-XXX, B-YYY, ..."
```

**推送走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push + 分段冲突策略）：

```bash
# Round 1
git push origin main
# 被拒 → git pull --rebase origin main → 回到 push
# rebase 冲突：
#   - product/backlog.md 新增行冲突（多 skill 同时落 idea）→ 按 B-NNN 升序合并
#   - design/roadmap.md AUTO 段 → 任取一侧后从 backlog + modules 全量重渲染
#   - design/modules/*.md 同模块并发编辑 → frontmatter status 取新、关联 Backlog / 修订历史按主键合并
#   - 模块边界 / 技术选型段冲突 → STOP + 日志（需用户确认设计意图）
# 3 轮仍失败 → STOP，写日志到 .logs/module-designer/M-NNN.md
```

**编号碰撞防护（每轮 rebase 后必须执行）：** 并发的两个 `/design` 会话可能各自基于同一快照分配相同的 M-NNN / B-NNN（行级合并不会将其识别为冲突，会导致同号双义）。每轮 `git pull --rebase` 成功后、重试 push 前：

1. 重扫远端合入的 `design/modules/` 与 `product/backlog.md`
2. 若本次分配的任一 M-NNN / B-NNN 已被**不同内容**的条目占用 → 本侧全部顺移重编号（新 max +1 起），同步更新：module 文档（含文件名）、backlog 行、roadmap 渲染，**以及所有指向被重编号 ID 的引用**（module `## 关联 Backlog` 行尾 `[depends-on: B-XXX]`、idea 之间的依赖关系）
3. 写 WARN 日志（类型：编号碰撞重编）→ 重试 push

> PRD-NNN 与 B-NNN 一一映射、change-id 由 prd-writer 生成并做唯一性检查，因此编号防护只需覆盖 M/B 两个分配点。

> commit 首词用 `design`（与 `feat|fix|chore|docs` 并列，语义为"设计层变更"）。

---

## 输出给 用户

完成后输出一段简报：

```
✅ M-NNN <模块名> 设计完成
   - 文档：design/modules/M-NNN-<slug>.md
   - 拆出 N 条 idea：B-XXX, B-YYY, ...
   - roadmap 已同步（architecture / dependencies / progress）
   - 下一步：/prd B-XXX 开始 PRD 对话
```

---

## 失败恢复

| 失败场景 | 恢复策略 |
|---|---|
| Phase 0 git pull 冲突 | 提示用户先 merge/rebase |
| Phase 3 用户未确认即中断 | 不写任何文件，下次重跑 |
| Phase 4 写 backlog 后写 roadmap 失败 | 已写的 backlog 保留；下次 `/design review M-NNN` 会补齐 roadmap |
| Phase 5 AUTO 段标记缺失 | 检测不到边界时用 `templates/roadmap.md.tmpl` 的标记原样注入（保持幂等） |
| Phase 6 push 被拒（远程有新 commit）| 走 `core/git-safe-push.md`（3 轮 pull-rebase-push + 分段冲突策略）；3 轮失败 STOP 写 `.logs/module-designer/M-NNN.md` |

---

## 与其他 Skill 的交接

| 下游 Skill | 交接物 | 交接方式 |
|---|---|---|
| `prd-writer` | 每条新建 B-NNN 的"模块"列 + `design/modules/M-NNN-*.md` 存在 | PRD frontmatter 的 `module-ref` 直接读 backlog 该列 |
| `change-propose` | 模块设计文档（给 proposal.md 引用产品语境）| 不直接交互，通过 PRD 的 `design-inputs` 间接引用 |
| `change-review` | module 生命周期（active → done 由归档最后一条触发）| review 归档时检查本模块关联 backlog 是否全 done |

---

## 不做的事（Do NOT）

- ❌ 不生成 PRD（那是 prd-writer 的职责）
- ❌ 不生成四件套（那是 change-propose 的职责）
- ❌ 不跨模块拆分 idea（遇到跨模块时提示用户另开 /design）
- ❌ 不在 feature branch 操作（设计层一律落 main）
- ❌ 不删除已 done 的 backlog 行
- ❌ 不覆盖 roadmap 的人工段（只动 AUTO:* 段）
- ❌ 不自动触发 /prd（用户读完简报后手动发起）
