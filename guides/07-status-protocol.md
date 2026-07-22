# 状态协议与字段规范

## tasks.md YAML 头

```yaml
---
status: draft
backlog-ref: B-003
depends-on: []
---
```

### status 字段

| 值 | 含义 | 谁设置 | 前置条件 |
|---|---|---|---|
| `draft` | 交互式 agent 正在编写四件套 | 交互式 agent（Claude Code / Codex） | 创建 change 时 |
| `ready` | 四件套齐全，等待 dispatch runner 领取 | 交互式 agent（Claude Code / Codex） | pre-flight 通过 |
| `executing` | dispatch 正在执行某个任务组 | change-dispatch | 领取第一个任务组时 |
| `review` | 所有自动化任务组完成，等待审查 | change-dispatch | 所有自动化组 done |
| `done` | 已通过 verify 并归档 | change-review | verify 三维度通过 |

### backlog-ref 字段

关联的 backlog 条目 ID，格式 `B-NNN`。

### depends-on 字段

前置 change 的 change-id 列表。dispatch 扫描时会检查列表中所有 change 是否 `done`。

```yaml
depends-on: [auth-core, user-profile]  # 需要这两个 change 先完成
depends-on: []                          # 无前置依赖
```

---

## 任务组 HTML 注释

每个任务组的标题下方使用 HTML 注释标注元信息：

```markdown
## 共享基础设施

<!-- 执行模式: auto | 约束: 串行，必须先完成 | status: pending -->
```

### 字段说明

| 字段 | 值 | 说明 |
|------|---|------|
| 执行模式 | `auto` / `interactive` | `auto` = 任意 dispatch runner（Codex Automation / Claude Code `/loop` / cron / GH Actions）领取；`interactive` = 交互式由 review 或人工承接。旧 `执行工具: Codex` / `执行工具: Claude Code` 保留向后兼容 |
| 约束 | 自由文本 | 如"串行"、"G0 完成后"、"与任务组 3 并行" |
| status | `pending` / `executing` / `done` | 任务组级别状态 |

> **不再为每个任务组创建子分支**。所有任务组（G0 / G1-A / G1-B / G2 等）在同一个 `<branch-prefix>/<change-id>` feature branch 上线性提交，通过 `约束` 字段表达串行/并行关系。G 命名是任务组的逻辑标签，不是分支名。

---

## PRD 状态

`product/prd/PRD-NNN.md` YAML 头中的 status 字段：

| 状态 | 含义 | 谁设置 |
|------|------|--------|
| `draft` | 正在撰写 | 交互式 agent（Claude Code / Codex，prd-writer） |
| `reviewing` | 等待用户审阅 | 交互式 agent（Claude Code / Codex，prd-writer） |
| `approved` | 用户已确认，可进入 propose | 用户 |
| `superseded` | 已废弃（需求变更或取消） | 用户 / 交互式 agent |

### depends-on 字段（PRD）

PRD YAML 头中的 `depends-on` 字段，列出前置 backlog 依赖：

```yaml
depends-on: [B-044, B-045]  # 需要这些 backlog 条目先完成
depends-on: []               # 无前置依赖
```

`change-propose` 扫描时会检查列表中所有 backlog 条目是否为 `done`，未满足则跳过。

### change-id 字段（PRD）

PRD YAML 头中预定义的 change-id，用于 feature branch 命名 `<branch-prefix>/<change-id>`（branch 前缀由 type 直接映射，见 [11-task-types.md](./11-task-types.md)）。

```yaml
change-id: ai-voice-entry
```

此字段由 `prd-writer` 在生成 PRD 时按 type 前缀规则产出（feature 无前缀 / bug `fix-` / chore `chore-` / hotfix `hotfix-`），全局唯一；`change-propose` 校验前缀与 type 一致，但不生成它。dispatch / review 不从中反解析 type（type 直接读 backlog 类型列）。

---

## Backlog 状态

`product/backlog.md` 中的阶段字段：

| 阶段 | 含义 | 触发者 | 对应事件 |
|------|------|--------|---------|
| `idea` | 初步想法 | module-designer / 人工 | — |
| `exploring` | PRD 生成中 | prd-writer | PRD 生成，status: reviewing |
| `proposed` | 已生成四件套 | change-propose | PRD approved → pre-flight 通过 |
| `done` | 已归档 | change-review | verify 通过，status → done |

> backlog 只有 4 个阶段——都有明确的 main 写入者。执行中 / 审查中的细粒度（dispatch 领取、组完成、PR 审查）由 `tasks.md` YAML 头的 `status` 承担，不在 backlog.md 里冗余。dispatch 禁碰 main 治理层。

---

## 状态流转图

### Change 维度

```
       交互式 agent              dispatch             dispatch            review
            编写中                 pre-flight             领取                全部完成              归档
              │                      │                    │                   │                   │
draft ──────→ draft ──────────→ ready ──────────→ executing ──────────→ review ──────────→ done
```

### PRD 维度

```
draft ──→ reviewing ──→ approved ──→ (可选) superseded
  │           │             │                │
创建时     生成完成      用户确认        需求变更时
```

### Backlog 维度

```
idea ──→ exploring ──→ proposed ──────────────────────→ done
  │          │              │                              │
  人工    prd-writer   change-propose                 change-review
         (PRD)       (四件套+Draft PR)              (归档+verify)

细粒度见 tasks.md YAML status：
draft → ready → executing → review → done
            │         │          │        │
        propose   dispatch    dispatch   review
                  (领取)   (收敛全done) (合并+归档)
```

### 任务组维度

```
pending ──→ executing ──→ done
    │            │           │
  初始状态    dispatch      完成后
             领取时       自动设置
```

---

## 完整生命周期示例

```
T=0   用户把灵感放入 design/inputs/，运行 /design
      → module-designer 生成 M-002 模块并拆出 B-003 (idea)
T=1   用户说: "帮我分析 B-003 的需求"
      → prd-writer 生成 PRD-003 (status: reviewing)
      → backlog B-003: idea → exploring, PRD: PRD-003
T=2   用户审阅 PRD: "approved"
      → PRD-003 status: approved
T=3   用户说: "基于 B-003 开始规划"（或 change-propose 自动触发）
      → 交互式 agent 读取 PRD-003 → 生成四件套
      → tasks.md status: draft → ready
      → backlog B-003: exploring → proposed
T=4   dispatch runner 自动领取 G0
      → G0 status: pending → executing → done
      （backlog B-003 保持 proposed——dispatch 不碰 main）
T=5   dispatch runner 并行领取 G1-A、G1-B
      → G1-A/G1-B status: pending → executing → done
      → tasks.md status: ready → review
      （backlog B-003 仍保持 proposed，细粒度看 tasks.md status）
T=6   用户触发 review
      → 交互式 agent 审查 → 合并 → verify → 归档
      → tasks.md status: review → done
      → backlog B-003: proposed → done
```
