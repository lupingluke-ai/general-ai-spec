# AGENTS.md — AI Agent Runtime Contract

> 本文件是 AI Agent（Claude Code / Codex / Cursor / 其他）在本项目中的最小运行契约。
> `guides/` 是给人的操作手册，不作为 agent runtime 规则源。

## Rule Sources

Runtime 规则源：
- `AGENTS.md`：框架运行契约、阶段入口、Git 边界与硬禁令
- `openspec/project.md`：当前项目技术栈、架构基线、目录职责与实现顺序
- `openspec/config.yaml`：本框架叠加到 OpenSpec 之上的治理规则（backlog / PRD / change / verify / archive）
- OpenSpec 官方 skills / commands：由 `openspec init` 安装到当前 agent 目录（如 `.codex/skills/openspec-*`、`.claude/skills/openspec-*`），提供 proposal / delta spec / validate / archive 的底层规则
- `skills/*/SKILL.md`：当前阶段的执行细则、STOP / WARN 条件与日志协议
- `core/git-safe-push.md`：main 分支安全推送协议
- 相关目录 `_DIR.md`：局部目录职责、输入输出与位置约束

冲突优先级：硬边界 / Git 禁令 > 当前阶段 `SKILL.md` > `openspec/config.yaml` > OpenSpec 官方 skills / commands > `openspec/project.md`。`guides/` 只作人工操作手册，不参与 runtime 优先级。

遇到 OpenSpec change / spec / proposal / archive 相关任务时，使用当前 agent 已安装的 OpenSpec 官方 skills / commands（如 `openspec-propose`、`openspec-apply-change`、`openspec-archive-change`）并读取 `openspec/config.yaml`。这里只接入 OpenSpec 官方 proposal、delta spec、validate、archive 规则；主开发路径仍以本文件和 `skills/*/SKILL.md` 为准。

## Operating Posture

- 不静默假设：关键不确定性先说明；涉及产品决策、模块边界、安全风险或破坏性 Git 操作时先停下确认。
- 简单优先：不为未来假设加抽象、配置、兼容层或单次使用框架。
- 外科手术式修改：只改完成当前请求必需的文件；不顺手重构、改格式或清理无关代码。
- 目标可验证：开始前明确 done 条件；结束前用测试、lint、build、diff check 或三维 verify 证明完成。
- 不写兼容性代码（backwards-compat shim、feature flag 占位、renamed-alias 再导出、`// removed` 注释占位等），除非用户明确要求。
- 项目可在本节追加称呼、语气、沟通偏好；core 默认不绑定具体用户。

## Framework Contract

本项目采用四套纪律：
- **设计层**：`design/inputs` 原始输入、`design/modules/M-NNN-*.md` 模块边界、`design/roadmap.md` 全局 AUTO 图谱
- **产品 Backlog**：`product/backlog.md` 是需求全景；每条 backlog 必须归属一个模块 `M-NNN`（历史迁入可为 `—`）
- **OpenSpec**：管理 PRD 后的 proposal、delta specs、design、tasks、verify、archive
- **分形文档**：每个目录 `_DIR.md`，关键文件 `@input/@output/@pos` 头注释

五层架构固定为：`design/inputs` → `design/modules` → `product/backlog.md` → `product/prd/` → `openspec/changes/`。

硬约束：一条 backlog / PRD / change 只归属一个模块；跨模块需求必须在 `/design` 阶段拆分。

## Task Intake

收到开发请求时先判断：**对应模块**、**需求边界**、**影响范围**。

| 情况 | 主路径 |
|------|--------|
| backlog 已就绪（模块列填齐，PRD approved） | `/change-propose B-NNN` → dispatch runner → `/change-review` |
| backlog 已就绪但无 PRD | `/prd B-NNN` → 用户审阅 PRD → `/change-propose` → dispatch runner → `/change-review` |
| 新想法 / 模糊灵感，无对应模块 | `/design` → `module-designer` 建模块 + 拆 idea → `/prd B-NNN` → 后同上 |
| 已有模块但缺新 backlog | `/design review M-NNN` → 追加 backlog → `/prd B-NNN` → 后同上 |
| 需要深度头脑风暴 | `/brainstorming` 写 `design/inputs/brainstorming/` → `/design` → 后同上 |

PRD approved 后，`change-propose`、dispatch runner 与 `change-review` 可按人工触发或定时触发协作；具体频率和 runner 配置见对应 `skills/*/SKILL.md`。

## Context Intake

原则：**先读文档，再写代码。**

