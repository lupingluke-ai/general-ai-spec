# 执行阶段：dispatch 自动开发

本阶段由 **任意 runner**（Codex Desktop Automation / Claude Code `/loop` / cron / GitHub Actions / 一次性手动触发）调用 `change-dispatch` skill 执行。skill 本身与具体 agent 解耦，只要环境具备 git + shell + 网络即可运行。

## 前提

- 已选好并配置至少一种 runner（见 [01-initialization.md](./01-initialization.md)）
- 至少有一个 change 的 tasks.md `status: ready`
- Runner 具备网络权限：`github.com` 和 `registry.npmjs.org`

## Runner 配置（任选其一）

详细清单见 `skills/change-dispatch/SKILL.md` 的「Runner 配置」章节，摘要如下：

### 方式 A — Claude Code `/loop`（推荐开发期）

```
/loop 5m /change-dispatch
```

### 方式 B — Codex Desktop Automation（推荐 24/7 无人值守）

```
Name:     change-dispatch
Schedule: every 5 minutes
Worktree: yes (隔离执行)
Network:  allow github.com, allow registry.npmjs.org
Prompt:   使用 $change-dispatch 扫描并执行就绪的任务组
```

### 方式 C — cron

```cron
*/5 * * * * cd /path/to/repo && claude --dangerously-skip-permissions -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
# 或使用 Codex CLI：
# */5 * * * * cd /path/to/repo && codex exec "/change-dispatch" >> .logs/dispatch/cron.log 2>&1
```

### 方式 D — GitHub Actions

`.github/workflows/change-dispatch.yml`：定时触发 runner，详见 SKILL.md。

### 方式 E — 一次性手动触发

```
/change-dispatch
```

> **执行工具 tag 语义**：tasks.md 里的 `执行工具: Codex` 表示"自动化任务组"，任意 runner 都可领取；`执行工具: Claude Code` 表示"交互式任务组"，由 change-review 或人工承接。tag 字面值保留是为了向后兼容。

## 自动执行流程

### 每 5 分钟（或配置的间隔）自动触发

Runner 按配置的 schedule 调用 dispatch skill：

```
change-dispatch 启动
  ↓
Step 1: 从 main 的 backlog.md 扫描活跃 change
  → 筛选阶段为 proposed（执行细粒度由 tasks.md YAML status 承担）
  → 从 change-id 前缀派生 branch-prefix（feat/ | fix/ | chore/ | hotfix/）
  → 推导 feature branch: <branch-prefix>/<change-id>
  ↓
Step 2: fetch 并读取 feature branch 上的 tasks.md
  → git fetch origin <branch-prefix>/<change-id>
  → git show origin/<branch-prefix>/<change-id>:openspec/changes/<change-id>/tasks.md
  → 筛选 status: ready 或 executing
  → 检查 depends-on 前置 change 是否都 done
  ↓
Step 3: 选择任务组
  → 找第一个 status: pending 的自动化任务组（`执行工具: Codex`）
  → 跳过交互式任务组（`执行工具: Claude Code`）
  → 检查前置任务组约束
  ↓
Step 4: 环境准备（推荐在 worktree 中）
  → git checkout <branch-prefix>/<change-id>
  → git pull origin <branch-prefix>/<change-id>
  → pnpm install
  ↓
Step 5: 执行任务
  → 读 design.md 获取文件清单
  → 读代码库理解项目模式
  → 逐项实现 checkbox 任务
  ↓
Step 6: 范围校验
  → git diff --name-only 与 design.md 文件清单对比
  → 确保无超范围文件（超范围 → STOP）
  ↓
Step 7: 更新状态、提交并推送
  → 勾选对应 checkbox
  → 任务组 status: executing → done
  → 如果所有自动化组完成: change status → review
  → git commit + git push origin <branch-prefix>/<change-id>
```

> `<branch-prefix>` 由 change-id 字符串前缀零 I/O 派生：`hotfix-` → `hotfix/`、`chore-` → `chore/`、`fix-` → `fix/`（严格 4 字符）、其余 → `feat/`。详见 [11-task-types.md](./11-task-types.md)。

### dispatch push 后的自动效果

