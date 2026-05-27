# 可选扩展 Skill

框架默认不包含以下两个 skill，按需通过 `--with-*` flag 安装。两者都是完全外部的独立 skill，升级、替换或卸载只在 `.claude/skills/` 目录动手，**不影响核心流水线**。

---

## 安装

```bash
# 仅装 brainstorming
bash scripts/init.sh --stack nextjs-react-local --dir ./my-app --with-brainstorming

# 仅装 impeccable
bash scripts/init.sh --stack nextjs-react-local --dir ./my-app --with-impeccable

# 两个都装
bash scripts/init.sh --stack nextjs-react-local --dir ./my-app \
  --with-brainstorming --with-impeccable
```

安装失败只会 `[WARN]`，不会中断初始化。失败时按下方"手动安装"继续。

---

## brainstorming（obra/superpowers）

**仓库**：<https://github.com/obra/superpowers/tree/main/skills/brainstorming>

### 何时用

- backlog 条目阶段为 `idea`
- **需求模糊到无法直接写 PRD**（连用户故事都说不清）
- 需要先探索问题空间、比较多个可行方案

需求清晰时不要用它 —— 直接 `/prd B-NNN` 更高效。

### 核心行为

- **硬闸门**：不写代码、不搭脚手架，先出设计文档
- 9 步流程：探索代码 → 一次一个澄清问题 → 给 2–3 个方案加 trade-off → 用户选 → 写设计 → 自审 → 用户审
- 默认产出路径：`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

### 与 prd-writer 的衔接

brainstorming 产出的设计文档**不是 PRD**，它是"问题空间探索结果"。产出后按正常流程继续：

```
/brainstorming                                          # 模糊 idea 阶段
  → docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md
  → 用户审阅通过

/prd B-NNN                                              # 把探索结果固化为 PRD
  → prd-writer 把同 topic 的 brainstorming 设计文档作为对话起点
  → product/prd/PRD-NNN.md（status: approved）

/change-propose → dispatch → review                   # 进入常规流水线
```

触发 `/prd` 时在对话里提一句"请参考 `docs/superpowers/specs/<date>-<topic>-design.md`"，交互式 agent 会把它读进来作为上下文。

### 手动安装（fallback）

```bash
cd my-app
git clone --depth=1 https://github.com/obra/superpowers /tmp/superpowers
mkdir -p .claude/skills
cp -r /tmp/superpowers/skills/brainstorming .claude/skills/
rm -rf /tmp/superpowers
```

---

## impeccable（pbakaus/impeccable）

**仓库**：<https://github.com/pbakaus/impeccable> · **主页**：<https://impeccable.style>

### 何时用

- 前端栈项目（`nextjs-react-local` / `nextjs-react-drizzle` 等）
- **本次 change 涉及 UI 组件新增或修改**
- UI 变更很小（改个文案、调个 padding）时不需要用它

后端/CLI/数据层 change 不启用。

### 18 个命令分类

| 类别 | 命令 |
|------|------|
| Create（创建） | `/impeccable teach` · `/shape` |
| Evaluate（评估） | `/audit` · `/critique` |
| Refine（优化） | `/animate` · `/bolder` · `/colorize` · `/delight` · `/layout` · `/overdrive` · `/quieter` · `/typeset` |
| Simplify（简化） | `/adapt` · `/clarify` · `/distill` |
| Harden（加固） | `/harden` · `/optimize` · `/polish` |

### 三个集成时刻

**1. propose 起稿（Claude Code / Codex）**

首次进入 UI 开发前，一次性注入项目设计上下文：

```
/impeccable teach
```

起稿时用 `/shape` 生成组件初稿参考。把产出沉淀到 `design.md` 的 "UI Design Notes" 自由文本小节（手动填，不强制）。

**2. dispatch 实现（任意 runner）**

dispatch 按 `design.md` 的 "UI Design Notes" 小节实现，不直接调用 impeccable 命令。

**3. review 轮次 1（Claude Code / Codex）**

本地 CI 通过后、`gh pr ready` 之前，对本次 UI diff 跑：

```
/audit              # 评分审查
```

发现问题按类别用 Refine 系命令修复：

- 排版问题 → `/typeset`
- 颜色/对比度 → `/colorize`
- 布局 → `/layout`
- 整体打磨 → `/polish`

修复 + commit + push，再 `gh pr ready`。

### 产出定位

impeccable 的输出是**建议性**的，**不进四件套**。最终沉淀位置：

- 设计上下文 → `design.md` 的 "UI Design Notes" 小节（手动填写，非强制）
- 组件代码 → 正常的 `src/components/` 等位置
- 审查结论 → PR comment 或 `design.md` 更新

### 手动安装（fallback）

```bash
cd my-app
npx -y skills add pbakaus/impeccable
# 或插件方式：在 Claude Code 内执行 /plugin
```

---

## 弱耦合保证

| 保证 | 体现 |
|------|------|
| 不装时零影响 | 两个 flag 都不加，init.sh 行为与未引入扩展时完全一致 |
| 不改核心 skill | `prd-writer` / `change-propose` / `change-dispatch` / `change-review` 一个字都不动 |
| 不改模板和 stacks | 产物走各 skill 自己的默认路径，框架不插手 |
| 可随时替换 | 卸载只需 `rm -rf .claude/skills/<name>`；换 skill 只改 `scripts/init.sh` 中 `install_extra_skill` 的一行 |

---

## 卸载

```bash
rm -rf .claude/skills/brainstorming
rm -rf .claude/skills/impeccable
```

无需其他清理 —— 因为框架没有在其他地方依赖它们。
