# 审查、验证与归档

本阶段由交互式 agent（Claude Code / Codex）执行，使用 `change-review` skill。

## 触发方式

三种方式：

```
# 方式 1: 手动触发
你：审查已完成的 change
你：帮我 review 下 ai-voice-entry

# 方式 2: 定期触发（通过 /loop）
/loop 10m change-review

# 方式 3: dispatch push 后 CI 全绿，PR 更新可见
```

## 合并架构：Review + Auto-Merge 分工

Review skill **不直接 merge**。合并由 `auto-merge.yml` GitHub Actions 负责。

```
Review skill (Claude Code / Codex)      GitHub Actions (auto-merge.yml)
─────────────────────────               ──────────────────────────────
轮次 1:
  审查 → 分形同步 → 本地 CI 修复
  → gh pr ready                          → 检测 ready_for_review
                                          → gh pr merge --auto --merge
                                          → GitHub 等 required checks 通过后 merge commit
轮次 2:
  检测 MERGED → verify → archive
  → backlog: done
```

## 5-State Machine

每次 review skill 启动时，先用 `gh pr view` 判断 PR 状态，决定执行路径：

| PR 状态 | tasks.md status | 动作 |
|---------|----------------|------|
| Draft + open | review | **轮次 1**：审查 → 分形同步 → 本地 CI → `gh pr ready` |
| Open + Ready + CI green | review | **跳过**（等 auto-merge 合并） |
| Open + Ready + CI red | review | **回退**：`gh pr ready --undo` → 修复 → 重新 `gh pr ready` |
| MERGED | review | **轮次 2**：verify → archive → backlog: done |
| MERGED | done | **跳过**（已完成） |

## Step 1 — 发现待审查 Change

交互式 agent 通过以下方式发现待审查 change：

- 扫描 `product/backlog.md`，找到阶段为 `proposed` 的条目，fetch 对应 feature branch，读取 tasks.md 确认 `status: review`
- 或扫描 Draft PR 列表：`gh pr list --state open --draft`
- 或检查 CI 状态：dispatch push 后 CI 全绿即可触发审查

如果没有，输出 "No changes ready for review."

发现后，执行 `gh pr view <PR-number> --json state,isDraft,mergeStateStatus` 判断当前状态，进入对应路径。

## Step 2 — PR 审查

通过 Draft PR 审查 feature branch 上的全部变更：

| 检查项 | 说明 |
|--------|------|
| Spec 合规 | 实现匹配 design.md 文件清单和技术方案 |
| Delta Specs 合规 | 实现覆盖 delta specs 中的 ADDED/MODIFIED 场景 |
| 范围合规 | 只修改了 design.md 声明范围内的文件 |
| 测试通过 | CI 绿灯或本地 `pnpm test` |
| 分形文档合规 | 新文件有头注释，新目录有 `_DIR.md` |
| Change-ID | commit message 包含 `Change-ID: <change-id>` |

**问题处理策略：**
- **可自动修复**（缺 _DIR.md、缺头注释、格式问题）→ Step 3 中自动修复，继续流程
- **不可自动修复**（设计偏离、测试持续失败、范围越界）→ STOP，输出问题报告，等待人工决策

## Step 3 — 分形文档同步（仅 change-owned 部分）

在 feature branch 上（merge 前）**只处理 change 独占**的分形文档：

1. 更新 change 新建目录的 `_DIR.md`（main 上不存在）
2. 逐文件验证 `@input/@output/@pos` 头注释完整性
3. 提交分形文档更新到 feature branch 并 push

**判定规则（用 `git ls-tree origin/main --` 逐个 `_DIR.md` 测）：**

| 结果 | 含义 | 处理 |
|---|---|---|
| ❌ 未命中（change 新建目录） | change 独占 | 本步 Step 3 在 feature branch 更新 |
| ✅ 命中（main 已存在的共享 `_DIR.md`） | 跨 change 共享 | **推迟到 Step 6.1.5 在 main 上更新**，写入 `.logs/review/<change-id>.md` 的 "Step 6.1.5 待办" 段 |

