# 常见问题

## 设计层

### Q: 为什么要引入设计层（design/）？

三个问题的答案：

1. **模块化抽象**：散落的 backlog 无法回答"系统由哪些模块组成"——设计层补齐了这一中间层。
2. **灵感收敛沉淀**：brainstorming / figma / 访谈原始信息集中到 `design/inputs/`，不再散落四处。
3. **模块边界防越界**：PRD / four-piece-set 阶段频繁出现 "scope 越界"——`module-ref` 把每条 backlog 锚定到固定模块边界上。

详见 [12-design-layer.md](./12-design-layer.md)。

### Q: 历史项目迁入，backlog 没有"模块"列怎么办？

不强制回填。自动化 skill 对"模块"列为 `—` 的行会自动跳过模块/roadmap 同步：

- `prd-writer` Step 2.2 提示 Luke 补模块（可通过 `/design review M-NNN` 追加），补齐前拒绝生成 PRD
- `change-propose` Phase 0 跳过并写日志
- `change-review` Step 6.3.2 跳过模块/roadmap 更新

建议渐进式迁移：有空时 `/design review M-NNN` 把历史条目挂到具体模块。

### Q: 模块边界调整怎么处理？

分两档：

- **小幅调整**：PRD 或 propose 对话中发现 "scope 差一点点" → 提示 "要不要扩展 M-NNN 的边界？" → 回到 `/design review M-NNN` 调整 → 回到原 skill 继续
- **大幅越界**：本质上属于另一个模块 → 拒绝当前对话 → 拆到新 backlog 挂到对应模块

**硬约束**：change 执行期不得调整模块边界（必须回到设计层重排）。

### Q: 一个 backlog 可以属于多个模块吗？

不行。`1 backlog : 1 PRD : 1 change : 1 模块` 是硬约束。跨模块需求必须在 `/design` 阶段拆成多条 backlog。

### Q: `/design` 和 `/brainstorming` 的关系？

- `/brainstorming` 是上游：灵感产出写到 `design/inputs/brainstorming/`
- `/design` 是下游：消费 inputs 素材，产出模块 + backlog

可以先 `/brainstorming` 再 `/design`，也可以直接 `/design`（module-designer 会提示是否需要先录入灵感）。

---

## PRD 阶段

### Q: 每个需求都必须写 PRD 吗？

必须。**所有 backlog 都要经过 `/prd B-NNN`** 产出 PRD（Full 或 Lite，由 type 决定）。这是 change-propose 的硬前置。

bug / chore / hotfix 自动用 Lite 模板（省去成功指标等产品字段，保留 Must Have + AC）。feature 用 Full 模板。

### Q: PRD 和 proposal 有什么区别？

| | PRD | Proposal |
|---|---|---|
| 视角 | 产品（what & why） | 技术（how） |
| 内容 | 用户故事、功能需求、验收标准 | 技术路线、文件清单、并行策略 |
| 审阅者 | 用户/PM | Claude Code 自动 pre-flight |
| 位置 | `product/prd/` | `openspec/changes/<id>/` |
| 生命周期 | 长期保留 | 随 change 归档 |

### Q: PRD approved 后需求变了怎么办？

两个选择：
1. 如果 change 还没开始执行：直接修改 PRD 内容，保持 `approved`
2. 如果 change 已在执行中：将旧 PRD 标记为 `superseded`，创建新版 PRD

### Q: 一个 PRD 对应几个 change？

**严格 1:1**。PRD frontmatter 的 `change-id` 是单值字段，`change-propose` 会检查 `<branch-prefix>/<change-id>` 远程分支不存在才允许生成四件套——一个 PRD 只能触发一次 propose。

如果产品能力较大、实现需要切成多块（基础设施 / UI / 集成），在 **backlog 层**拆成多条 B-NNN：

```
B-003  AI 语音记账 - 基础设施     → PRD-003 → change: ai-voice-infra
B-004  AI 语音记账 - UI 输入       → PRD-004 → change: ai-voice-ui
B-005  AI 语音记账 - 历史记录集成  → PRD-005 → change: ai-voice-history
```

三条 backlog 通过 `depends-on` 声明顺序（B-004 depends-on B-003 等）。拆分由 `module-designer` 在 `/design` 对话中驱动（不再由 prd-writer 承担）。

**为什么不支持 1:N？** 维持 1:1 是为了让 `/loop 15m /change-propose` 的自动触发路径零阻塞——它只需要判断"PRD approved 且未 proposed"，不需要追踪"PRD 下还有哪些 change 没生成"。高度自动化是本框架的一级约束。

---

## 规划阶段

### Q: 小修复也需要走四件套吗？

不需要。change-propose 适用于需要 OpenSpec 管理的功能变更。小修复（bug fix、文案修改、配置调整）可以直接用 Claude Code 或手动完成，无需创建 change。

