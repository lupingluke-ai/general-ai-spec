# PRD：从想法到产品定义

本阶段由交互式 agent（Claude Code / Codex）执行，使用 `prd-writer` skill。

## 为什么需要 PRD

```
idea（一行描述）──→ PRD（结构化产品定义）──→ 四件套（技术方案）
      ↑                     ↑                        ↑
  "午饭时的灵感"      "完整的用户故事、       "精确到文件级别的
                      功能需求、验收标准"       并行执行方案"
```

PRD 解决的问题：避免 AI 在写技术方案时同时做产品决策。先用 PRD 把"做什么"想清楚，再用四件套把"怎么做"定义好。

## 触发方式

```
你：帮我分析 B-003 的需求
你：帮我写个 PRD，B-003 AI 语音记账
你：/prd B-003
```

## 完整流程

### Step 0 — 前置：模块归属必须就绪

`prd-writer` 不再做 idea 拆分（已下放到 `module-designer`）。进入 `/prd B-NNN` 前，backlog 该行必须：

- "模块"列已填 `M-NNN`
- 归属的 `design/modules/M-NNN-*.md` 文件存在

若"模块"列为 `—` 或模块文档缺失，`prd-writer` 会拒绝生成 PRD 并提示用户：
- 历史遗留 backlog → `/design review M-NNN` 追加到具体模块
- 新条目漏填 → 回到 `/design` 重新走 module-designer 流程

拆分需求、调整边界都回到 `/design`，不在 prd-writer 阶段承担。

### Step 1 — 定位 Backlog + 上下文

交互式 agent 读取 `product/backlog.md` 找到 B-NNN，然后按以下顺序必读上下文：

- `design/modules/M-NNN-*.md` — 模块边界、对外接口、`## 关联 Backlog` 中该行尾部的 `[depends-on: ...]`
- `design/inputs/**` — module 文档 `design-inputs` 字段列出的所有路径
- `openspec/project.md` — 技术栈约束
- `openspec/specs/` — 已有系统行为，避免需求冲突
- 相关代码 — 评估现状时按需读

### Step 2 — 边界受模块约束的需求对话

交互式 agent 通过提问引导你澄清需求。**所有需求必须落在 module 文档的"承担"边界内**：

- 小幅越界 → 提示 "要不要扩展 M-NNN 的边界？"，调整后先走 `/design review M-NNN` 再回来
- 大幅越界 → 拒绝对话，提示 "这条需求本质属于另一个模块，建议拆到新 backlog 并挂到对应模块"

### Step 3 — 对话示例

```
交互式 agent：B-003 描述"AI 语音快速记账"，我有几个问题：
1. 语音识别是纯离线还是需要联网？
2. 识别结果是直接保存还是让用户确认后保存？
3. 只支持中文还是多语言？
4. 识别失败时的降级方案是什么？

你：联网，用户确认后保存，只支持中文，降级到手动输入

交互式 agent：明白。关于"用户确认"环节——是用现有表单预填充，
            还是需要一个新的确认界面？

你：用现有表单预填充

交互式 agent：好的，这样可以复用已有的表单验证逻辑。我来生成 PRD。
```

### Step 4 — 生成 PRD

交互式 agent 创建 `product/prd/PRD-003.md`：

```markdown
---
id: PRD-003
type: feature
backlog-ref: B-003
module-ref: M-002
status: reviewing
created: 2026-03-26
depends-on: []
design-inputs:
  - design/modules/M-002-voice-entry.md
  - design/inputs/brainstorming/voice-entry-notes.md
change-id: ai-voice-entry
---

# AI 语音快速记账

## 背景与问题
当前记账需要手动打开表单、选择分类、输入金额，步骤繁琐。
用户希望通过语音快速完成记账，降低使用门槛。

## 目标用户
日常记账用户，尤其是移动端用户，在不方便打字时快速记一笔。

## 用户故事
- 作为记账用户，我想对着手机说"午饭花了32块"，
  以便 3 秒内完成一笔记录
- 作为记账用户，我想在语音识别后确认并调整金额和分类，
  以便确保记录准确

## 功能需求
### 核心功能（Must Have）
- FR-1: 首页提供语音记账入口按钮
- FR-2: 点击后启动浏览器语音识别（中文）
- FR-3: 语音文本发送到 AI 提取接口，返回结构化数据
- FR-4: 提取结果预填充到现有记账表单，用户确认后保存

### 明确不做（Out of Scope）
- 多语言语音识别
- 离线语音识别
- 语音直接保存（不经用户确认）

## 验收标准
- AC-1: 用户说"午饭花了32块"，表单自动填入 支出/32.00/餐饮
- AC-2: 浏览器不支持语音时，按钮显示禁用状态
- AC-3: AI 识别失败时，显示错误提示并可重试
```

