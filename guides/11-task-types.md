# 任务类型与命名规范

本指南汇总 4 种任务类型的语义标签差异。**所有类型走完全相同的流程**，通过 backlog / PRD 的 type 声明和后续 change-id / branch / commit 前缀区分语义，便于下游过滤。

---

## 为什么要分类

单一 `feat/*` 前缀覆盖所有变更时，下游工具（CI 规则、git log 过滤、release notes 生成）无法区分"新功能"和"线上 P0 修复"，导致：

- git log 过滤器必须靠 PR 标题正则判断类型，脆弱
- release notes 无法自动分组（Features / Fixes / Chores / Hotfixes）
- PRD 模板"一把抓"，bug/chore/hotfix 被迫填写不相关的产品级字段（如成功指标、用户故事）

**设计原则：流程一致，前缀分类**。分类只是标签，不改变执行路径。

沿用 Conventional Commits / Conventional Branches 把类型做成**一等公民**，backlog / PRD 的 type 是声明事实源；change-id 前缀由 `prd-writer` 生成、由 propose 校验，只作为命名语义标签，不承担下游 type 反解析。

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
| delta specs | required | optional（空时需 marker） | optional（空时需 marker） | optional（空时需 marker） |
| 流程 | standard | standard | standard | standard |
| trailer | `Backlog-Ref` | `Backlog-Ref` | `Backlog-Ref` | `Backlog-Ref` |

> 四类任务的阶段、门禁与恢复协议完全一致；PRD 模板和 delta specs 是否允许为空按表中类型区分。bug/chore/hotfix 无可观察行为变化时必须用 `specs/README.md` 的 `delta-specs: none` + `reason:` 留下可审查证据。
>
> **type 建议由 `module-designer` 在 `/design` 对话中自动产生**（默认 feature；signals 包含 "bug/缺陷/修复" → bug；"重构/升级/构建/文档" → chore；"线上/紧急/P0/P1" → hotfix）。type 落到 backlog type 列后不可变，PRD / four-piece-set 都读取 backlog.type 保持一致。
>
> **变更粒度由 `module-designer` 在 `/design` 阶段与用户对话确定**（不再由 prd-writer 承担）。propose / dispatch / review 阶段信任 backlog 的拆分结果，不再二次检查——避免阻塞 `/loop` 自动化流水线。

---

## 事实源与派生关系

**backlog.type / PRD type 是声明事实源**。`change-id` 的命名前缀由 `prd-writer` 按 type 生成、`change-propose` 校验（type=bug 必须 `fix-` 开头等）。branch / PR title / commit type / flow **由 type 直接映射**（dispatch / review 扫描 backlog 时读同行"类型"列，或从 PR 分支前缀得到，不做 change-id 字符串反解析）：

```
feature → feat/  · feat  · Full PRD · delta required
bug     → fix/   · fix   · Lite PRD · delta optional
chore   → chore/ · chore · Lite PRD · delta optional
hotfix  → hotfix/· fix   · Lite PRD · delta optional
```

change-id 前缀（供 propose 校验一致性、便于 git log 过滤）命名示例：`chat-ui-basic-route`（feature，无前缀）、`fix-login-redirect`（bug）、`chore-upgrade-next-15`（chore）、`hotfix-payment-500`（hotfix）。

> **为什么不再从 change-id 反解析 type**：type 已在 backlog 类型列显式存在，反解析要额外处理 `fix-` 严格 4 字符、排除 `fixture-*` 等陷阱，且让"唯一没人把关的字段"承担了下游分支派生的重任。直接读 type 列消除这类隐患。

---

## 统一流程（所有类型）

```
(design → ) idea → exploring → proposed ────────────────→ done
                                    │                       ↑
                         tasks.md: draft→ready→executing→review→done
                                       │      │       │       │
                                   propose dispatch  收敛   review
                                           (原子领取) (全done→review)(预合并 Verify + 归档)
```

**Backlog 4 阶段**（main 上，治理层）：

- **(design)**：`/design` 由 `module-designer` 建模块 + 拆 idea + 自动建议 type
- **idea**：backlog 新建条目，`type` + `模块列` 已填（由 module-designer 分配）
- **exploring**：`/prd B-NNN` 生成 PRD（feature → Full；bug/chore/hotfix → Lite）
- **proposed**：`/change-propose B-NNN` 生成四件套 + Draft PR，branch 按 type 映射前缀
- **done**：合并前 Verify → implementation merge → governance archive PR → backlog 更新 → 若为模块最后一条，模块 status `active → done`

**执行细粒度**（tasks.md YAML status，change 独占）：

- **draft**：change-propose 编写四件套期间
- **ready**：pre-flight 通过，等待 dispatch 领取
- **executing**：dispatch 原子 claim 已 fast-forward push 成功；group comment 同时记录 claim-id/时间戳
- **review**：所有自动化任务组完成（dispatch 收敛判定），等待 change-review 审查、合并前 Verify、实现合并与归档
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
| Skill | `skills/change-propose/SKILL.md` | type → branch / PR 前缀映射 |
| Skill | `skills/change-dispatch/SKILL.md` | type → commit type 映射 |
| Skill | `skills/change-review/SKILL.md` | 统一的审查 + 归档流程 |
| 工作流 | `guides/09-git-github-workflow.md` | Git 全流程（见 Stage 图中分支命名） |