判断标准：如果修改只涉及 1-2 个文件且不改变系统行为，直接改就行。

### Q: 需求不清楚怎么办？

回到设计层：

```
你：/design           ← 或 /design review M-NNN
→ module-designer 与你对话：建模块 + 划边界 + 拆 idea
→ backlog 新增 N 条 B-NNN（带"模块"列 M-NNN）
→ /prd B-NNN 逐条生成 PRD
→ PRD approved 后再 /change-propose
```

拆分粒度判定在 `/design` 阶段由 module-designer 完成（读取 module 边界 + 硬拆信号）。

### Q: 一个 backlog 条目需要拆成几个 change？

看拆分信号。常见拆法：
- 按层级拆：基础设施（类型/工具）→ UI 组件 → 页面集成
- 按模块拆：用户模块 → 账单模块 → 统计模块
- 按功能拆：创建能力 → 编辑能力 → 删除能力

拆分后在 proposal.md 中写清依赖关系，tasks.md 用 `depends-on` 字段声明。

### Q: tasks.md 里可以写代码吗？

**不可以。** tasks.md 是简洁的 checkbox 清单。dispatch（任意 runner）从三个来源获取上下文：
1. tasks.md 的任务描述（做什么）
2. design.md（怎么做、文件清单）
3. 代码库（已有模式和约定）

---

## 执行阶段

### Q: dispatch runner 没有自动领取任务？

检查以下几点：

1. 所选 runner 是否配置正确（Codex Automation 的名称/schedule/worktree；`/loop` 是否在运行；cron 是否加载；GH Actions 是否启用）
2. tasks.md 的 `status` 是否为 `ready`
3. `depends-on` 中的前置 change 是否都已 `done`
4. 是否有任务组的 `status` 为 `pending` 且 `执行工具: Codex`（= 自动化任务组）

### Q: dispatch 执行出错了怎么办？

1. 查看所选 runner 的日志（Codex Desktop Automation 历史 / `/loop` 输出 / `.logs/dispatch/cron.log` / GH Actions run history）
2. 如果是代码问题：切到对应分支手动修复，保留 `Change-ID`
3. 如果是配置问题：修复后，下一轮 runner 会自动重试
4. 如果反复失败：将任务组的 `执行工具` 改为 `Claude Code`，手动执行

### Q: 可以手动触发 dispatch 执行吗？

可以。任意 agent 手动执行 `/change-dispatch` 即可（Codex Desktop 也可手动运行 Automation），不用等 5 分钟周期。

### Q: 并行任务组出现文件冲突怎么办？

说明 design.md 的并行设计有误。应该：
1. 将冲突的任务组改为串行
2. 或者拆分文件，消除写入冲突
3. 更新 tasks.md 的任务组约束

---

## 审查阶段

### Q: 审查发现 dispatch 实现不符合 spec 怎么办？

Claude Code 会标记具体分支和问题。你有三个选择：
1. **修复**：切到分支修改，commit 后重新审查
2. **跳过**：跳过该分支，手动实现对应功能
3. **放弃**：回退整个 change，重新规划

### Q: verify 失败怎么办？

看是哪个维度：
- **Completeness 失败**：有任务没完成或 delta specs 场景没覆盖 → 补充实现
- **Correctness 失败**：test/lint/build 不过 → 修代码
- **Coherence 失败**：目录结构或文档不一致 → 补 _DIR.md 和头注释

修复后重新运行 verify。

### Q: 归档时 sync delta specs 的具体操作是什么？

Claude Code 自动执行：

```
change 的 specs/ai-voice.md 中的 ADDED Requirements
  → 追加到 openspec/specs/ai-voice.md

change 的 specs/ai-voice.md 中的 MODIFIED Requirements
  → 替换 openspec/specs/ai-voice.md 中对应的旧版本

change 的 specs/ai-voice.md 中的 REMOVED Requirements
  → 从 openspec/specs/ai-voice.md 中删除
```

---

## 分形文档

### Q: 什么是分形文档？

两个核心机制：

1. **`_DIR.md`** — 每个目录一个，说明目录职责、子目录分工、关键入口
2. **`@input/@output/@pos` 头注释** — 关键源码文件的头部注释，说明输入、输出和在系统中的位置

### Q: 什么时候更新分形文档？

**写代码时同步更新，不是写完代码再补。**

- 新建文件 → 写头注释
- 新建目录 → 创建 _DIR.md
- 修改文件 → 检查头注释是否需要更新
- 修改目录结构 → 更新相关 _DIR.md
- 顶层结构变化 → 更新 openspec/project.md

### Q: 头注释格式是什么？

```typescript
/**
 * @input 这个文件接收什么输入
 * @output 这个文件产出什么输出
 * @pos 这个文件在系统中处于什么位置
 */
```

---

## Git / 并发

