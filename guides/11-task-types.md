# 任务类型与命名规范

本指南汇总 4 种任务类型的语义标签差异。**所有类型走完全相同的流程**，通过 backlog / PRD 的 type 声明和后续 change-id / branch / commit 前缀区分语义，便于下游过滤。

---

## 为什么要分类

单一 `feat/*` 前缀覆盖所有变更时，下游工具（CI 规则、git log 过滤、release notes 生成）无法区分"新功能"和"线上 P0 修复"，导致：

- git log 过滤器必须靠 PR 标题正则判断类型，脆弱
- release notes 无法自动分组（Features / Fixes / Chores / Hotfixes）
- PRD 模板"一把抓"，bug/chore/hotfix 被迫填写不相关的产品级字段（如成功指标、用户故事）

**设计原则：流程一致，前缀分类**。分类只是标签，不改变执行路径。

沿用 Conventional Commits / Conventional Branches 把类型做成**一等公民**，backlog / PRD 的 type 是声明事实源；change-id 前缀是 propose 阶段校验后的派生标识，供后续自动化消费。

---

## 4 种类型速查

| 维度 | feature | bug | chore | hotfix |
|------|---------|-----|-------|--------|
| 含义 | 新功能 / 能力扩展 | 缺陷修复（非紧急） | 重构 / 升级 / 构建 / 文档 | P0/P1 紧急修复 |
| change-id 前缀 | 无 | `fix-` | `chore-` | `hotfix-` |
| branch 前缀 | `feat/` | `fix/` | `chore/` | `hotfix/` |
| commit type | `feat` | `fix` | `chore`/`refactor`/`build`/`ci`/`perf`/`docs` | `fix` |
| PR title 前缀 | `feat` | `fix` | `chore` | `fix` |
| PRD | Full | Lite | Lite | Lite |
| delta specs | required | optional | optional | optional |
| 流程 | standard | standard | standard | standard |
| trailer | `Backlog-Ref` | `Backlog-Ref` | `Backlog-Ref` | `Backlog-Ref` |

> 表格里**非前缀相关的所有列**（PRD 类型、delta specs、流程、trailer）都是**完全一致**的。前缀之外的差异只在交互阶段由 `prd-writer` 的 Step 3 对话澄清重点（bug/hotfix 聚焦根因、chore 聚焦目标状态、feature 聚焦用户故事）。
>
> **type 建议由 `module-designer` 在 `/design` 对话中自动产生**（默认 feature；signals 包含 "bug/缺陷/修复" → bug；"重构/升级/构建/文档" → chore；"线上/紧急/P0/P1" → hotfix）。type 落到 backlog type 列后不可变，PRD / four-piece-set 都读取 backlog.type 保持一致。
>
> **变更粒度由 `module-designer` 在 `/design` 阶段与用户对话确定**（不再由 prd-writer 承担）。propose / dispatch / review 阶段信任 backlog 的拆分结果，不再二次检查——避免阻塞 `/loop` 自动化流水线。

---

## 事实源与派生关系

**backlog.type / PRD type 是声明事实源**。`change-propose` 必须校验 backlog type、PRD type、change-id 派生 type 三者一致；校验通过后，branch / PR title / commit type / flow 分支可从 change-id 字符串前缀派生，供 dispatch / review 等下游在 feature branch 上稳定消费。

判定规则（严格顺序）：

```
1. hotfix-<rest>   → hotfix
2. chore-<rest>    → chore
3. fix-<rest>      → bug（严格 4 字符含连字符，排除 fixture-* 等）
4. 其余            → feature
```

> 前缀合法命名示例：`chat-ui-basic-route`（feature）、`fix-login-redirect`（bug）、`chore-upgrade-next-15`（chore）、`hotfix-payment-500`（hotfix）。
> 反例：`fixture-data-import` 不是 bug，`fix-up-payment` 符合 bug 规则（前 4 字符严格为 `fix-`）。

---

## 统一流程（所有类型）

```
(design → ) idea → exploring → proposed ────────────────→ done
                                    │                       ↑
                         tasks.md: draft→ready→executing→review→done
                                       │      │       │       │
                                   propose dispatch review  review
                                           (领取)   (轮 1)  (轮 2)
```

**Backlog 4 阶段**（main 上，治理层）：

- **(design)**：`/design` 由 `module-designer` 建模块 + 拆 idea + 自动建议 type
- **idea**：backlog 新建条目，`type` + `模块列` 已填（由 module-designer 分配）
- **exploring**：`/prd B-NNN` 生成 PRD（feature → Full；bug/chore/hotfix → Lite）
- **proposed**：`/change-propose B-NNN` 生成四件套 + Draft PR，branch 按 type 前缀派生
- **done**：verify → sync specs → archive → backlog 更新 → 若为模块最后一条，模块 status `active → done`

**执行细粒度**（tasks.md YAML status，change 独占）：

- **draft**：change-propose 编写四件套期间
- **ready**：pre-flight 通过，等待 dispatch 领取
- **executing**：dispatch 领取中（`status: executing` commit 作分布式锁）
- **review**：所有自动化任务组完成，等待 change-review 轮次 1
- **done**：归档完成

> 为什么不让 backlog 反映执行细粒度？——dispatch runner 在 feature branch 上工作，**禁碰 main 治理层**（见 `core/AGENTS.md` Feature Branch 治理层禁改清单）。细粒度只能落在 change 独占的 tasks.md 里。

> hotfix 虽然是紧急修复，但仍必须走完整流程。PRD + 四件套不是形式主义——它让"改了什么、为什么改、如何验证"在事故后仍可追溯，是 release notes 和事后复盘的基础。紧急性通过资源调度（停手头的事先做）而非跳过流程体现。

---

## PRD 模板选择

- `templates/prd.md.tmpl`（Full）—— feature 用。保留用户故事 / Must Have / Nice to Have / Out of Scope / 非功能需求 / 成功指标
- `templates/prd-lite.md.tmpl`（Lite）—— bug / chore / hotfix 用。保留 Must Have（≥ 1 条）和 AC（≥ delta specs 场景数），去掉成功指标等产品级字段

> Lite PRD 保留 Must Have 段落是为了让 change-propose 的 P1 / P3 复盘检查点能继续工作。

---

## Commit Trailer 统一

所有类型统一用 `Backlog-Ref: B-NNN`，保证 `git log --grep='Backlog-Ref:'` 单一过滤器可用。

每条 commit 保留：

```
Change-ID: <change-id>
```

---

## 相关文件索引

| 层 | 文件 | 职责 |
|----|------|------|
| 规则 | `core/config.yaml → task-types` | type 声明、change-id 前缀、branch 前缀、commit type 的权威 schema |
| 规则 | `core/AGENTS.md → Artifact Contract` | runtime 入口与硬边界 |
| 模板 | `templates/backlog.md.tmpl` | type 列 + 阶段说明 |
| 模板 | `templates/prd.md.tmpl` / `prd-lite.md.tmpl` | Full / Lite PRD |
| Skill | `skills/prd-writer/SKILL.md → Step 2.4` | 模板选择 |
| Skill | `skills/change-propose/SKILL.md` | 分支派生 |
| Skill | `skills/change-dispatch/SKILL.md` | commit type 派生 |
| Skill | `skills/change-review/SKILL.md` | 统一的审查 + 归档流程 |
| 工作流 | `guides/09-git-github-workflow.md` | Git 全流程（见 Stage 图中分支命名） |