### Step 5 — 用户审阅

```
交互式 agent：PRD-003 已生成，请审阅。重点确认：
- 用户故事是否覆盖了你的核心场景？
- "明确不做"中的排除项是否正确？
- 验收标准是否充分？

你：看起来不错，approved
交互式 agent：好的，PRD-003 已标记为 approved。
            backlog B-003 阶段已更新为 exploring。
            你可以随时进入下一步：基于 PRD-003 做 propose。
```

### Step 6 — 进入 Propose

PRD approved 后：

```
你：基于 B-003 开始规划
交互式 agent：（读取 PRD-003 → 使用 change-propose 生成四件套）
```

## PRD 状态

| 状态 | 含义 | 转换条件 |
|------|------|----------|
| `draft` | 正在撰写 | 创建时 |
| `reviewing` | 等待用户确认 | 生成完成时 |
| `approved` | 用户已确认 | 用户说"确认/approved" |
| `superseded` | 已废弃 | 需求变更或取消时 |

## PRD YAML Schema

PRD 文件头的完整字段：

| 字段 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `id` | `PRD-NNN` | ✅ | 与 backlog ID 对应（B-003 → PRD-003） | `PRD-003` |
| `type` | `feature` / `bug` / `chore` / `hotfix` | ✅ | 与 backlog.type 必须一致 | `feature` |
| `backlog-ref` | `B-NNN` | ✅ | 关联的 backlog 条目 | `B-003` |
| `module-ref` | `M-NNN` | ✅ | 归属模块，= backlog 该行"模块"列 | `M-002` |
| `status` | `draft` / `reviewing` / `approved` / `superseded` | ✅ | PRD 生命周期 | `reviewing` |
| `created` | `YYYY-MM-DD` | ✅ | 创建日期 | `2026-03-26` |
| `depends-on` | `[B-xxx, ...]` | ✅ | 前置 backlog 依赖列表，无依赖则 `[]` | `[B-044, B-045]` |
| `design-inputs` | `[path, ...]` | ✅ | 至少含模块文档路径 | 见示例 |
| `change-id` | `string` | ✅ | 预定义 kebab-case，供 change-propose 使用 | `ai-voice-entry` |

**强校验**（由 prd-writer / change-propose 执行）：
- `module-ref` 必须 = backlog 该行"模块"列（否则 prd-writer 硬偏离自动修正）
- `design-inputs` 必须至少包含 `design/modules/<module-ref>-*.md`（否则 change-propose 跳过）
- `type` 必须 = backlog `type` 字段（不可变）
- PRD `status: approved` 是进入 change-propose 的硬前置

## PRD 文件位置

```
product/
├── _DIR.md
├── backlog.md
└── prd/
    ├── _DIR.md
    ├── PRD-001.md    ← approved
    ├── PRD-003.md    ← reviewing
    └── ...
```

## 什么时候可以用 Lite PRD

bug / chore / hotfix 类型自动使用 Lite PRD 模板（`templates/prd-lite.md.tmpl`），保留 Must Have 和 AC，省去成功指标等产品级字段。feature 使用 Full 模板。模板选择由 prd-writer 根据 type 自动匹配。

不支持"完全跳过 PRD"——所有类型的 backlog 都必须经过 `/prd B-NNN` 产出 PRD（Full 或 Lite），这是 change-propose 的硬前置。

## 注意事项

- PRD 是产品文档，不包含技术实现细节
- PRD 必须用户确认 approved 才能进入 propose（AI 不代替人做产品决策）
- **PRD 与 change 严格 1:1 绑定**（PRD frontmatter 的 `change-id` 是单值字段）。需要切分工作量时请回到 `/design`，由 `module-designer` 在 backlog 层拆成多条 B-NNN，每条 backlog 各自 1 PRD → 1 change
- **PRD 不跨模块**（`module-ref` 是单值字段）。跨模块需求必须先在 `/design` 拆分
- PRD 不随 change 归档，长期保留在 `product/prd/` 中

## 下一步

PRD approved 后，进入 [04-propose.md](./04-propose.md) 开始技术规划。