**Feature Branch 禁改清单（Step 3 强约束）：** core/AGENTS.md 的治理层清单中所有条目都不得在本步修改（backlog / roadmap / modules / 主 specs / project.md / changes/_DIR.md / main 共享 _DIR.md）。命中即写 STOP 日志，不做自动还原。

## Step 3.8 — Rebase feature branch 到最新 main（强制）

在 `gh pr ready` **前**必须 rebase，消除 auto-merge 阶段的冲突窗口：

```bash
git fetch origin main
git checkout <branch-prefix>/<change-id>
git rebase origin/main
```

**三种场景：**

- **A 无冲突** → `git push --force-with-lease origin <branch>` → 远程 CI 重新运行；若可查询则等 CI 绿 → Step 4
- **B change-owned 文件冲突**（design.md 与其他 change 范围重叠）→ STOP + 日志，提示 Luke 回 `/design review M-NNN` 重排
- **C 治理层文件冲突**（说明 dispatch/其他 skill 意外写了禁改清单）→ STOP + 日志，提示 Luke 人工回滚

> main 分支禁止任何 force 推送；**`--force-with-lease` 仅本步允许**（因为 rebase 后 feature branch 历史被重写）。

## Step 3.5 — 本地 CI 验证与自动修复

在 `gh pr ready` 前，先在本地运行 CI 三件套并自动修复：

```bash
pnpm test && pnpm lint && pnpm build
```

**如果全部通过** → 进入 Step 4。

**如果失败** → 进入自动修复循环（最多 2 轮）：

### 可自动修复的错误类型

| 类型 | 示例 | 修复方式 |
|------|------|---------|
| TypeScript 类型错误 | 缺少导入、类型不匹配 | 读取错误信息，修改对应文件 |
| ESLint 规则违反 | unused import、格式问题 | `pnpm lint --fix` 或手动修改 |
| Next.js 构建错误 | Route export 限制、Suspense 缺失 | 根据错误信息修改对应文件 |
| 测试断言失败 | 预期值与实际值不匹配 | 分析原因，修改代码或更新测试 |

### 不可自动修复的错误类型

| 类型 | 示例 | 处理 |
|------|------|------|
| 设计方案偏离 | 架构与 design.md 不一致 | STOP |
| 依赖缺失 | 需要新增第三方包 | STOP |
| 环境配置问题 | 缺少环境变量 | STOP |

### 修复流程

```
Round 1: 读取错误 → 分析 → 修复 → commit + push → 重新运行 CI
  ↓ 如果仍失败
Round 2: 读取错误 → 分析 → 修复 → commit + push → 重新运行 CI
  ↓ 如果仍失败
STOP: 写入日志，输出问题报告，等待人工决策
```

## Step 4 — PR Ready（委托 Auto-Merge）

本地 CI 通过后，只执行 `gh pr ready`，**不直接 merge**：

```bash
# Draft PR → Ready for Review
gh pr ready <PR-number>
```

`auto-merge.yml` GitHub Actions 会自动：
1. 检测 `ready_for_review` 事件
2. 执行 `gh pr merge --auto --merge`
3. 由 GitHub 在 required checks 通过后执行 merge commit（保留完整历史）

**合并策略：merge commit（`--no-ff`）**，保留 feature branch 上的完整提交历史。

### 异常兜底：远程 CI 失败

如果 `gh pr ready` 后远程 CI 红灯：

```bash
# 回退到 Draft 状态
gh pr ready --undo <PR-number>

# 在 feature branch 上修复 → commit + push
# 重新进入 Step 3.5 本地 CI 验证
```

## Step 5 — 更新 main 上的治理层

auto-merge 合并完成后（轮次 2 开始时），在 main 上更新：

1. 更新 `openspec/project.md` 的 Directory Structure（如有变化）
2. 更新 `openspec/changes/_DIR.md` 索引表状态
3. **Sync main-shared `_DIR.md`**（Step 3 推迟的待办）：读 `.logs/review/<change-id>.md` 的 "Step 6.1.5 待办" 段，对每条在 main 上更新对应 `_DIR.md`

