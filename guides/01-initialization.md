# 项目初始化

## 前提条件

- Node.js 22（生成的 GitHub Actions 也固定使用 Node 22）
- pnpm 已安装
- Git 已安装；目标没有仓库时 init 会创建 `main`，目标若只是另一个仓库的子目录则拒绝执行
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

# Drizzle stack 如需脚本同时启动本地 PostgreSQL，必须显式 opt-in
START_LOCAL_SERVICES=true bash scripts/init.sh --stack nextjs-react-drizzle --dir /path/to/project

# 先预览，不实际写入
bash scripts/init.sh --stack nextjs-react-local --dir /path/to/project --dry-run
```

路径应指向现有 Git 仓库根目录，或不属于任何其他仓库的新目录。不要把目标设为当前仓库的普通子目录；init 会为避免嵌套仓库而 STOP。

若项目已经由 General AI Spec 初始化并用于 Codex，只需接入 Claude Code：

```bash
bash scripts/cc-onboard.sh --dry-run
bash scripts/cc-onboard.sh
# 显式升级框架自有 runtime tools 与五个 skills
bash scripts/cc-onboard.sh --refresh-framework
```

onboarding 会校验 `AGENTS.md`、`openspec/config.yaml` 与 `product/backlog.md`。缺任一项说明它不是完整 General AI Spec 项目，应使用 `init.sh`。

## 初始化后的目录结构

```
project/
├── _DIR.md                   ← 项目根目录索引
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
│   │   └── _DIR.md
│   ├── prd/                   ← prd-writer 日志
│   │   └── _DIR.md
│   ├── dispatch/              ← change-dispatch 执行日志（任意 runner）
│   │   └── _DIR.md
│   ├── propose/               ← change-propose 日志
│   │   └── _DIR.md
│   └── review/                ← change-review 日志
│       └── _DIR.md
├── src/
│   ├── _DIR.md
│   └── app/
│       └── _DIR.md
├── scripts/
│   ├── _DIR.md
│   ├── governance-publish.sh ← 共享治理状态经 PR 发布
│   ├── render-roadmap.mjs    ← roadmap AUTO 段确定性渲染
│   └── validate-change.mjs   ← propose/dispatch/review 结构校验
├── public/
│   └── _DIR.md
├── .github/
│   ├── _DIR.md
│   └── workflows/
│       ├── _DIR.md
│       ├── ci.yml
│       ├── propose.yml
│       ├── dispatch.yml
│       └── review.yml
├── .env.local                 ← 环境变量模板
└── .gitignore                 ← 已包含 .worktrees、环境变量、依赖与构建产物
```

## Skills 安装

init.sh 会把框架 skills 复制为项目自有的可移植版本，并为 Claude Code 建相对链接：

```
.agents/skills/               ← 真实目录；Codex / 其他 agent 使用
  ├── module-designer/
  ├── prd-writer/
  ├── change-propose/
  ├── change-dispatch/
  └── change-review/

.claude/skills/                ← 指向 ../../.agents/skills/... 的相对符号链接
  ├── module-designer/
  ├── prd-writer/
  ├── change-propose/
  ├── change-dispatch/
  └── change-review/
```

> skill 协议 runner-agnostic，但 runner 仍须具备项目工具链、agent CLI、Git/GitHub 写入凭证和网络。项目移动到另一台机器后，skills 不依赖原框架绝对路径。

OpenSpec 1.6 初始化时可能提示 `openspec/project.md` 属于 legacy context。这里无需删除：本框架在 `openspec/config.yaml` 的 `context` 中显式引用它，并继续用它维护详细技术基线与 Directory Structure。

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

初始化已生成 propose / dispatch / review 三个 workflow。在仓库 Secrets 配置：

- `OPENAI_API_KEY`：Codex CLI 调用模型。
- `DISPATCH_GITHUB_TOKEN`：具备分支、PR 与合并所需权限的 token；同时保证 agent push 能触发后续 CI/workflow。

使用专用、最小仓库权限的 fine-grained PAT 或 GitHub App token，不要复用个人高权限 token。三个 workflow 都从受信任的 `main` checkout，支持手动触发和 schedule，并使用 concurrency key 防止同类运行重叠；它们只适合 GitHub-hosted 临时 runner。

### 方式 E — 一次性手动触发

任何支持 skill 调用的 agent 都可手动执行 `/change-dispatch`。

## 初始化验证

```bash
# 确认依赖安装
pnpm install

# 确认代码质量
pnpm test
pnpm lint
pnpm build

# 确认文件存在
ls AGENTS.md CLAUDE.md openspec/project.md openspec/config.yaml product/backlog.md \
  .github/workflows/ci.yml .github/workflows/propose.yml \
  .github/workflows/dispatch.yml .github/workflows/review.yml \
  scripts/governance-publish.sh scripts/validate-change.mjs src/_DIR.md
```

## CI 与合并策略

`init.sh` 已生成 `.github/workflows/ci.yml`（test / lint / build），dispatch 的每次 push 与 PR 都会触发。

`change-review` 在 feature branch 最新 SHA 上完成本地 CI、rebase 和三维 Verify 后才允许合并 implementation PR。合并后的 specs/archive/backlog 更新再通过 deterministic governance PR 发布；所有 main 写入都兼容 branch protection。

**推荐仓库设置：**

1. main 要求通过 PR 合并，禁止 force push。
2. 将 CI workflow 的 `ci` job 配置为 required check。
3. 开启 "Allow auto-merge"，供无人值守运行在 checks 通过后继续。

checks pending 时 review 会进入 PENDING/auto-merge，下一次定时扫描从 PR 状态续跑。仓库若要求人工 approving review，自动化会等待而不是绕过规则。

## 下一步

初始化完成后，把原始想法放到 `design/inputs/`，运行 `/design` 生成模块和第一批 backlog，然后进入 [02-backlog.md](./02-backlog.md)。
