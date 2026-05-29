---
name: prd-writer
description: Interactive AI skill (Claude Code or Codex) for generating Product Requirements Documents (PRDs). Takes a backlog entry (already tagged with a module) and produces a structured PRD through user dialogue, grounded in the module design document and referenced design inputs. Use when the user wants to explore, analyze, or define requirements for a backlog item.
---

# PRD Writer

## Overview

将 backlog 中的一行想法转化为结构化的产品需求文档（PRD）。读取该 backlog 条目归属的模块设计 + design-inputs，与用户对话澄清边界，生成覆盖用户故事、功能需求、验收标准的完整 PRD。

**职责边界：** 只负责单条 backlog → PRD。拆分工作由 `module-designer` 在 /design 对话中完成，本 skill 不再做粒度评估。技术规划由 `change-propose`，执行/审查由 `change-dispatch` / `change-review`。

**Announce at start:** "Running prd-writer: drafting PRD for B-NNN."

## When to Use

- 用户说"帮我分析 B-NNN 的需求"
- 用户触发 `/prd B-NNN`
- backlog 条目处于 `idea` 阶段，`模块` 列已填写（由 `module-designer` 产出），需要生成 PRD

## Bash 命令规范

1. **每条命令独立调用** — 不用 `&&`、`||`、`;` 串联
2. **管道可以用** — 如 `grep -c 'B-' product/backlog.md`
3. **并行无依赖时分开调用**

## 输出物清单

单次运行产出（全部落 `main` 分支）：

1. `product/prd/PRD-NNN.md`（新建，首次 `status: reviewing`；Luke approved 后改为 `approved`）
2. `product/backlog.md`（目标 B-NNN 阶段 idea → exploring，PRD 列写入 PRD-NNN）
3. `design/modules/M-NNN-*.md`（`## 关联 Backlog` 小节更新该行阶段；`status: planning → active` 当且仅当本 skill 首次将该模块的任一 backlog 推进到 exploring）
4. `design/roadmap.md` 的 `AUTO:ARCHITECTURE` 段（若 module status 变化）+ `AUTO:PROGRESS` 段（目标行 💡 → 🔎）

---

## Step 1 — 同步远程

```bash
git checkout main
git pull origin main
```

**目的：**
- 读到最新 backlog 与 module 文档
- PRD-NNN 编号分配不冲突
- 不在过时基线上做产品决策

**失败处理：** 冲突时提示 Luke 先解决再继续。

---

## Step 2 — 读取 Backlog 与上下文

### 2.1 定位 Backlog 条目

从 `product/backlog.md` 读取目标 `B-NNN` 行，解析：
- 需求描述
- 归属模块（"模块"列的 `M-NNN`）— **必填字段**
- type
- 阶段（应为 `idea`；若已 `exploring` 且 PRD 文件存在，视为增量对话）

### 2.2 module-ref 必填校验

若"模块"列为 `—` 或空：

- **历史遗留 backlog**（启用本框架前创建的）→ 提示 Luke 给这条 backlog 补模块归属：要么手工改 backlog 该列，要么通过 `/design review M-NNN` 把它追加到模块的 `## 关联 Backlog`
- **新条目漏填** → 提示 Luke 回 `/design` 重新落盘（通常说明 module-designer 流程被绕过）

补齐前**不生成 PRD**。

### 2.3 必读上下文（硬性要求）

| 路径 | 用途 |
|---|---|
| `design/modules/<M-NNN>-*.md` | **必读** — 模块边界、对外接口、技术选型。PRD 范围必须落在模块边界内 |
| `design/modules/<M-NNN>-*.md` 的 `## 关联 Backlog` 小节 | **必读** — 本 B-NNN 的 `depends-on` 注释（module-designer 在对话中记录的依赖关系） |
| `design/inputs/**` | 必读 — module 文档 `design-inputs` 字段列出的所有路径 |
| `openspec/project.md` | 必读 — 技术栈约束 |
| `openspec/specs/` | 扫描 — 已有系统行为，避免需求冲突 |
| 相关代码 | 按需 — 评估现状时读 |

### 2.4 模板选择（按 type）

| type | 模板 |
|------|------|
| `feature` | `templates/prd.md.tmpl`（Full）|
| `bug` / `chore` / `hotfix` | `templates/prd-lite.md.tmpl`（Lite）|

**硬性要求：**
- 生成的 PRD frontmatter 必须写 `type: <type>`，与 backlog 一致
- 必写 `module-ref: <M-NNN>`，与 backlog 的"模块"列一致
- 必写 `design-inputs:`，至少包含 `design/modules/<M-NNN>-<slug>.md`（模块文档强制引用）；其余 input 可按对话需要追加
- Lite PRD 的 Must Have ≥ 1；AC 数 ≥ 预估 delta specs 场景数

