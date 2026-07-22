# Git 与 GitHub 完整工作流

本章是仓库写入、并发、PR、required checks 与中断恢复的统一事实说明。命令级细节以各 skill 和 `core/git-safe-push.md` 为准。

## 两类 PR，一条受保护主线

```text
governance/<skill>/<scope> ── governance PR ──┐
                                              ├──> main（稳定、受保护）
feat|fix|chore|hotfix/<change-id> ─ implementation PR ─┘
                 ↑
     worker/<change>/<group>/<claim>（短生命周期、本地唯一）
```

- `main` 是唯一稳定基线，任何 skill 都不得直接 push。
- 设计、PRD、propose 索引、archive 等共享状态通过确定性 governance branch 发布。
- 四件套与实现代码在一个 feature branch 上，通过一个 implementation PR 审查和合并。
- dispatch runner 只在自己的 detached worktree 与唯一 worker branch 中执行；最终以 fast-forward push 更新共享 feature branch。
- `resume-interview.md` 一类无关未跟踪文件不会因全仓暂存被带入，因为协议禁止无范围的 `git add -A`。

## 写入所有权

| 数据 | 写入者 | 发布通道 |
|---|---|---|
| `design/modules/`、新 backlog、roadmap | module-designer | governance PR |
| PRD draft / approved | prd-writer | governance PR |
| 四件套与实现 | propose / dispatch / review | implementation PR |
| backlog `proposed`、module/roadmap 索引 | change-propose | governance PR |
| 主 specs、archive、backlog `done`、共享 `_DIR.md` | change-review | governance PR |

dispatch 永远不改 main 治理文件。共享状态写入者即使不同，也统一经过 `scripts/governance-publish.sh`，从而兼容 branch protection 和 required checks。

## 阶段 1：Propose

1. 从最新 `origin/main` 建 `<branch-prefix>/<change-id>`。
2. 生成 proposal、design、tasks，以及 delta specs 或明确的 optional marker。
3. 运行 `node scripts/validate-change.mjs --phase propose`。
4. 显式暂存 change 目录和 propose 日志，commit 并 push feature branch。
5. 创建 Draft implementation PR。
6. 在本地 main 快照准备 backlog/module/roadmap 索引，通过 `governance/change-propose/<change-id>` PR 发布。
7. 只有 governance PR 已 MERGED，dispatch 才能从 main 的 `proposed` 索引发现该 change。

确定性 branch 名是 durable checkpoint。重复运行先执行：

```bash
scripts/governance-publish.sh --check --skill change-propose --scope <change-id>
```

- `MERGED`：索引已经生效，不重复提交。
- `PENDING`：等待 checks / review，不重复改文件。
- `READY`：尚未发布，可继续准备并发布。
- `STOP`：存在已关闭未合并 PR 或语义冲突，需要处理后重跑。

## 阶段 2：Dispatch 的原子认领

### 为什么不能直接 checkout 共享 feature branch

两个 runner 若同时基于同一 tasks 快照把不同组改为 `executing`，普通 commit 无法证明谁先拥有任务；同机多个 worktree 也不能安全地 checkout 同一共享本地分支。协议因此把“提交 claim”和“获得所有权”合并为一个远端 fast-forward 竞争。

### 正确序列

```text
fetch 远端 feature tip
  → detached worktree + 唯一 worker branch
  → 写 group-specific claim-id / claimed-at / heartbeat-at
  → commit claim
  → push HEAD:<feature>（fast-forward 竞争）
       ├─ 成功：本 runner 拥有该组
       └─ rejected：没有所有权；丢弃 claim、刷新、重新选组
```

失败的 claim 禁止 rebase 后再次 push，因为那会把两个“我拥有此组”的决定合并在一起。只有成功更新远端 tip 的 runner 才能开始实现。

### 执行与汇合

1. 每 20 分钟更新本组 `heartbeat-at`；stale 阈值为 150 分钟，大于单任务上限 120 分钟。
2. 只修改 design 声明的实现文件、change-owned `_DIR.md`、`pending-sync.md` 与本 change 日志。
3. 运行 test / lint / build。
4. 显式暂存并提交实现，确认 worktree 干净。
5. fetch + rebase 最新远端 feature tip。
6. 再确认 claim-id 仍属于本 runner，随后标记组 done 并清空 claim 字段。
7. push `HEAD:refs/heads/<feature>`；并发拒绝时按 group-id 合并 tasks 状态，最多重试三轮。

时间戳缺失或格式错误不能按 Unix epoch 解释为 stale；必须 STOP。回收 claim 时须精确匹配 group-id 与 claim-id，不能用模糊 grep 误伤其他组。

## 阶段 3：Review、Verify、Merge

```text
PR review
  → change-owned 分形文档同步
  → validate-change
  → test / lint / build（最多两轮可解释修复）
  → rebase origin/main
  → R1–R4 + 三维 Verify
  → 将 Verify 组标为 done 并 push 最新 SHA
  → gh pr ready
  → merge implementation PR
```

Verify 必须在 merge 之前完成：

- Completeness：tasks、delta/optional specs、验收场景全部有证据。
- Correctness：实现符合 proposal intent，test/lint/build 全绿。
- Coherence：变更范围、分形文档、目录结构与设计一致。

required checks 尚未完成时使用 `gh pr merge --auto --merge`。如果仓库要求人工 approving review，则保持 PENDING；不得绕过保护规则。

## 阶段 4：Archive Governance PR

implementation PR MERGED 后：