> 为什么迁移到 main：并发的多个 change 可能各自要在同一 `_DIR.md` 追加条目。feature branch 上改 → auto-merge 阶段相互冲突；main 上改 → 串行 + `git-safe-push` 协议按条目名主键合并，冲突自动化解。

**推送走 `core/git-safe-push.md` 协议**（3 轮 pull-rebase-push + 分段冲突策略）。3 轮失败写 `.logs/review/<change-id>.md`。

## Step 6 — Verify 三维度

### Completeness（完备性）

- [ ] tasks.md 中自动化任务组与「文档与分形同步」任务组已完成；「Verify」与「归档」任务组由 review/archive 本轮推进
- [ ] delta specs 中每个 ADDED/MODIFIED 场景都有对应实现
- [ ] delta specs 中每个 REMOVED 场景确认已不存在

### Correctness（正确性）

- [ ] 代码行为匹配 proposal.md 中的 Intent
- [ ] `pnpm test` 通过
- [ ] `pnpm lint` 通过
- [ ] `pnpm build` 通过

### Coherence（一致性）

- [ ] 实际目录结构匹配 design.md 的文件清单
- [ ] 所有新文件有 `@input/@output/@pos` 头注释
- [ ] 所有新目录有 `_DIR.md`
- [ ] `openspec/project.md` Directory Structure 已更新

## Step 7 — 归档

### 7.1 Sync Delta Specs

将 `openspec/changes/<change-id>/specs/` 合并到 `openspec/specs/`：

| 标记 | 动作 |
|------|------|
| ADDED | 追加到对应领域 spec 文件（不存在则新建） |
| MODIFIED | 替换对应领域 spec 文件中的旧版本 |
| REMOVED | 从对应领域 spec 文件中删除 |

### 7.2 Archive Change

1. tasks.md YAML 头 `status` → `done`
2. tasks.md 中除「归档」任务组外的 checkbox 已勾选；「归档」任务组在本步骤内勾选
3. 移动 change 目录 → `openspec/changes/archive/`
4. 更新 `openspec/changes/_DIR.md`

### 7.3 Update Backlog

更新 `product/backlog.md` 对应条目：
- 阶段 → `done`
- 确认关联的所有 change-id 都已归档

### 7.4 清理分支

```bash
# 删除远程 feature branch（<branch-prefix> 由类型派生：feat/ | fix/ | chore/ | hotfix/）
git push origin --delete <branch-prefix>/<change-id>

# 删除本地 feature branch
git branch -d <branch-prefix>/<change-id>
```

## 完成后的状态

```
product/backlog.md
  B-003: done, Change: ai-voice-entry

openspec/specs/ai-voice.md
  ← 包含从 delta specs 合并过来的完整需求规格

openspec/changes/archive/ai-voice-entry/
  ← 归档的四件套（保留完整历史）

feat/ai-voice-entry 分支已删除
```

## 一个完整周期的时间线示例

```
Day 1 10:00  用户录入 backlog B-003 (idea)
Day 1 10:05  交互式 agent 规划，生成四件套，创建 feat/ai-voice-entry + Draft PR (proposed)
Day 1 10:10  dispatch runner 领取 G0，在 worktree 中执行，完成后直接 push
Day 1 10:11  Draft PR 更新，CI 自动运行
Day 1 10:15  下一轮 dispatch fetch 到 G0 代码，G1-A/G1-B 被并行领取
Day 1 10:25  所有自动化任务完成，push 后 tasks.md status → review
Day 1 10:26  CI 全绿，Draft PR 展示完整代码
Day 1 10:30  用户触发 review（或 /loop 发现）
Day 1 10:32  轮次 1：审查 + 分形同步 + 本地 CI 修复 + gh pr ready
Day 1 10:33  auto-merge.yml：启用 --auto --merge，GitHub 等 CI 绿后 merge commit
Day 1 10:35  轮次 2（/loop 下一轮发现 MERGED）：verify + archive → backlog: done
Day 1 10:36  清理 feature branch
```

## 下一步

归档完成后，该 change 的生命周期结束。你可以继续处理 backlog 中的下一个需求。

状态协议的完整字段规范见 [07-status-protocol.md](./07-status-protocol.md)。
