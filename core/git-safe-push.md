# git-safe-push — main 治理变更发布协议

所有需要更新 main 治理层的 skill（`module-designer` / `prd-writer` / `change-propose` / `change-review`）**必须**遵循本协议。skill 不再直接 push main，而是通过确定性 governance branch + PR 发布。

目的：兼容 required checks、branch protection、auto-merge 与多人并发，同时让每次 main 变更具备可查询的 MERGED/PENDING/STOP checkpoint。

---

## 标准流程

1. 为**本次状态转换**确定稳定 scope，在修改前调用 `scripts/governance-publish.sh --check --skill <skill> --scope <scope>`。
   - `MERGED/READY`：继续。
   - `PENDING`：已有 PR 等待 checks/approval，本轮结束。
   - `STOP`：关闭未合并或孤儿 branch，人工处理。
2. 保持本地 `main == origin/main`，完成治理文件修改。
3. 只用显式路径 `git add -- <allowed-files...>`，禁止 `git add -A`。
4. 把完整 commit message 写入仓库外的临时文件，调用：

```bash
scripts/governance-publish.sh \
  --skill <skill> \
  --scope <scope> \
  --title "<PR title>" \
  --commit-file <temp-message-file> \
  -- <allowed-file-or-directory>...
```

脚本创建 `governance/<skill>/<scope>`、校验 staged allowlist、commit、push、创建 PR。无保护时尝试即时 merge；required checks 未完成时启用 auto-merge并返回 `PENDING`。后续轮次通过同一个确定性 branch/PR 恢复；发布器负责检测状态与范围，语义冲突由调用它的 skill 按下节规则解决。

**实现要点：**

- 每个 scope 同一时间最多一个 governance PR
- scope 表示一次可重试状态转换，而不是永久 artifact 锁；例如 module 增量更新用 `M-NNN-RNNN`，PRD draft/approved 用不同 scope
- main 永不被 skill 直接 push；无需 bypass actor
- 调用 skill 更新冲突 PR branch 最多 3 轮，且仍按下方语义策略执行；发布器不会擅自选择 ours/theirs
- STOP 时必须写到该 skill 的 artifact 日志；revision/transition scope 不改变日志文件的稳定 artifact-id

### 冲突恢复与重试

`--check` 报告 merge conflict 后，调用 skill 执行以下受控恢复；每轮都从远端分支开始，不得新建第二个 PR：

1. `git switch governance/<skill>/<scope>`，`git pull --ff-only origin governance/<skill>/<scope>`，再 `git fetch origin main`。
2. `git merge origin/main`，只按下节规则解决冲突；不在覆盖策略内的内容立即 STOP。
3. 对事实源完成合并后运行 `node scripts/render-roadmap.mjs --write && node scripts/render-roadmap.mjs --check`（若 scope 涉及 roadmap）。
4. 确认 `git diff --cached --name-only` 与最终 commit 都没有超出原 allowlist，commit 并 push 同一 governance branch。
5. 切回干净的 `main`，调用 `scripts/governance-publish.sh --retry --skill <skill> --scope <scope> -- <原 allowlist...>`。发布器会重新核对整个 PR diff 的 allowlist，并再次请求即时/自动合并。

若 push 时远端又前进，重新 fetch 后进入下一轮；最多 3 轮。`PENDING` 只等待 checks/approval 或人工 merge，不计入冲突重试次数。

---

## 冲突解决策略（按文件类型）

### `product/backlog.md`

按 **B-NNN 主键** 行级三方合并：

- 两侧改同一 B-NNN 行 → "最新阶段胜出"（阶段顺序：`idea < exploring < proposed < done`）
- 两侧改不同 B-NNN 行 → 各自保留
- 新增行冲突（双方都在尾部追加 B-NNN）→ 按 B 编号升序合并
- **编号碰撞**（同一 B-NNN 双方内容不同，即两个并发会话分配了同号）→ 保留先到达远端的一侧；本地行按"当前最大 B-NNN + 1"顺移重编号（同步更新模块文档 `## 关联 Backlog` 与 roadmap 重渲染），写 WARN 日志后重试
- 表头 / 分组标题区冲突 → STOP

### `design/roadmap.md` AUTO:* 段 — AUTO 段重渲染

AUTO 三段是 `product/backlog.md` + `design/modules/*.md` 的**派生视图，不存储独立状态**，因此不做行级合并：

