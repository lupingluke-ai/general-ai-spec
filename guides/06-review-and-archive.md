# 审查、验证与归档

本阶段由交互式 agent 或定时 `review.yml` 调用 `change-review`。目标是：在实现合并前完成所有硬检查，再用可恢复的 governance PR 发布归档与共享治理状态。

## 触发方式

- 手动：告诉 agent “审查已完成的 change”或指定 change-id。
- 定时：`/loop <interval> /change-review`。
- GitHub Actions：生成的 `review.yml` 支持 schedule 与 `workflow_dispatch`。

定时触发很重要：required checks、auto-merge 或 governance PR 可能跨越一次运行；下一轮会从远端 durable checkpoint 续跑。

## 完整状态机

```text
Draft implementation PR + tasks: review
  → 审查 / 分形同步 / CI 修复
  → rebase 最新 main
  → 合并前 R1–R4 + 三维 Verify
  → implementation PR ready / merge / auto-merge
  → main-side coherence prep
  → governance archive PR
  → backlog + tasks: done
  → 删除 feature branch
```

| Implementation PR | Governance PR | 行为 |
|---|---|---|
| Draft/Open | 不存在 | 执行审查、CI、rebase、Verify、merge |
| Open + checks pending | 不存在 | 启用 auto-merge 或保持 PENDING |
| Open + checks red | 不存在 | 回修复循环；禁止 merge |
| MERGED | 不存在 | 准备 main-side sync 与 archive，创建 governance PR |
| MERGED | OPEN | PENDING，不重复 sync/move |
| MERGED | MERGED | 确认 archive 生效，幂等删除 feature branch |
| MERGED | CLOSED 未合并 | STOP，需处理关闭原因 |

## Step 1：发现待审查 Change

按以下证据交叉发现：

1. main backlog 中阶段为 `proposed` 且有 change-id。
2. 对应 feature branch 的 tasks.md 为 `review`。
3. Draft/Open implementation PR。
4. 历史 MERGED PR，但 main 中 change 尚未 archive。

若 feature branch 已删，也要查历史 PR；这使“实现已合并、归档未完成”的中断可恢复。

## Step 2：PR 审查

先运行：

```bash
node scripts/validate-change.mjs --change <change-id> --type <type> --phase review
```

再检查：

| 检查项 | 标准 |
|---|---|
| Spec | 实现匹配 proposal intent 与 design 文件清单 |
| Delta / optional specs | feature 有完整场景；其他类型无行为变化时有 `delta-specs: none` + reason |
| 范围 | 没有修改 main 治理禁区或 design 未声明实现文件 |
| 测试 | test / lint / build 可复现通过 |
| 分形文档 | 新文件有头注释，新目录有 `_DIR.md` |
| Commit | implementation commit 含 `Change-ID` |

设计偏离、范围越界、主 specs 语义冲突都必须 STOP；缺头注释、缺 change-owned `_DIR.md` 等机械问题可以自动修复。

## Step 3：Feature Branch 收敛

feature branch 只处理 change-owned 内容：

- change 新建目录的 `_DIR.md`。
- 新文件的 `@input/@output/@pos`。
- tasks 状态与 review 日志。
- main-shared `_DIR.md` 的待办只写进 change-owned `pending-sync.md`。

判断 `_DIR.md` 是否共享：

```bash
git ls-tree origin/main -- <path-to-_DIR.md>
```

命中表示 main 已存在，不能在 feature branch 修改；未命中表示 change-owned，可以随 implementation PR 合并。

## Step 3.5：本地 CI 与修复

依次运行：

```bash
pnpm test
pnpm lint
pnpm build
```

机械、可解释的类型/lint/build/test 问题最多自动修复两轮。需要新增未批准依赖、设计改动或环境密钥时 STOP，不猜测需求。

## Step 3.8：Rebase 最新 Main

```bash
git fetch origin main
git rebase origin/main
git push --force-with-lease origin <feature-branch>
```

`--force-with-lease` 只允许用于本步的 feature branch；main 永远禁止 force push。change-owned 文件冲突通常说明两个 change 范围重叠，应 STOP 让设计层裁决。

## Step 3.9：合并前三维 Verify

所有可能阻止交付的检查必须在 merge 前完成，并针对 rebase 后的最新 SHA。

### Completeness

