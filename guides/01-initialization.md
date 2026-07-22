# 项目初始化

## 前提条件

- Node.js 18+
- pnpm 已安装
- Git 已初始化
- **GitHub 远程仓库已创建，且 `gh auth status` 通过**——`change-propose` 需要创建 Draft PR，`change-review` 需要合并 PR；没有远程仓库流水线走不到 propose 之后
- Claude Code 或 Codex 已安装（用于规划和审查）
- 至少选择一种 dispatch runner（Codex Desktop / Claude Code `/loop` / cron / GitHub Actions / 手动），详见下文
- 全自动闭环还需给 `change-review` 配置定时触发（如 `/loop <interval> /change-review`）——review 的兜底等待与中断恢复依赖下一次扫描

## 初始化命令

```bash
# 查看可用技术栈
bash scripts/init.sh --list

# 初始化项目（示例：Next.js + React + 本地存储）
bash scripts/init.sh --stack nextjs-react-local --dir /path/to/project

# 先预览，不实际写入
bash scripts/init.sh --stack nextjs-react-local --dir /path/to/project --dry-run
```

## 初始化后的目录结构

```
project/
├── CLAUDE.md                  ← Claude Code adapter 入口（共享规则在 AGENTS.md）
├── AGENTS.md                  ← AI Agent 行为规范
├── product/
│   ├── _DIR.md
│   ├── backlog.md             ← 产品需求 Backlog
│   └── prd/
│       └── _DIR.md
├── design/
│   ├── _DIR.md
│   ├── roadmap.md
│   ├── inputs/
│   │   ├── _DIR.md
│   │   ├── brainstorming/
│   │   │   └── _DIR.md
│   │   ├── figma/
│   │   │   └── _DIR.md
│   │   └── interviews/
│   │       └── _DIR.md
│   └── modules/
│       └── _DIR.md
├── openspec/
│   ├── project.md             ← 技术栈 & 架构说明
│   ├── config.yaml            ← OpenSpec 治理规则
│   ├── specs/                 ← 主 specs（归档时自动填充）
│   │   └── _DIR.md
│   └── changes/
│       └── _DIR.md
├── .logs/
│   ├── _DIR.md                ← 日志格式与规则说明
│   ├── module-designer/       ← module-designer 日志
│   ├── prd/                   ← prd-writer 日志
│   ├── dispatch/              ← change-dispatch 执行日志（任意 runner）
│   ├── propose/               ← change-propose 日志
│   └── review/                ← change-review 日志
├── src/
│   ├── _DIR.md
│   └── app/
│       └── _DIR.md
├── .env.local                 ← 环境变量模板
└── .gitignore                 ← 已包含 .worktrees
```

## Skills 安装

init.sh 会自动将框架 skills 符号链接到项目中：

```
.agents/skills/               ← Codex / 其他 agent 使用
  ├── module-designer/
  ├── prd-writer/
  ├── change-propose/
  ├── change-dispatch/
  └── change-review/

.claude/skills/                ← Claude Code 使用
  ├── module-designer/
  ├── prd-writer/
  ├── change-propose/
  ├── change-dispatch/
  └── change-review/
```

> skill 本身 runner-agnostic，只依赖 git + shell + 网络。无论哪个 agent 调用，都执行相同的 dispatch 逻辑。

## 执行日志

init.sh 自动创建 `.logs/` 目录及五个子目录。各阶段 skill 在遇到 STOP/WARN 级别问题时写入对应子目录：

| 子目录 | 写入者 | 内容 |
|--------|--------|------|
| `module-designer/` | module-designer | 模块边界、idea 拆分、roadmap 同步偏离 |
| `prd/` | prd-writer | PRD 字段、模块边界、roadmap 同步偏离 |
| `propose/` | change-propose | PRD 缺字段、依赖未就绪、四件套交叉一致性偏离 |
| `dispatch/` | change-dispatch | 测试/lint/构建失败、实现与设计一致性偏离、Rebase 冲突 |
| `review/` | change-review | 设计偏离、范围越界、合并冲突、Verify 三维度失败、归档前完整性偏离 |

每个 skill 还内置 **复盘检查点**，在关键阶段完成后交叉验证产出物一致性，发现偏离时同样写入日志。

详见 `.logs/_DIR.md`。

## 配置 Dispatch Runner

初始化后需要选一种方式承接 dispatch 循环。完整清单见 `skills/change-dispatch/SKILL.md` 的「Runner 配置」小节；以下是常见选项：

### 方式 A — Claude Code `/loop`（推荐开发期，零配置）

在 Claude Code 内直接运行：

```
/loop <interval> /change-dispatch
```

### 方式 B — Codex Desktop Automation（推荐 24/7 无人值守）

1. 打开 Codex Desktop → Settings → Automations
2. 新建 Automation：
   - **Name**: `change-dispatch`
   - **Schedule**: `<interval>`
   - **Worktree**: Yes
   - **Prompt**: `使用 $change-dispatch 扫描并执行就绪的任务组`

### 方式 C — cron

```cron
<cron> cd /path/to/repo && claude --dangerously-skip-permissions -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

### 方式 D — GitHub Actions

参考 `skills/change-dispatch/SKILL.md` 的 GitHub Actions 示例自行配置定时 runner。

### 方式 E — 一次性手动触发

任何支持 skill 调用的 agent 都可手动执行 `/change-dispatch`。

## 初始化验证

```bash
# 确认依赖安装
pnpm install

# 确认代码质量
pnpm lint

# 确认文件存在
ls AGENTS.md CLAUDE.md openspec/project.md openspec/config.yaml product/backlog.md .github/workflows/ci.yml src/_DIR.md
```

## CI 与合并策略

`init.sh` 已生成 `.github/workflows/ci.yml`（test / lint / build），dispatch 的每次 push 与 PR 都会触发。

**默认路径（零仓库配置）：** `change-review` 在本地跑完同样的 CI 三件套并 rebase 到最新 main 后，直接 `gh pr merge --merge` 完成合并，同一轮继续 verify + 归档。远端 `ci.yml` 作为第二道观测保障，不阻塞合并。

**可选加固（推荐生产项目）：** 在 GitHub 仓库设置中：

1. 开启 branch protection，将 CI workflow 的 `ci` job 配置为 required check
2. 开启 "Allow auto-merge"

配置后，`change-review` 的即时合并会因 checks 未跑完被拒，自动退化为 `gh pr merge --auto --merge`（GitHub 等 checks 绿后合并），下一轮 review 扫描到 MERGED 后继续 verify + 归档。**只开 branch protection 而不开 auto-merge 会导致 review STOP**——两项要么都开，要么都不开。

## 下一步

初始化完成后，把原始想法放到 `design/inputs/`，运行 `/design` 生成模块和第一批 backlog，然后进入 [02-backlog.md](./02-backlog.md)。