- **冲突解决** = 任取一侧（`git checkout --ours/--theirs` 均可）→ **先解决 `backlog.md` / `modules/*.md` 的冲突（它们是事实源，按各自主键合并）**→ 再从合并后的 backlog + modules **全量重渲染**三段 AUTO 区 → 一并提交。渲染必须在事实源合并之后，保证视图反映合并结果
- **唯一渲染器**：所有写 main 状态的 skill 必须运行 `node scripts/render-roadmap.mjs --write`，提交前再运行 `--check`；禁止各 agent 自行拼 Markdown。渲染语义：
  - `AUTO:ARCHITECTURE`：遍历 `design/modules/*.md` frontmatter，按 M-NNN 升序生成模块表（ID / 名 / status / 链接 / depends-on / created）
  - `AUTO:DEPENDENCIES`：由各模块 `depends-on` 生成邻接表，按 M-NNN 升序
  - `AUTO:PROGRESS`：遍历 backlog 按模块分节，每条 B-NNN 一行，图标按阶段列映射（`💡 idea | 🔎 exploring | 📝 proposed | ✅ done`）
- AUTO 段外的人工维护区冲突 → STOP

### `design/modules/M-NNN-*.md`

按段处理：

- **frontmatter**：正常生命周期按 `planning < active < done` 取较新；`deprecated` 是人工终止态，与 active/done 并发时一律 STOP，禁止自动覆盖；其他字段冲突 → STOP
- **`## 关联 Backlog` 段**：按 B-NNN 主键行合并（行内只含描述 + depends-on，无阶段标签，冲突面很小）
- **`## 修订历史` 段**：append 双方记录，按日期升序去重
- **其他段**（模块边界 / 对外接口 / 技术选型等）：冲突 → STOP（需人工确认设计意图）

### `openspec/specs/**.md`（主 specs）

冲突 → **STOP**（spec 合并涉及需求语义，禁止自动化）。

### `openspec/changes/_DIR.md`

按 **change-id 主键** 行级合并（活跃条目追加、归档条目删除）。两侧都删同一条 → 已删除，接受。两侧一加一删 → 以删除胜出。

### 顶层分形 `_DIR.md`

按 **条目名主键** 行级合并（每个 _DIR.md 的"子目录/文件清单"段）。

### 其他

默认 git 三方合并；解不开 → STOP。

---

## STOP 触发条件（统一）

1. governance PR 被关闭但未合并，或远端 branch 无对应 PR
2. 3 轮更新 PR branch 后仍冲突
3. rebase 冲突落在"策略不覆盖"的段
4. 本地 main 不等于 origin/main，或 staged 文件超出 allowlist
5. PR 存在不可自动解决的 merge conflict（单纯等待 required checks、approval，或仓库未启用 auto-merge，均为 `PENDING`，不是 STOP）

---

## 日志格式

```markdown
### [YYYY-MM-DD HH:mm] git-safe-push · <skill-name>

- **scope**: change-id / M-NNN / PRD-NNN
- **PR**: governance PR number / URL
- **类型**: PENDING / PR branch 冲突 / allowlist 越界 / 策略不覆盖 / 其他
- **冲突文件**: path/to/file.md
- **处理**: 重试通过 / STOP + 提示人工 / 其他
```

正常的 `PENDING` 是等待状态，不写 STOP；冲突修复或异常才写日志。

---

## 反例（禁止做法）

- ❌ `git push --force origin main`（丢失他人提交）
- ❌ `git push --force-with-lease origin main`（main 分支禁止任何 force 推送）
- ❌ `git push origin main`（绕过 governance PR 与 required checks）
- ❌ `git add -A`（会把用户未跟踪文件或其他 change 带入治理提交）
- ❌ 无 retry 上限（死循环阻塞 `/loop`）
- ❌ 把不可合并的段强行用 `--strategy-option=theirs/ours`（语义丢失）
- ❌ STOP 时不写日志（下一轮用户 / 另一 skill 无从追溯）

---

## 与 feature / worker branch push 的区别

dispatch worker 通过 fast-forward `HEAD:<feature-branch>` push 获取 claim 和提交实现；竞争失败必须重新选组。`--force-with-lease` 仅允许 `change-review` 的 feature PR rebase-before-ready。main 只接受 GitHub 合并 governance/feature PR。