- **Draft PR 自动更新**——展示最新代码变更
- **GitHub CI 自动运行**——test + lint + build
- **Claude Code 可感知**——通过 PR 状态、CI 结果、或 runner 通知（Codex Automation inbox / `/loop` 输出 / cron 日志 / GH Actions run history）

### 并行执行

```
G0 (串行，必须先完成)
  ↓ G0 push 后，下一轮 dispatch fetch 到最新代码
G1-A ∥ G1-B ∥ G1-C  (并行，各自 worktree，push 时 rebase 解决冲突)
  ↓ 全部完成
标记 change status: review
```

- **同一 change 的串行组**：按顺序领取（G0 先于 G1）
- **同一 change 的并行组**：可被同一轮次的不同 runner 实例领取，各自 worktree 隔离
- **不同 change**：完全隔离（不同 feature branch），可同时执行
- **所有任务组在同一个 `<branch-prefix>/<change-id>` 分支上提交**
- **Push 冲突**：通过 `git pull --rebase` 解决

## 自动化任务组执行规范

每个自动化任务组（`执行工具: Codex`）执行时遵循：

1. **读取 design.md** — 文件清单、技术方案、接口设计
2. **读取代码库** — 理解已有模式和约定
3. **新建文件** — 必须包含 `@input/@output/@pos` 头注释
4. **新建目录** — 必须包含 `_DIR.md`
5. **Commit message** — 必须包含 `Change-ID: <change-id>`
6. **更新 _DIR.md** — 创建新文件时，必须同时更新该目录已有的 `_DIR.md`，添加新文件条目
7. **完成后直接 push** — 推送到 feature branch

## 状态更新时机

| 事件 | tasks.md 变更 | backlog 变更 |
|------|--------------|-------------|
| 领取任务组 | 任务组 status → executing | — |
| 完成任务组 | checkbox 勾选, 任务组 status: executing → done | — |
| 所有自动化组完成 | YAML 头 status → review | 保持 proposed（backlog 细粒度由 tasks.md status 承担，dispatch 禁碰 main） |

## 你能看到什么

取决于所选 runner：

| Runner | 运行状态 | 通知 |
|--------|---------|------|
| Codex Desktop Automation | Codex Desktop → Automation 历史 | Inbox 通知 |
| Claude Code `/loop` | CLI 实时输出 | 命令行日志 |
| cron | `.logs/dispatch/cron.log` | 无（需自行接通知） |
| GitHub Actions | Actions 页面 run history | GH 通知 / email |

在 GitHub 上（所有 runner 共通）：

- **Draft PR** — 每次 push 后自动更新，展示四件套和代码变更
- **CI 状态** — push 触发 CI，可查看 test/lint/build 结果

## 异常情况

### 执行失败

如果某个任务组执行失败：

- Runner 日志中会显示错误
- 该任务组的 status 保持 `pending` 或 `executing`
- 下一轮 runner 会重新尝试
- 如果代码已提交但有问题，commit message 会包含 `[NEEDS-FIX]` 标记

### 依赖未满足

如果 change 的 `depends-on` 中有未完成的前置 change：

- dispatch 会跳过，输出 "No ready tasks found."
- 等前置 change 归档（status: done）后自动恢复

### Push 冲突

如果并行任务组（G1-A、G1-B）同时 push：

- 后 push 的一方通过 `git pull --rebase` 解决
- 如果文件冲突（理论上不应发生——design.md 保证并行组文件不交叉），标记 `[NEEDS-FIX]` 并通知

### 手动干预

如果需要手动修改 dispatch 生成的代码：

1. 切换到 feature branch `<branch-prefix>/<change-id>`
2. 修改代码
3. commit 时保留 `Change-ID: <change-id>`
4. push 到远程

## 不做什么

dispatch 有明确边界，**不做**以下事情：

- 审查代码质量
- 合并分支到 main
- 修改 main 上的任何文件（backlog、specs、project.md）
- 执行 `执行工具: Claude Code` 的任务组（交互式任务组）
- 运行 verify 或归档

这些都是 change-review 的职责。

## 下一步

当你在 runner 的输出/通知中看到任务完成，或者在 GitHub 上看到 Draft PR 更新且 CI 全绿，进入 [06-review-and-archive.md](./06-review-and-archive.md)。
