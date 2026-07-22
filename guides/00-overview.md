# 全流程总览

本框架通过五个 AI Skill 串联，形成从灵感到交付的完整闭环。

## 五层架构

```
L0 design/inputs/         ← 原始设计输入（brainstorming / figma / interviews）
L1 design/modules/        ← 模块设计（M-NNN，module-designer 产出）
L2 product/backlog.md     ← B-NNN（带"模块"列 = M-NNN）
L3 product/prd/           ← PRD-NNN（引用 module 文档 + design-inputs）
L4 openspec/changes/      ← 四件套 + feature branch + Draft PR
```

全景映射沉淀在 `design/roadmap.md`（AUTO 段：ARCHITECTURE / DEPENDENCIES / PROGRESS 从 backlog + modules 全量重渲染）。

## 流水线

```
用户 / PM
  │  录入灵感到 design/inputs/（brainstorming / figma / interviews）
  ▼
module-designer                 ← 交互式 agent（Claude Code / Codex，/design）
  │  读 inputs + roadmap + 既有模块
  │  与用户对话：建模块 + 划边界 + 拆 idea
  │  → 生成 design/modules/M-NNN-<slug>.md（status: planning）
  │  → 同步把 idea 拆到 product/backlog.md（阶段: idea，模块列: M-NNN）
  │  → 更新 design/roadmap.md 的 AUTO 段
  │
  ▼
prd-writer                      ← 交互式 agent（Claude Code / Codex，/prd B-NNN）
  │  读 backlog + 归属模块 M-NNN 文档 + design-inputs
  │  与用户对话澄清需求（边界受 module 文档约束）
  │  → 生成 PRD（product/prd/PRD-NNN.md，含 module-ref / design-inputs）
  │  → backlog 阶段: exploring（首次激活时模块 status: planning → active）
  │
  ▼
用户审阅 PRD                     ← 人工确认 → PRD status: approved
  │
  ▼
change-propose                 ← 交互式 agent（Claude Code / Codex，人工触发 / runner 定期触发）
  │  Phase 0: 读 backlog + 读 PRD（必须 approved，粒度已在 /design 阶段确定）
  │  Phase 1: 基于 PRD 生成四件套（proposal + delta specs + design + tasks）
  │  Phase 2: 依赖分析 → 编写 tasks.md → pre-flight → 标记 ready
  │  → 创建 feature branch + Draft PR → backlog 阶段: proposed
  │
  ▼
change-dispatch                ← dispatch runner（Codex Automation / `/loop` / cron / GH Actions，按配置间隔自动）
  │  扫描 backlog → detached worktree → 原子 claim → 唯一 worker branch 执行 → fast-forward push
  │  → tasks.md status: review
  │  → Draft PR 自动更新 → CI 自动运行
  │  （backlog 阶段保持 proposed——dispatch 不碰 main；细粒度看 tasks.md status）
  │
  ▼
change-review                  ← 交互式 agent（Claude Code / Codex，人工 / 定期 / CI 全绿触发）
  │  PR 审查 → 分形文档同步 → 合并前三维 Verify
  │  → implementation PR 合并 → sync delta specs + archive governance PR
  │  → backlog 阶段: done
  │
  ▼
交付完成
```

## Backlog 状态流转

```
idea → exploring → proposed ────────────────────────→ done
 ↑        ↑           ↑                                  ↑
module  prd-writer  change-propose                  change-review
designer  (PRD)     (四件套 + Draft PR)              (Verify + 合并 + 归档)

执行细粒度（tasks.md YAML status，change 独占，dispatch 禁碰 main）：
draft → ready → executing → review → done
          │         │          │        │
      propose   dispatch    dispatch   review
                 (原子领取) (收敛全done) (预合并 Verify + 归档)
```

## 模块状态流转

```
planning → active → done
   ↑          ↑        ↑
 module   prd-writer change-review
 designer  (首次    (最后一条
  (首次建) 激活)    backlog done)
                        │
                        └──► deprecated（人工 /design review 标记）
```

## PRD 状态流转

```
draft → reviewing → approved → (可选) superseded
  ↑        ↑           ↑              ↑
创建时   生成完成    用户确认      需求变更时
```

## Change 状态流转

```
draft → ready → executing → review → done
  ↑       ↑         ↑          ↑       ↑
编写中  pre-flight  dispatch   dispatch  归档
                    领取       全部完成
```

## 核心产物

### PRD（产品定义 — what & why）

```
product/prd/PRD-NNN.md
├── 背景与问题
├── 用户故事
├── 功能需求（Must Have / Nice to Have / Out of Scope）
├── 验收标准
└── 依赖与风险
```

### Change 四件套（技术方案 — how）

```
openspec/changes/<change-id>/
├── _DIR.md          ← change 说明
├── proposal.md      ← 技术路线、范围、影响（引用 Backlog + PRD）
├── specs/           ← Delta Specs（ADDED/MODIFIED/REMOVED）
├── design.md        ← 文件清单、并行设计
└── tasks.md         ← 简洁 checkbox 任务清单
```

## 工具分工

| 阶段 | 工具 | 触发方式 |
|------|------|----------|
| 灵感录入 | 人工 | 写 `design/inputs/**` |
| 模块设计 + idea 拆分 | 交互式 agent（Claude Code / Codex，module-designer） | `/design` / `/design review M-NNN` |
| 产品定义 | 交互式 agent（Claude Code / Codex，prd-writer） | `/prd B-NNN` |
| PRD 审阅 | 人工 | 用户确认 approved |
| 技术规划 | 交互式 agent（Claude Code / Codex，change-propose） | 人工触发 / runner 定期触发 |
| 代码执行 | change-dispatch (任意 runner：Codex Automation / `/loop` / cron / GH Actions) | 按配置间隔自动 |
| 审查归档 | 交互式 agent（Claude Code / Codex，change-review） | 人工触发 / runner 定期触发 |

## 指南目录

| 文件 | 内容 |
|------|------|
| [01-initialization.md](./01-initialization.md) | 项目初始化 |
| [02-backlog.md](./02-backlog.md) | 管理产品 Backlog |
| [03-prd.md](./03-prd.md) | PRD：从想法到产品定义 |
| [04-propose.md](./04-propose.md) | 规划阶段：从 PRD 到四件套 |
| [05-execution.md](./05-execution.md) | 执行阶段：dispatch 自动开发 |
| [06-review-and-archive.md](./06-review-and-archive.md) | 审查、验证与归档 |
| [07-status-protocol.md](./07-status-protocol.md) | 状态协议与字段规范 |
| [08-faq.md](./08-faq.md) | 常见问题 |
| [09-git-github-workflow.md](./09-git-github-workflow.md) | Git & GitHub 全流程操作指南 |
| [10-extras.md](./10-extras.md) | 外部 skill 弱耦合接入（brainstorming / impeccable） |
| [11-task-types.md](./11-task-types.md) | 4 种任务类型（feature / bug / chore / hotfix）与命名规范 |
| [12-design-layer.md](./12-design-layer.md) | 设计层：从灵感到模块化 Backlog（module-designer / roadmap / 模块生命周期） |

## Claude Code 权限配置

为避免自动化 skill（review、dispatch、change-propose）运行时反复弹出 Bash 命令确认，建议在 `.claude/settings.json` 中配置：

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(pnpm *)",
      "Bash(ls *)",
      "Bash(pwd)",
      "Bash(mkdir *)"
    ]
  }
}
```

同时，所有 skill 中的 Bash 命令应遵循"单命令单调用"原则，避免用 `&&`/`||`/`;` 串联多条命令。