### Q: Review 结束后 auto-merge 阶段远端仓库出现冲突，怎么办？

典型根因是三类中的一种（见 [09-git-github-workflow.md](./09-git-github-workflow.md) "三类冲突"）：

1. **feature branch 写到 main 共享文件**（`product/backlog.md` / `design/roadmap.md` / `openspec/specs/**` / 主 `_DIR.md` 等）→ 两个 change 在各自 feature branch 都改同一段 → auto-merge 两次合并时物理冲突
2. **auto-merge 期间 main 又前进了**（别的 change 先合并）→ 当前 PR 的 base 过期 → GitHub 标记 "需要更新"
3. **多个 skill 并发 push main**（/loop 15m + /loop 10m + 任意 dispatch runner + 人工）→ 第二个被拒 (non-fast-forward)

当前版本已经把三类全部系统化防住：

- 类型 1 → `core/AGENTS.md` 的 "Feature Branch 治理层禁改清单" + `change-review` Step 3 只处理 change-owned 分形文档 + dispatch D1 / review R1 双检查点
- 类型 2 → `change-review` Step 3.8 rebase-before-ready（`gh pr ready` 前强制 rebase `origin/main`，force-with-lease push）
- 类型 3 → `core/git-safe-push.md`（3 轮 pull-rebase-push + 分段冲突策略；主 specs 冲突 → STOP）

遇到冲突时按 `.logs/review/<change-id>.md` 的 STOP 日志判断类型：
- 治理违规 → 人工回滚该 commit（禁改清单说明之）
- Step 3.8 conflict B / C → 回 `/design review M-NNN` 或人工介入
- git-safe-push 3 轮失败 → 按日志中的冲突段人工 merge 后续跑

### Q: 为什么 main 禁止 force push，feature branch 却允许？

main 是协作基线：force push 会丢掉其他人已经合并的提交，且多个 skill + /loop 并发时会随机覆盖彼此的更新。

feature branch 的 force-with-lease 仅在 `change-review` Step 3.8 rebase-before-ready 允许——rebase 改写了 feature branch 历史但没有丢任何人的工作（所有合并都尚未发生）。且 `--force-with-lease` 会在远端有新提交时失败，防止误覆盖。

其他时候（dispatch push / Claude Code 分形 sync push）都用普通 push + `git pull --rebase`。

---

## 通用

### Q: 这套流程适合几个人的团队？

设计上适合 1-3 人的小团队，配合 AI 工具（Claude Code 规划 + 任意 dispatch runner 执行）实现高效开发。核心思路是用 AI 承担规范化流程（规划、文档、验证），人只负责决策和需求。

### Q: 没有 Codex Desktop 能用吗？

可以。dispatch skill 本身 runner-agnostic，选下面任一方式即可：

1. **Claude Code `/loop`**：`/loop 5m /change-dispatch`（零配置）
2. **cron**：`*/5 * * * * claude -p "/change-dispatch"` 或 `codex exec "/change-dispatch"`
3. **GitHub Actions**：定时 workflow 调用 runner
4. **一次性手动**：任意 agent 运行 `/change-dispatch`
5. **人工实现**：直接按 tasks.md 逐项实现代码

详见 `skills/change-dispatch/SKILL.md` 的「Runner 配置」。

### Q: 哪些文件是 AI 自动维护的，哪些需要人工维护？

| 文件 | 维护者 |
|------|--------|
| `design/inputs/**` | 人工（原始灵感，永久保留） |
| `design/_DIR.md` / `design/modules/_DIR.md` / `design/inputs/_DIR.md` | 人工（偶尔更新） |
| `design/roadmap.md` 人工段（愿景 / 原则 / 里程碑） | 人工 |
| `design/roadmap.md` AUTO 段（ARCHITECTURE / DEPENDENCIES / PROGRESS） | AI（多 skill 按责任行各自维护，勿手改）|
| `design/modules/M-NNN-*.md`（frontmatter / 人工段） | AI（module-designer 主写） |
| `design/modules/M-NNN-*.md`（## 关联 Backlog / ## 修订历史） | AI（多 skill 追加自己的行） |
| `product/backlog.md` 需求内容 + 模块列 + type 列 | AI（module-designer 建行）/ 人工（补录） |
| `product/backlog.md` 阶段 / PRD / Change 列 | AI（按阶段 skill 自动更新） |
| `product/prd/PRD-NNN.md` | AI（prd-writer 主写）/ 人工（approved 决策） |
| `openspec/changes/*/` 四件套 | AI（change-propose 主写 + dispatch 更新） |
| `openspec/specs/` 主 specs | AI（change-review 归档时自动 sync） |
| `openspec/project.md` 目录结构 | AI（分形同步时更新） |
| `_DIR.md` / 头注释 | AI（写代码时同步） |
| 业务代码 | AI（dispatch runner / Claude Code） |