---

## Step 3 — 对话澄清（边界受模块约束）

与 Luke 对话，澄清：

- **feature**：用户故事 / Must Have / Nice to Have / Out of Scope
- **bug / hotfix**：现象 / 根因 / 预期行为 / 回归场景
- **chore**：动机 / 目标状态 / 影响面

**约束**：对话推导的需求不得越出 module 文档的"承担"边界；越界时有两种处理：
1. **小幅调整** → 主动提示 Luke"要不要扩展 M-NNN 的边界？"，调整后先走 `/design review M-NNN` 再回本 skill
2. **大幅越界** → 拒绝对话，提示 Luke"这条需求本质上属于另一个模块，建议拆到新 backlog 并挂到对应模块"

`depends-on` 字段：优先采用 module-designer 在 `## 关联 Backlog` 记录的依赖；Luke 若在对话中提及新的前置依赖（跨模块 backlog），追加到 PRD frontmatter 的 `depends-on` 列表。

---

## Step 4 — 生成 PRD

写入 `product/prd/PRD-NNN.md`：

- PRD-NNN 编号：从 backlog ID 直接映射（`B-003` → `PRD-003`），确保 1:1 可追踪
  ```bash
  printf '%s\n' "B-NNN" | sed 's/^B-/PRD-/'
  ```
  若目标 `product/prd/PRD-NNN.md` 已存在，则进入增量对话或状态更新，不新分配编号。
- frontmatter 按 Step 2.4 的硬性要求填齐
- `status: reviewing`
- 正文按对应模板结构填充

---

## Step 5 — 更新 Backlog

`product/backlog.md` 中 `B-NNN` 行：
- `阶段` 列：`idea → exploring`
- `PRD` 列：`— → PRD-NNN`
- 其他列保持

---

## Step 6 — 更新 Module 文档与 Roadmap（实时同步）

### 6.1 更新 `design/modules/<M-NNN>-*.md`

- `## 关联 Backlog` 小节中对应 B-NNN 行的阶段标记 `[idea] → [exploring]`
- `## 修订历史` 追加一行 `YYYY-MM-DD | B-NNN 进入 exploring | prd-writer`
- **若该模块之前所有 backlog 都在 idea**，本次推进意味着模块"首次激活"：
  - frontmatter `status: planning → active`
  - `## 修订历史` 额外记录 `YYYY-MM-DD | 模块激活（B-NNN 进入 exploring）| prd-writer`

判定模块是否"首次激活"的方法：读 `product/backlog.md` 中所有归属该模块的 backlog 行，若除当前 B-NNN 外其余都在 `idea`（或列表为空），则本次推进即首次激活。

### 6.2 更新 `design/roadmap.md`

**仅在 module status 变化时**更新 `AUTO:ARCHITECTURE` 段的对应行（status 列）。边界由 `<!-- AUTO:ARCHITECTURE_START -->` / `<!-- AUTO:ARCHITECTURE_END -->` 注释包裹。

**每次都更新** `AUTO:PROGRESS` 段：
- 找到对应模块的 `### M-NNN <模块名>` 小节
- 将该 B-NNN 行的图标从 `💡 idea` 改为 `🔎 exploring`
- **非本行保持原样**，尤其非 idea/exploring 阶段的行（`change-propose` / `change-review` 会维护那些）

**AUTO 段并发约定（本 skill 负责）：**
- 只改本次 B-NNN 对应行（idea → exploring）
- 读取全量 → 局部替换 → 写回
- 遇到其他阶段或其他 backlog 的行原样保留

---

## 复盘检查点 — PRD 与上下文一致性

Step 6 完成后、Commit 前，**必须**执行以下交叉验证。

**日志写入是硬性要求：** 发现任何偏离（硬偏离或软偏离）时，**先写入** `.logs/prd/PRD-NNN.md`，**再**修正。无偏离时写一行 "复盘通过，无偏离" 作为执行凭证。

| # | 检查项 | 检查方法 | 偏离类型 |
|---|---|---|---|
| P1 | PRD frontmatter `module-ref` = backlog 该行"模块"列 | 字符串比对 | 硬偏离 |
| P2 | PRD `design-inputs` 包含 module 文档路径 | 检查列表 | 硬偏离 |
| P3 | PRD Must Have / AC 可追溯到 module 边界的"承担"小节 | 对比 module 边界 | 范围偏离 |
| P4 | PRD type 与 backlog type 一致 | 字符串比对 | 硬偏离 |
| P5 | module 文档 `## 关联 Backlog` 中该 B-NNN 行阶段 = exploring | 行级比对 | 一致性偏离 |
| P6 | roadmap AUTO:PROGRESS 中该 B-NNN 行图标 = 🔎 | 行级比对 | 一致性偏离 |