- 全局：`product/backlog.md`、`openspec/project.md`、相关目录 `_DIR.md`
- backlog / PRD：对应 `product/prd/PRD-NNN.md`、`design/modules/M-NNN-*.md`、PRD `design-inputs`
- change：`openspec/changes/<change-id>/` 四件套、相关 `openspec/specs/**`、受影响源码

各阶段更细的必读清单与 STOP / WARN 规则以对应 `skills/*/SKILL.md` 为准。

## Artifact Contract

- **任务类型与命名**：feature / bug / chore / hotfix 走同一流程；branch、commit、PR title、PRD 模板与 trailer 以 `openspec/config.yaml` 的 `task-types` 为准。
- **Change 四件套**：每个 change 必须包含 `proposal.md` + `specs/` delta + `design.md` + `tasks.md` + `_DIR.md`；delta 语义遵循 OpenSpec 官方 skills / commands。执行期推迟的 main 共享 `_DIR.md` 更新记录在 change 目录的 `pending-sync.md`（change-owned，随分支合并流转），由 `change-review` 归档阶段在 main 上消费。
- **状态唯一源**：backlog 阶段唯一存于 `product/backlog.md`；`design/roadmap.md` 的 AUTO 段是从 backlog + modules 全量重渲染的派生视图，模块文档 `## 关联 Backlog` 行不携带阶段标签。
- **分形文档同步**：创建或修改文件时同步维护文件头、所在目录 `_DIR.md`；新建目录必须有 `_DIR.md`；顶层结构变化更新 `openspec/project.md`。
- **日志协议**：自动化 skill 遇到 STOP / WARN 必须写 `.logs/<skill>/<artifact-id>.md`；scope 与格式以各 `SKILL.md` 和 `.logs/_DIR.md` 为准。

## Verification

apply 完成后、archive 之前必须执行三维 verify：

1. **Completeness**：tasks.md 全部勾选，delta specs 场景全部有实现
2. **Correctness**：代码行为匹配 proposal intent
3. **Coherence**：目录结构、分形文档与 design.md 一致

不跳过 verify 直接归档；验证失败时按对应 `SKILL.md` 记录日志、修复或 STOP。

## Git Boundaries

- dispatch 永远不碰 main，只在 feature branch 工作。
- Backlog 阶段只由主控交互式 agent（Claude Code / Codex）在 main 上更新。
- PR 必须同时包含四件套与代码。
- Merge 策略固定为 merge commit（`--no-ff`）。
- 所有 main push 必须走 `core/git-safe-push.md`。
- `change-review` 在 `gh pr ready` 前必须 rebase 到最新 main。

### Feature Branch 治理层禁改清单

feature branch 禁改 main 上已存在、多 change 共享的治理层文件：

`product/backlog.md` / `design/roadmap.md` / `design/modules/*.md` / `openspec/specs/**` / `openspec/project.md` / `openspec/changes/_DIR.md` / main 上已存在的共享 `_DIR.md`

例外：change 新建目录的 `_DIR.md` 属于 change-owned，可以在 feature branch 上维护。

`change-dispatch` D1 与 `change-review` R1 必须用 `git diff --name-only` / `gh pr diff --name-only` 检查禁改范围；命中硬禁文件即 STOP + 写日志，不自动还原。命中 main 上已存在的共享 `_DIR.md` 时，dispatch 可记录待办并还原，由 review 在 main 上同步。

## Do NOT

- 不创建超过 300 行的文件。
- 不使用类型逃逸（TypeScript `any`、Python `Any` 无约束等）。
- 不硬编码 API key、secret、token。
- 不跳过输入验证直接处理用户请求。
- 不遗漏文件头注释、`_DIR.md` 或必要的 `openspec/project.md` 目录更新。
- 不跳过设计层直接写 backlog；新需求必须经过 `/design`，历史遗留 backlog 用 `—` 标记模块列。
- 不跳过 delta specs 直接写 tasks.md。
- 不在没有 OpenSpec change 的前提下进行大型功能变更。
- 不在 change 执行期调整模块边界；必须回到 `/design review M-NNN`。
- 不手改 `design/roadmap.md` 的 `AUTO:*` 段。
- 不在 feature branch 上修改治理层共享文件。
- 不对 main 使用 `git push --force` / `--force-with-lease`。
- 不绕过 `core/git-safe-push.md` 直接 `git push origin main`。

> 技术栈特定禁令由 `scripts/init.sh` 从 `stacks/<name>/do-not.md` 注入到本文件末尾；技术栈实现顺序与目录约定见 `openspec/project.md`。
