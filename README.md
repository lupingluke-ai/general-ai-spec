# General AI Spec

**AI 驱动的全流程软件开发框架**

作者：**jiatao**

---

## 是什么

General AI Spec 是一套三层架构的 AI 编码框架，将产品需求管理、规范治理（OpenSpec）、分形文档和 AI 并行开发整合为一条自动化流水线。框架通过交互式 AI agent（Claude Code / Codex，规划/审查）和任意 dispatch runner（Codex Automation / Claude Code `/loop` / cron / GH Actions，runner-agnostic 并行执行）协同工作，实现从一行想法到代码交付的完整闭环。

## 核心流水线

```
design/inputs (原始灵感)
  → module-designer (模块设计 + idea 拆分)
  → backlog (idea, 带模块列)
  → prd-writer (PRD 产品定义)
  → change-propose (四件套技术方案)
  → change-dispatch (runner 自动执行)
  → change-review (审查/验证/归档)
  → backlog (done)
```

## 目录结构

```
general_ai_spec/
├── core/           通用规则层
├── stacks/         技术栈配置层
├── skills/         AI Skill 层
├── templates/      项目初始化模板
├── scripts/        自动化脚本
└── guides/         中文操作指南
```

---

## core/ — 通用规则

与技术栈无关的核心规范，所有项目共享。

| 文件 | 职责 |
|------|------|
| `AGENTS.md` | AI Agent 行为规范：工作流路径、分形文档规则、四件套要求、verify 三维度、禁令清单 |
| `config.yaml` | OpenSpec 治理规则：PRD / backlog / proposal / specs / design / tasks / verify / archive 的完整规则 |
| `fractal.md` | 分形文档规范：`_DIR.md` + `@input/@output/@pos` 头注释的格式和约束 |

## stacks/ — 技术栈配置

可插拔的技术栈 Profile，每个 Profile 定义特定技术栈的架构、依赖和禁令。

| Profile | 适用场景 |
|---------|---------|
| `nextjs-react-local/` | Next.js + React + 本地 JSON 存储（轻量 MVP） |
| `nextjs-react-drizzle/` | Next.js + React + Drizzle ORM + PostgreSQL（生产级） |

每个 Profile 包含：
- `stack.md` — 技术栈描述和架构约定
- `do-not.md` — 技术栈特定禁令
- `config-ext.yaml` — OpenSpec 规则扩展
- `scaffold.sh` — 依赖安装和环境配置脚本

## skills/ — AI Skill

五个串联 Skill 组成完整开发流水线：

| Skill | 执行角色 / 可选工具 | 职责 |
|-------|---------|------|
| `module-designer/` | 交互式 agent（Claude Code / Codex） | 从 design inputs 建模块、划边界、拆分 backlog idea，并同步 roadmap |
| `prd-writer/` | 交互式 agent（Claude Code / Codex） | 从 backlog 条目生成 PRD（产品需求文档），与用户对话澄清需求 |
| `change-propose/` | 交互式 agent（Claude Code / Codex） | 基于 PRD 生成四件套（proposal + delta specs + design + tasks），支持并行任务拆分 |
| `change-dispatch/` | 任意 runner（Codex Automation / `/loop` / cron / GH Actions） | 按项目配置的节奏扫描就绪任务，在 worktree 中隔离执行 |
| `change-review/` | 交互式 agent（Claude Code / Codex） | 分支审查、顺序合并、verify 三维度验证、delta specs 同步、归档 |

## templates/ — 初始化模板

init.sh 使用的文件模板，用于生成新项目的基础文件。

| 模板 | 生成目标 |
|------|---------|
| `CLAUDE.md.tmpl` | 项目根 `CLAUDE.md`（Claude Code adapter 入口；共享规则仍在 `AGENTS.md`） |
| `AGENTS.md.tmpl` | 项目根 `AGENTS.md`（core 规则 + stack 禁令） |
| `project.md.tmpl` | `openspec/project.md`（项目技术上下文与架构基线） |
| `backlog.md.tmpl` | `product/backlog.md`（产品需求 Backlog） |
| `prd.md.tmpl` | `product/prd/PRD-NNN.md`（Full PRD，feature 类型用） |
| `prd-lite.md.tmpl` | `product/prd/PRD-NNN.md`（Lite PRD，bug / chore / hotfix 类型用） |
| `github-workflows/auto-merge.yml` | `.github/workflows/auto-merge.yml`（change-review 转 Ready 后启用 merge commit auto-merge） |

## scripts/ — 自动化脚本

| 脚本 | 职责 |
|------|------|
| `init.sh` | 一键初始化新项目：生成 AGENTS.md、project.md、config.yaml、CLAUDE.md 适配入口、backlog、分形文档骨架、auto-merge workflow、`.logs/` 执行日志目录，安装 Skills |

```bash
# 使用示例
bash scripts/init.sh --stack nextjs-react-local --dir /path/to/project
bash scripts/init.sh --list          # 列出可用技术栈
bash scripts/init.sh --dry-run       # 预览模式
```

## guides/ — 中文操作指南

按流程阶段分文件的完整操作手册：

| 文件 | 内容 |
|------|------|
| `00-overview.md` | 流水线全景、状态流转、工具分工 |
| `01-initialization.md` | 项目初始化步骤和 dispatch runner 配置 |
| `02-backlog.md` | 产品 Backlog 管理：格式、阶段、操作流程 |
| `03-prd.md` | PRD 生成：从想法到结构化产品定义 |
| `04-propose.md` | 技术规划：从 PRD 到四件套 |
| `05-execution.md` | dispatch 自动执行：并行机制、异常处理 |
| `06-review-and-archive.md` | 审查、verify 三维度、归档 |
| `07-status-protocol.md` | 状态字段规范和完整生命周期 |
| `08-faq.md` | 常见问题 |

---

## 快速开始

```bash
# 1. 初始化项目
bash scripts/init.sh --stack nextjs-react-local --dir ./my-app

# 2. 选一种 dispatch runner（任选其一，详见 skills/change-dispatch/SKILL.md）
#    A: 在 Claude Code 中运行 `/loop <interval> /change-dispatch`（零配置，推荐开发期）
#    B: Codex Desktop 配置 Automation（Name: change-dispatch | Schedule: <interval> | Worktree: yes）
#    C: cron：<cron> cd /path/to/repo && claude -p "/change-dispatch"
#    D: GitHub Actions 定时 workflow

# 3. 录入原始想法并拆成 backlog
#    将灵感写入 design/inputs/，然后在 Claude Code 或 Codex 中运行 /design

# 4. 开始开发
#    告诉 Claude Code 或 Codex: "帮我分析 B-001 的需求"
#    → PRD → 四件套 → dispatch 自动执行 → 审查归档
```

## 设计原则

- **产品驱动**：所有开发从 design inputs 收敛到模块化 backlog，PRD 定义 what & why，四件套定义 how
- **人工门控**：PRD 必须用户 approved，AI 不代替人做产品决策
- **规范治理**：每个 change 必须有四件套（proposal + delta specs + design + tasks）
- **并行优先**：任务按依赖关系拆分为串行/并行组，runner 在 worktree 中隔离执行
- **分形文档**：每个目录维护 `_DIR.md`，关键文件维护 `@input/@output/@pos`，文档是实现的一部分
- **三维验证**：Completeness（全覆盖）+ Correctness（行为正确）+ Coherence（结构一致）
- **可插拔**：core 规则通用，技术栈通过 stacks/ 切换，skill 可独立演进
- **执行可观测**：所有自动化 skill 遇到 STOP/WARN 问题时写入 `.logs/`，复盘检查点检测路径偏离

## License

MIT