**偏离处理：**
- **硬偏离**（P1/P2/P4 字段不一致）→ 写日志 → 自动修正（以 backlog 为准）
- **范围偏离**（P3 越界）→ 写日志 → 回 Step 3 让 Luke 决策（扩边界 / 拒绝 / 改挂模块）
- **一致性偏离**（P5/P6 同步未落盘）→ 写日志 → 自动补齐

---

## Step 7 — Commit + Push

**在 `main` 分支**直接提交：

```bash
git add product/prd/PRD-NNN.md
git add product/backlog.md
git add design/modules/<M-NNN>-<slug>.md
git add design/roadmap.md
git add .logs/prd/PRD-NNN.md
```

```bash
git commit -m "docs(PRD-NNN): draft PRD for B-NNN

Backlog-Ref: B-NNN
Module-Ref: M-NNN
PRD-Status: reviewing"
```

**推送走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push + 分段冲突策略）：

```bash
# Round 1
git push origin main
# 被拒 → git pull --rebase origin main → 回到 push
# rebase 冲突：
#   - product/backlog.md / design/roadmap.md AUTO:* / design/modules/*.md 关联 Backlog / 修订历史 → 按协议自动合并
#   - 主 specs / 模块边界等策略不覆盖段 → STOP + 日志
# 3 轮仍失败 → STOP，写日志到 .logs/prd/PRD-NNN.md
```

> commit 首词用 `docs`（PRD 是产品文档，非功能代码）。

---

## Step 8 — 等待 Luke 审阅与 Approved

输出简报：

```
📝 PRD-NNN 已生成（status: reviewing）
   - 路径：product/prd/PRD-NNN.md
   - 模块：M-NNN <模块名>
   - 关联：B-NNN（已推进到 exploring）
   - design-inputs：<已引用路径列表>
   - 请审阅；确认后说 "approved" 我改状态
```

### Luke 确认 approved 时：

```bash
git checkout main
git pull origin main
```

- 将 `status: reviewing → approved`
- commit message：`docs(PRD-NNN): approved`
- push 走 `core/git-safe-push.md` 协议（3 轮 retry）

**approved 是进入 `change-propose` 的硬前置。**

### 后续变更

- **需求变化但 change 未开始** → 直接改 PRD 内容，保持 `approved`
- **需求变化且 change 已执行中** → 旧 PRD 标 `superseded`，新开 B-NNN（新 PRD），走新流程
- **Luke 否决** → 改 `status: draft`，回 Step 3 重新对话

---

## 失败恢复

| 失败场景 | 恢复策略 |
|---|---|
| Step 2.2 "模块"列缺失 | 拒绝生成 PRD；提示 Luke 走 `/design` 或 `/design review` 补齐 |
| Step 3 对话越界 | 按 Step 3 的两档处理（小调 / 大越界） |
| Step 6.1 module 文档并发写入冲突 | `git pull --rebase` 后重试；P5 复盘兜底 |
| Step 7 push 被拒 | 走 `core/git-safe-push.md`（3 轮 pull-rebase-push），3 轮失败 STOP 写日志 |

---

## 与其他 Skill 的交接

| Skill | 交接方向 | 交接物 |
|---|---|---|
| `module-designer` | 上游 → 本 skill | backlog "模块"列、module 文档 `## 关联 Backlog` 的 depends-on 注释 |
| `change-propose` | 本 skill → 下游 | PRD `approved` + frontmatter 六字段齐全（id / type / backlog-ref / module-ref / status / change-id / design-inputs）|
| `change-review` | 本 skill → 下游（间接） | module `status: active` + roadmap AUTO:PROGRESS 图标 |

---

## 不做的事（Do NOT）

- ❌ 不做 idea 拆分（已下放到 `module-designer`）
- ❌ 不跨模块写 PRD（越界时拒绝对话）
- ❌ 不在 feature branch 操作（PRD 是产品文档，落 main）
- ❌ 不碰 AUTO:PROGRESS 非 idea/exploring 阶段的行
- ❌ 不覆盖 module 文档的人工段（只动 frontmatter、`## 关联 Backlog`、`## 修订历史`）
- ❌ 不自动触发 `/change-propose`（Luke approve 后由 `/loop 15m /change-propose` 自动接手）