- 所有 auto 组、文档组已 done；Verify 组由本步骤完成。
- 每个 delta 场景都有实现与测试/验证证据。
- optional empty specs 的 marker 与 reason 合法。
- 正常、边界/异常路径均被覆盖。

### Correctness

- 代码行为符合 proposal intent。
- test / lint / build 全绿。
- 没有 `[NEEDS-FIX]` 未解决项。

### Coherence

- 实际文件与 design 清单、任务组范围一致。
- 分形文档完整。
- main-shared 文档的变化已经进入 pending-sync 计划。
- R1–R4 交叉检查未发现 PRD/spec/design/tasks/implementation 偏离。

通过后勾选 Verify 任务组，commit/push tasks 与 review 证据；远端 required checks 必须针对这个最新 SHA。

## Step 4：合并 Implementation PR

```bash
gh pr ready <pr-number>
gh pr merge <pr-number> --merge
```

required checks 还在运行时：

```bash
gh pr merge <pr-number> --auto --merge
```

若仓库要求 approving review，则等待 review。不得降低保护规则或使用管理员绕过。

## Step 5：Main-side Coherence Prep

合并后更新本地 main，并先检查 archive checkpoint：

```bash
git checkout main
git pull --ff-only origin main
scripts/governance-publish.sh --check --skill change-review --scope <change-id>
```

- `PENDING`：立即结束，不重复执行。
- `MERGED`：确认 archive 已在 origin/main，进入分支清理。
- `READY`：继续准备。
- `STOP`：保留现场，报告语义冲突或关闭的 PR。

随后消费 pending-sync，更新 `openspec/project.md` 和 main-shared `_DIR.md`。这些改动只在本地 main 快照准备，最后随 archive governance PR 一次发布。

## Step 6：Sync 与 Archive

### Delta Specs

| 标记 | 动作 |
|---|---|
| ADDED | 追加到领域主 spec |
| MODIFIED | 替换对应 requirement |
| REMOVED | 删除对应 requirement |

optional empty specs 不改主 specs，但 `specs/README.md` 随 change 保留到 archive，形成审计证据。

### Change 与状态

1. 归档组 done；tasks YAML `status: done`。
2. 将 change 移到 `openspec/changes/archive/`。
3. 更新 `openspec/changes/_DIR.md` 与 `openspec/project.md`。
4. backlog 阶段改为 `done`。
5. 模块修订历史追加；若该模块全部 backlog done，模块 status 改为 done。
6. 运行 `node scripts/render-roadmap.mjs --write`，随后 `--check`。

### 发布

只暂存本 change allowlist 内路径，并调用：

```bash
scripts/governance-publish.sh \
  --skill change-review --scope <change-id> \
  --title "chore(<change-id>): archive and sync specs" \
  --commit-file <temp-message-file> -- \
  <explicit-allowed-paths...>
```

发布器会拒绝 allowlist 外 staged 文件。MERGED 后才能删除 feature branch；PENDING 时下轮从 `--check` 续跑。

## 恢复场景

| 中断点 | 下轮证据 | 恢复动作 |
|---|---|---|
| Verify 前 | implementation PR open、tasks review | 回 Step 2/3.5 |
| auto-merge 等 checks | PR open + autoMergeRequest | 等待，不重复提交 |
| 实现已合并 | implementation PR MERGED、change 仍 active | Step 5 |
| archive 本地已准备 | main worktree 有 allowlist 内 tracked diff | 恢复 staging/publish |
| archive PR OPEN | deterministic governance branch/PR | PENDING |
| archive PR MERGED、feature 未删 | archive 在 main | 幂等删除分支 |

日志只能辅助诊断，不用于判断流程所有权或完成状态；远端 branch、PR 与 tasks 才是 durable state。

## STOP 与 WARN

STOP 包括：范围越界、设计偏离、测试两轮仍失败、主 specs 语义冲突、required review 无法满足、archive PR 被关闭未合并、范围外 tracked 修改。

WARN 包括：机械问题自动修复成功、auto-merge 正在等待、历史 change 无 pending-sync、分支删除失败。WARN 不得掩盖未完成的 required checks。

## 下一步

归档完成后，backlog 与 tasks 都为 done，主 specs 和 roadmap 已同步。完整 Git/PR 状态机见 [09-git-github-workflow.md](./09-git-github-workflow.md)。
