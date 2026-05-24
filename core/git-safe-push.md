# git-safe-push — main 分支并发推送协议

所有直接向 `main` 推送的 skill（`module-designer` / `prd-writer` / `change-propose` / `change-review`）**必须**遵循本协议。

目的：多人协同 + `/loop` 自动化 + 任意 dispatch runner 并发场景下，消除 "push 被拒 / rebase 冲突" 导致的流水线断裂。

---

## 标准流程

```
本地构造完所需 commit（正常 git add / commit）
│
▼
┌─ 推送尝试循环（最多 3 轮）─────────────────────────┐
│                                                    │
│  第 N 轮：                                         │
│  1) git push origin main                          │
│     ├─ 成功 → 退出循环（记录成功）                 │
│     └─ 被拒（non-fast-forward） → 进入 2           │
│                                                    │
│  2) git pull --rebase origin main                 │
│     ├─ 无冲突 → 回到 1 重试 push                   │
│     └─ 有冲突 → 进入 3                             │
│                                                    │
│  3) 按"冲突解决策略"处理                          │
│     ├─ 策略覆盖 → git add + git rebase --continue  │
│     │            → 回到 1 重试 push                │
│     └─ 策略不覆盖 → STOP（写日志 + 人工介入）      │
│                                                    │
└────────────────────────────────────────────────────┘
│
▼
3 轮仍失败 → STOP（写日志 + 人工介入）
```

**实现要点：**

- 每个 skill 在其 push main 小节引用本协议（不重复展开）
- 3 轮上限防止死循环
- STOP 时必须写日志到 `.logs/<skill>/<scope>.md`，`scope` 为 change-id / M-NNN / PRD-NNN

---

## 冲突解决策略（按文件类型）

### `product/backlog.md`

按 **B-NNN 主键** 行级三方合并：

- 两侧改同一 B-NNN 行 → "最新阶段胜出"（阶段顺序：`idea < exploring < proposed < done`）
- 两侧改不同 B-NNN 行 → 各自保留
- 新增行冲突（双方都在"未归类"尾部追加 B-NNN）→ 按 B 编号升序合并
- 表头 / 分组标题区冲突 → STOP

### `design/roadmap.md` AUTO:* 段

按 **主键行级** 合并（AUTO 段外的人工维护区冲突直接 STOP）：

| 段 | 主键 |
|---|---|
| `AUTO:ARCHITECTURE` | M-NNN（模块 ID）|
| `AUTO:DEPENDENCIES` | `M-NNN → M-NNN`（依赖对）|
| `AUTO:PROGRESS` | B-NNN（backlog ID）|

- 同键双方都改 → 最新状态胜出（阶段 / status 按该字段自有序关系）
- 不同键 → 各自保留

### `design/modules/M-NNN-*.md`

按段处理：

- **frontmatter**：`status` 字段按 `planning < active < done` 取较新；其他字段冲突 → STOP
- **`## 关联 Backlog` 段**：按 B-NNN 主键行合并（同 `backlog.md` 规则）
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

1. 3 轮推送尝试后仍被拒
2. rebase 冲突落在"策略不覆盖"的段
3. rebase 本身报错（非冲突类，如磁盘 / 权限 / 远端不可达）
4. `.git` 状态异常（未提交更改、worktree 锁定等）

---

## 日志格式

```markdown
### [YYYY-MM-DD HH:mm] git-safe-push · <skill-name>

- **scope**: change-id / M-NNN / PRD-NNN
- **轮次**: 1 / 2 / 3
- **类型**: push 被拒 / rebase 冲突 / 策略不覆盖 / 其他
- **冲突文件**: path/to/file.md
- **处理**: 重试通过 / STOP + 提示人工 / 其他
```

**SKIP** 级（单次 pull-rebase 成功即 push）不写日志——只在 STOP / 多轮冲突时留痕。

---

## 反例（禁止做法）

- ❌ `git push --force origin main`（丢失他人提交）
- ❌ `git push --force-with-lease origin main`（main 分支禁止任何 force 推送）
- ❌ 无 retry 上限（死循环阻塞 `/loop`）
- ❌ 把不可合并的段强行用 `--strategy-option=theirs/ours`（语义丢失）
- ❌ STOP 时不写日志（下一轮 Luke / 另一 skill 无从追溯）

---

## 与 feature branch push 的区别

feature branch 上的 push 使用标准顺序：先 `git pull --rebase origin <branch>`，再 `git push`（允许 `--force-with-lease` 的场景仅限：`change-review` 的 Step 3.8 rebase-before-ready）。main 禁止任何 force 推送。