1. checkout 并 fast-forward 本地 main。
2. 检查 `governance/change-review/<change-id>` checkpoint。
3. 消费 `pending-sync.md`，更新 main-shared `_DIR.md` 和 `openspec/project.md`。
4. 将 delta specs 同步进主 specs；optional empty specs 不产生主 spec 变更。
5. 移动 change 到 archive，更新 backlog/module/roadmap。
6. 运行确定性 roadmap renderer 与 archive 完整性检查。
7. 仅暂存 allowlist 路径，通过 governance PR 发布。
8. governance PR MERGED 后才删除远端 feature branch。

若中断发生在 move 之后但 publish 之前，下轮只要本地 tracked 改动全部属于本 change allowlist，就恢复发布；出现范围外 tracked 修改则 STOP。与 allowlist 无关的未跟踪用户文件保持不动。

## Branch Protection 推荐配置

对 `main` 启用：

1. Require a pull request before merging。
2. Require status checks to pass；至少把 `ci` 设为 required。
3. 禁止 force push。
4. 开启 auto-merge，供无人值守 workflow 在 checks 通过后收尾。

自动化所用 token 必须能创建/更新分支、PR 和合并；GitHub Actions 模板使用 `DISPATCH_GITHUB_TOKEN`，因为默认 `GITHUB_TOKEN` 触发的 push 通常不会再触发下游 workflow。应使用仅限本仓库、最小权限的 fine-grained PAT/GitHub App token。仓库另需 `OPENAI_API_KEY` 供 Codex CLI 使用。

agent workflow 固定从受信任的 `main` checkout，外部 Actions 固定到不可变 commit，只在 GitHub-hosted 临时 runner 上使用无沙箱模式。不要让 fork PR、任意分支 workflow 或长期自托管 runner直接获得这些 secrets。

生成的 workflow：

| 文件 | 作用 |
|---|---|
| `ci.yml` | test / lint / build |
| `propose.yml` | 定时或手动扫描 approved PRD |
| `dispatch.yml` | 原子认领并执行 auto 任务组 |
| `review.yml` | 审查、预合并 Verify、实现合并与 archive 恢复 |

三个 agent workflow 都有 concurrency key，防止同类定时任务重叠；跨 runner 并发仍由远端 claim 协议保证。

## 冲突与恢复矩阵

| 现象 | 原因 | 自动恢复 |
|---|---|---|
| claim push rejected | 另一 runner 先更新 feature tip | 丢弃失败 claim、刷新并重选；不 rebase 失败 claim |
| 实现完成 push rejected | 另一组先汇合 | fetch/rebase，按 group-id 合并 tasks，再验 ownership |
| stale claim | runner 异常退出且 heartbeat 超过 150 分钟 | 精确 group/claim 回收；空时间戳 STOP |
| implementation PR 冲突 | main 前进或文件范围重叠 | 合并前 rebase；change-owned 冲突 STOP |
| governance PR OPEN | checks 或 review 未结束 | `--check` 返回 PENDING，下一轮续跑 |
| governance PR MERGED | 上轮已发布但未清理 | `--check` fast-forward main，进入幂等清理 |
| governance PR CLOSED 未合并 | 人工关闭或策略拒绝 | STOP，不覆盖历史决定 |
| roadmap AUTO 冲突 | 多个治理写入同时更新派生视图 | 先按 ID 合并事实源，再运行 renderer 全量重建 |
| 主 specs 语义冲突 | 两个 change 修改同一行为规格 | STOP，人工裁决；禁止自动拼接 |
| required check 红 | 远端环境失败 | 回到修复循环，禁止 merge |
| required check pending | 正在运行 | auto-merge / PENDING，定时 review 续跑 |

## 安全暂存

所有脚本与 skill 都应使用显式路径：

```bash
git add -- path/declared-in-design.ts
git add -- openspec/changes/<change-id>/tasks.md
```

删除/移动 change 目录时允许路径限定的 `git add -A -- <old-path> <new-path>`，因为 Git 需要记录删除；禁止没有 pathspec 的全仓暂存。

`scripts/governance-publish.sh` 会再次检查 staged 文件是否全在调用方 allowlist 内。该双层约束防止把用户草稿、别的 change 或环境文件带入提交。

## Commit 约定

| 阶段 | 示例 | 最终进入 |
|---|---|---|
| module-designer | `design(M-002): voice entry + 3 backlog ideas` | governance PR |
| prd-writer | `docs(PRD-003): draft PRD for B-003` | governance PR |
| prd-writer approved | `docs(PRD-003): approved` | governance PR |
| change-propose | `feat(ai-voice-entry): propose change` | implementation PR |
| dispatch | `feat(ai-voice-entry): implement G1-A` | implementation PR |
| change-review fix | `fix(ai-voice-entry): resolve review findings` | implementation PR |
| change-review archive | `chore(ai-voice-entry): archive and sync specs` | governance PR |

feature/dispatch/review implementation commits必须包含：

```text
Change-ID: <change-id>
```

## 不变量

1. main 无直接 push、无 force push。
2. implementation merge 前已完成最新 SHA 的三维 Verify。
3. dispatch claim 的远端 fast-forward 成功是唯一所有权证明。
4. 同一 runner 只清理自己的 worktree 与 worker branch。
5. 共享治理状态只经 deterministic governance branch + PR 发布。
6. 所有中断点都能由远端 PR/branch/tasks 状态推断，不能依赖易丢失的本地日志。
7. 日志是观测证据，不是任务状态的数据通道。

## 下一步

查看 [10-extras.md](./10-extras.md) 了解日志、worktree 与扩展配置；任务类型与状态映射见 [11-task-types.md](./11-task-types.md)。
