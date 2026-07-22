#!/usr/bin/env bash
# init.sh — 基于三层架构（core + stacks + skills）初始化新项目
#
# 用法：
#   bash init.sh --stack nextjs-react-local [--dir /path/to/project]
#   bash init.sh --stack nextjs-react-drizzle --dir ./my-app
#   bash init.sh --stack nextjs-react-local --dry-run
#   bash init.sh --list                # 列出所有可用 stack profiles
#
# 流程：
#   1. 生成 AGENTS.md = core/AGENTS.md + stacks/<name>/do-not.md
#   2. 生成 openspec/project.md = templates/project.md.tmpl + stacks/<name>/stack.md
#   3. 生成 openspec/config.yaml = core/config.yaml + stacks/<name>/config-ext.yaml
#   4. 生成 CLAUDE.md = templates/CLAUDE.md.tmpl
#   5. 创建最小分形文档骨架
#   6. 创建 product/ 目录（backlog.md + _DIR.md）
#   7. 创建 design/ 目录（roadmap.md + inputs/ + modules/，module-designer 消费）
#   8. 创建 .logs/ 目录（执行日志基础设施）
#   9. 创建 GitHub workflow（ci: test/lint/build）
#  10. 配置 .gitignore
#  11. 运行 stacks/<name>/scaffold.sh（安装依赖、创建 .env.local 等）
#  12. 初始化 OpenSpec
#  13. 安装 skills
#  14. 安装可选扩展 skills

set -euo pipefail

# ─── Resolve paths ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Parse arguments ────────────────────────────────────────
STACK_NAME=""
PROJECT_DIR=""
DRY_RUN=false
LIST_STACKS=false
WITH_BRAINSTORMING=false
WITH_IMPECCABLE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)              STACK_NAME="$2";   shift 2 ;;
    --dir)                PROJECT_DIR="$2";  shift 2 ;;
    --dry-run)            DRY_RUN=true;      shift   ;;
    --list)               LIST_STACKS=true;  shift   ;;
    --with-brainstorming) WITH_BRAINSTORMING=true; shift ;;
    --with-impeccable)    WITH_IMPECCABLE=true;    shift ;;
    -h|--help)
      echo "Usage: bash init.sh --stack <profile-name> [--dir <path>] [--dry-run]"
      echo "       bash init.sh --list"
      echo ""
      echo "Options:"
      echo "  --stack <name>         Stack profile from stacks/ directory"
      echo "  --dir <path>           Target project directory (default: current dir)"
      echo "  --dry-run              Show what would be done without making changes"
      echo "  --list                 List available stack profiles"
      echo "  --with-brainstorming   Install brainstorming skill (obra/superpowers)"
      echo "  --with-impeccable      Install impeccable UI design skill (pbakaus/impeccable)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── List stacks ────────────────────────────────────────────
if $LIST_STACKS; then
  echo "Available stack profiles:"
  echo ""
  for stack_dir in "$FRAMEWORK_DIR"/stacks/*/; do
    [ -d "$stack_dir" ] || continue
    name=$(basename "$stack_dir")
    desc=""
    if [ -f "$stack_dir/stack.md" ]; then
      desc=$(head -5 "$stack_dir/stack.md" | grep '> 适用于' | sed 's/^> 适用于：//' || true)
    fi
    printf "  %-30s %s\n" "$name" "$desc"
  done
  exit 0
fi

# ─── Validate ───────────────────────────────────────────────
if [ -z "$STACK_NAME" ]; then
  echo "Error: --stack is required. Use --list to see available profiles."
  exit 1
fi

STACK_DIR="$FRAMEWORK_DIR/stacks/$STACK_NAME"
if [ ! -d "$STACK_DIR" ]; then
  echo "Error: Stack profile '$STACK_NAME' not found at $STACK_DIR"
  echo "Use --list to see available profiles."
  exit 1
fi

PROJECT_DIR="${PROJECT_DIR:-.}"
if [ ! -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ─── Helpers ────────────────────────────────────────────────
info()  { printf '\n[INFO]  %s\n' "$*"; }
ok()    { printf '[OK]    %s\n' "$*"; }
skip()  { printf '[SKIP]  %s\n' "$*"; }
would() { printf '[WOULD] %s\n' "$*"; }
fail()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

run_cmd() {
  if $DRY_RUN; then would "$*"; else eval "$*"; fi
}

write_file() {
  local target="$1"
  local content="$2"
  if $DRY_RUN; then
    would "Write $target ($(echo "$content" | wc -l | tr -d ' ') lines)"
  else
    mkdir -p "$(dirname "$target")"
    echo "$content" > "$target"
    ok "Created $target"
  fi
}

write_file_if_missing() {
  local target="$1"
  local content="$2"
  if [ -f "$target" ]; then
    skip "$target already exists"
  else
    write_file "$target" "$content"
  fi
}

info "Initializing project with stack: $STACK_NAME"
info "Project directory: $PROJECT_DIR"
$DRY_RUN && info "(Dry-run mode — nothing will be changed)"

# ─── 1. Generate AGENTS.md ──────────────────────────────────
info "Generating AGENTS.md ..."

CORE_AGENTS=$(cat "$FRAMEWORK_DIR/core/AGENTS.md")
STACK_DO_NOT=$(cat "$STACK_DIR/do-not.md" 2>/dev/null || echo "（无技术栈特定禁令）")

# Read template and substitute placeholders
AGENTS_CONTENT=$(cat "$FRAMEWORK_DIR/templates/AGENTS.md.tmpl")
AGENTS_CONTENT="${AGENTS_CONTENT/\{\{CORE_AGENTS\}\}/$CORE_AGENTS}"
AGENTS_CONTENT="${AGENTS_CONTENT/\{\{STACK_DO_NOT\}\}/$STACK_DO_NOT}"

write_file_if_missing "$PROJECT_DIR/AGENTS.md" "$AGENTS_CONTENT"

# ─── 2. Generate openspec/project.md ────────────────────────
info "Generating openspec/project.md ..."

STACK_CONTENT=$(cat "$STACK_DIR/stack.md")
PROJECT_TMPL=$(cat "$FRAMEWORK_DIR/templates/project.md.tmpl")
PROJECT_CONTENT="${PROJECT_TMPL/\{\{STACK_NAME\}\}/$STACK_NAME}"
PROJECT_CONTENT="${PROJECT_CONTENT/\{\{STACK_CONTENT\}\}/$STACK_CONTENT}"

write_file_if_missing "$PROJECT_DIR/openspec/project.md" "$PROJECT_CONTENT"

# ─── 3. Generate openspec/config.yaml ───────────────────────
info "Generating openspec/config.yaml ..."

merge_config_with_stack_ext() {
  local core_file="$1"
  local ext_file="$2"
  local stack_name="$3"

  if [ ! -f "$ext_file" ]; then
    cat "$core_file"
    return 0
  fi

  awk -v stack_name="$stack_name" '
    FNR == NR {
      if ($0 ~ /^rules:[[:space:]]*$/) {
        in_ext_rules = 1
        next
      }
      if (in_ext_rules && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) {
        ext_key = $1
        sub(/:$/, "", ext_key)
        ext_seen[ext_key] = 1
        next
      }
      if (in_ext_rules && ext_key != "" && $0 ~ /^    - /) {
        ext_items[ext_key] = ext_items[ext_key] "\n" $0
      }
      next
    }

    {
      print
      if ($0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) {
        key = $1
        sub(/:$/, "", key)
        if (key in ext_seen && !(key in inserted)) {
          print "    # Stack-specific extensions (" stack_name ")"
          count = split(ext_items[key], items, "\n")
          for (i = 1; i <= count; i++) {
            if (items[i] != "") print items[i]
          }
          inserted[key] = 1
        }
      }
    }

    END {
      for (key in ext_seen) {
        if (!(key in inserted)) {
          print ""
          print "  " key ":"
          print "    # Stack-specific extensions (" stack_name ")"
          count = split(ext_items[key], items, "\n")
          for (i = 1; i <= count; i++) {
            if (items[i] != "") print items[i]
          }
        }
      }
    }
  ' "$ext_file" "$core_file"
}

CONFIG_CONTENT=$(merge_config_with_stack_ext "$FRAMEWORK_DIR/core/config.yaml" "$STACK_DIR/config-ext.yaml" "$STACK_NAME")

write_file_if_missing "$PROJECT_DIR/openspec/config.yaml" "$CONFIG_CONTENT"

# ─── 4. Generate CLAUDE.md ──────────────────────────────────
info "Generating CLAUDE.md ..."

CLAUDE_CONTENT=$(cat "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl")
write_file_if_missing "$PROJECT_DIR/CLAUDE.md" "$CLAUDE_CONTENT"

# ─── 5. Fractal documentation skeleton ──────────────────────
info "Creating fractal documentation skeleton ..."

write_file_if_missing "$PROJECT_DIR/src/_DIR.md" "# src/_DIR.md

负责应用源码主目录，承载页面入口、共享组件、业务逻辑与类型定义。

当前初始化阶段仅保留最小骨架：
- \`app/\`：页面、布局、全局样式与路由入口

后续新增 \`components/\`、\`lib/\`、\`hooks/\`、\`types/\` 等目录时，必须同步补充本文件。"

write_file_if_missing "$PROJECT_DIR/src/app/_DIR.md" "# src/app/_DIR.md

负责 Next.js App Router 目录，承载页面路由、布局与 API Route Handlers。

当前初始化阶段仅保留最小骨架。

后续新增页面路由或 API 目录时，必须同步补充本文件。"

write_file_if_missing "$PROJECT_DIR/openspec/changes/_DIR.md" "# openspec/changes/_DIR.md

存放所有 OpenSpec change 目录。每个 change 是一个独立目录，包含四件套：proposal.md、specs/（delta specs）、design.md、tasks.md 和 _DIR.md。

已归档的 change 移入 \`archive/\` 子目录。

当前无活跃 change。"

write_file_if_missing "$PROJECT_DIR/openspec/specs/_DIR.md" "# openspec/specs/_DIR.md

主规格目录。归档时 change-review 会将 change delta specs 同步到这里，形成长期有效的系统行为规格。

当前无主规格文件。"

# ─── 6. Create product/ directory ─────────────────────────────
info "Creating product/ directory ..."

BACKLOG_CONTENT=$(cat "$FRAMEWORK_DIR/templates/backlog.md.tmpl")
write_file_if_missing "$PROJECT_DIR/product/backlog.md" "$BACKLOG_CONTENT"

write_file_if_missing "$PROJECT_DIR/product/_DIR.md" "# product/_DIR.md

产品级文档目录，存放需求全景、PRD 和产品决策记录。

## 文件与子目录

- \`backlog.md\` — 产品需求 Backlog，所有开发工作的起点
- \`prd/\` — 产品需求文档（PRD），每个 backlog 条目一份"

run_cmd "mkdir -p \"$PROJECT_DIR/product/prd\""

write_file_if_missing "$PROJECT_DIR/product/prd/_DIR.md" "# product/prd/_DIR.md

产品需求文档（PRD）存放目录。每个 PRD 对应一个 backlog 条目，编号格式 PRD-NNN。

PRD 状态：draft → reviewing → approved → superseded

当前无 PRD。"

# ─── 7. Create design/ directory ───────────────────────────────
info "Creating design/ directory (L0 inputs + L1 modules + roadmap) ..."

DESIGN_ROADMAP=$(cat "$FRAMEWORK_DIR/templates/roadmap.md.tmpl")
write_file_if_missing "$PROJECT_DIR/design/roadmap.md" "$DESIGN_ROADMAP"

DESIGN_ROOT_DIR=$(cat "$FRAMEWORK_DIR/templates/design/_DIR.md")
write_file_if_missing "$PROJECT_DIR/design/_DIR.md" "$DESIGN_ROOT_DIR"

DESIGN_INPUTS_DIR=$(cat "$FRAMEWORK_DIR/templates/design/inputs/_DIR.md")
write_file_if_missing "$PROJECT_DIR/design/inputs/_DIR.md" "$DESIGN_INPUTS_DIR"

DESIGN_MODULES_DIR=$(cat "$FRAMEWORK_DIR/templates/design/modules/_DIR.md")
write_file_if_missing "$PROJECT_DIR/design/modules/_DIR.md" "$DESIGN_MODULES_DIR"

# inputs 子目录（纯人工录入区）
run_cmd "mkdir -p \"$PROJECT_DIR/design/inputs/brainstorming\""
run_cmd "mkdir -p \"$PROJECT_DIR/design/inputs/figma\""
run_cmd "mkdir -p \"$PROJECT_DIR/design/inputs/interviews\""

write_file_if_missing "$PROJECT_DIR/design/inputs/brainstorming/_DIR.md" "# design/inputs/brainstorming/_DIR.md

头脑风暴与早期灵感记录目录。这里保留原始想法、问题探索和候选方案，供 module-designer 在 /design 阶段读取。

本目录由人工或可选 brainstorming skill 写入；核心流水线只读取。"

write_file_if_missing "$PROJECT_DIR/design/inputs/figma/_DIR.md" "# design/inputs/figma/_DIR.md

Figma 原型、截图说明和交互注释目录。这里记录设计稿链接、关键页面说明与交互约束。

本目录由人工维护，module-designer 读取后将相关输入引用到模块文档。"

write_file_if_missing "$PROJECT_DIR/design/inputs/interviews/_DIR.md" "# design/inputs/interviews/_DIR.md

用户访谈和调研记录目录。这里保留访谈纪要、痛点摘录和用户语境。

本目录由人工维护，module-designer 读取后将相关输入引用到模块文档。"

# ─── 8. Create .logs/ directory ────────────────────────────────
info "Creating .logs/ directory ..."

run_cmd "mkdir -p \"$PROJECT_DIR/.logs/dispatch\""
run_cmd "mkdir -p \"$PROJECT_DIR/.logs/propose\""
run_cmd "mkdir -p \"$PROJECT_DIR/.logs/review\""
run_cmd "mkdir -p \"$PROJECT_DIR/.logs/prd\""
run_cmd "mkdir -p \"$PROJECT_DIR/.logs/module-designer\""

write_file_if_missing "$PROJECT_DIR/.logs/module-designer/_DIR.md" "# .logs/module-designer/_DIR.md

module-designer 阶段日志目录。记录模块设计、idea 拆分、roadmap 同步中的 STOP/WARN 与复盘偏离。"

write_file_if_missing "$PROJECT_DIR/.logs/prd/_DIR.md" "# .logs/prd/_DIR.md

prd-writer 阶段日志目录。记录 PRD 字段、模块边界、roadmap 同步中的 STOP/WARN 与复盘偏离。"

write_file_if_missing "$PROJECT_DIR/.logs/propose/_DIR.md" "# .logs/propose/_DIR.md

change-propose 阶段日志目录。记录 PRD readiness、四件套一致性、pre-flight 和 main push 中的 STOP/WARN。"

write_file_if_missing "$PROJECT_DIR/.logs/dispatch/_DIR.md" "# .logs/dispatch/_DIR.md

change-dispatch 执行日志目录。记录任务认领、实现、验证、rebase/push 中的 STOP/WARN。
（main 共享 _DIR.md 的推迟更新不走日志，记录在各 change 目录的 pending-sync.md。）"

write_file_if_missing "$PROJECT_DIR/.logs/review/_DIR.md" "# .logs/review/_DIR.md

change-review 阶段日志目录。记录 PR 审查、CI 修复、verify、归档和 main 侧同步中的 STOP/WARN。"

write_file_if_missing "$PROJECT_DIR/.logs/_DIR.md" "# .logs/

执行问题日志目录。记录自动化 skill 运行中的异常和路径偏离，用于后续复盘优化。

## 子目录

- \`module-designer/\` — module-designer 阶段（按 M-NNN 或批次日期一个文件）
- \`prd/\` — prd-writer 阶段（按 PRD-NNN 一个文件）
- \`propose/\` — change-propose 阶段（按 change-id 一个文件）
- \`dispatch/\` — change-dispatch 执行阶段（任意 runner，按 change-id 一个文件）
- \`review/\` — change-review 阶段（交互式 agent，按 change-id 一个文件）

## 日志级别

| 级别 | 含义 | 行为 |
|------|------|------|
| **STOP** | 无法继续，需人工处理 | 写日志 → 终止当前 change → 尝试下一个 |
| **WARN** | 已自动降级/修复 | 写日志 → 继续执行 |
| **SKIP** | 条件不满足，正常跳过 | 不写日志 |

## 日志类型

### 系统异常类

执行失败 / 测试失败 / lint 错误 / 构建错误 / Git 失败 / 合并冲突 / Rebase 冲突 / PR 创建失败 / 依赖安装失败

### 路径偏离类（复盘检查点产出）

复盘偏离 — 范围偏离 / 复盘偏离 — 方案偏离 / 复盘偏离 — 一致性偏离

### 治理类

PRD 缺字段 / 依赖字段异常 / 范围越界 / 设计偏离 / Pre-flight 失败

## 日志格式

\`\`\`markdown
### [YYYY-MM-DD HH:mm] 步骤名/任务组 · skill 名称

- **类型**: <见上方类型列表>
- **级别**: STOP / WARN
- **现象**: 一句话描述
- **上下文**: 根因或相关信息
- **处理**: 当时采取的动作（STOP / 自动修正 / 重试后通过 / 标记 [NEEDS-FIX]）
\`\`\`

## 写入规则

- STOP 和 WARN 级别必须写入
- SKIP 级别不写入（属于正常流程）
- 一次性网络超时不记录，反复出现时记录
- 每个 change-id 一个文件，追加写入"

# ─── 9. GitHub workflow scaffolding ───────────────────────────
info "Creating GitHub workflow scaffolding ..."

CI_CONTENT=$(cat "$FRAMEWORK_DIR/templates/github-workflows/ci.yml")
write_file_if_missing "$PROJECT_DIR/.github/workflows/ci.yml" "$CI_CONTENT"

write_file_if_missing "$PROJECT_DIR/.github/_DIR.md" "# .github/_DIR.md

GitHub automation configuration directory.

## 子目录

- \`workflows/\` — GitHub Actions workflows used by the delivery pipeline."

write_file_if_missing "$PROJECT_DIR/.github/workflows/_DIR.md" "# .github/workflows/_DIR.md

GitHub Actions workflow directory.

## 文件

- \`ci.yml\` — test / lint / build 质量闸门。dispatch push 与 PR 都会触发；可在仓库设置中配置为 required check（配合 branch protection，change-review 会自动退化为 auto-merge 等待模式）。"

# ─── 10. .gitignore — add .worktrees ──────────────────────────
info "Checking .gitignore ..."

GITIGNORE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE" ] && grep -q '\.worktrees' "$GITIGNORE"; then
  skip ".gitignore already contains .worktrees"
else
  run_cmd "printf '\\n# Git worktrees for parallel development\\n.worktrees\\n' >> \"$GITIGNORE\""
  $DRY_RUN || ok ".worktrees added to .gitignore"
fi

# ─── 11. Run stack scaffold.sh ──────────────────────────────
SCAFFOLD="$STACK_DIR/scaffold.sh"
if [ -f "$SCAFFOLD" ]; then
  info "Running stack scaffold ($STACK_NAME) ..."
  if $DRY_RUN; then
    would "bash $SCAFFOLD $PROJECT_DIR"
  else
    bash "$SCAFFOLD" "$PROJECT_DIR"
  fi
else
  skip "No scaffold.sh found for $STACK_NAME"
fi

# ─── 12. Initialize OpenSpec ────────────────────────────────
info "Initializing OpenSpec ..."

OPENSPEC_PKG="${OPENSPEC_PKG:-@fission-ai/openspec@1.2.0}"

if $DRY_RUN; then
  would "Initialize OpenSpec with $OPENSPEC_PKG"
else
  cd "$PROJECT_DIR"
  if ! command -v pnpm >/dev/null 2>&1; then
    fail "pnpm is required to initialize OpenSpec. Install pnpm and rerun init.sh."
  fi

  pnpm dlx "$OPENSPEC_PKG" init --tools codex --force
  if [ ! -f "$PROJECT_DIR/.codex/skills/openspec-propose/SKILL.md" ]; then
    fail "OpenSpec Codex init completed but .codex/skills/openspec-propose/SKILL.md is missing."
  fi
  ok "OpenSpec initialized for Codex"

  pnpm dlx "$OPENSPEC_PKG" init --tools claude --force
  if [ ! -f "$PROJECT_DIR/.claude/skills/openspec-propose/SKILL.md" ]; then
    fail "OpenSpec Claude init completed but .claude/skills/openspec-propose/SKILL.md is missing."
  fi
  ok "OpenSpec initialized for Claude Code"
fi

# ─── 13. Install skills ─────────────────────────────────────
info "Installing skills ..."

FRAMEWORK_SKILLS="$FRAMEWORK_DIR/skills"
PROJECT_SKILLS_AGENTS="$PROJECT_DIR/.agents/skills"
PROJECT_SKILLS_CLAUDE="$PROJECT_DIR/.claude/skills"

if [ -d "$FRAMEWORK_SKILLS" ]; then
  for skill_path in "$FRAMEWORK_SKILLS"/*/; do
    [ -d "$skill_path" ] || continue
    name=$(basename "$skill_path")

    # .agents/skills/ (for Codex)
    target_agents="$PROJECT_SKILLS_AGENTS/$name"
    if [ -e "$target_agents" ]; then
      skip "  .agents/skills/$name (already exists)"
    else
      run_cmd "mkdir -p \"$PROJECT_SKILLS_AGENTS\" && ln -sfn \"$skill_path\" \"$target_agents\""
      $DRY_RUN || ok "  → .agents/skills/$name"
    fi

    # .claude/skills/ (for Claude Code)
    target_claude="$PROJECT_SKILLS_CLAUDE/$name"
    if [ -e "$target_claude" ]; then
      skip "  .claude/skills/$name (already exists)"
    else
      run_cmd "mkdir -p \"$PROJECT_SKILLS_CLAUDE\" && ln -sfn \"$skill_path\" \"$target_claude\""
      $DRY_RUN || ok "  → .claude/skills/$name"
    fi
  done
else
  skip "No skills directory found at $FRAMEWORK_SKILLS"
fi

# ─── 14. Optional extras (弱耦合外部 skills) ─────────────────
# 失败仅 WARN，不阻塞初始化。详见 guides/10-extras.md
install_extra_skill() {
  local label="$1"
  local repo_spec="$2"  # 形如 obra/superpowers/skills/brainstorming 或 pbakaus/impeccable
  info "Installing extra skill: $label ($repo_spec) ..."
  if $DRY_RUN; then
    would "npx -y skills add $repo_spec (in $PROJECT_DIR)"
    return 0
  fi
  if ( cd "$PROJECT_DIR" && npx -y skills add "$repo_spec" ) ; then
    ok "Extra skill installed: $label"
  else
    printf '[WARN] Extra skill install failed: %s — skipping, core init unaffected.\n' "$label"
  fi
}

if $WITH_BRAINSTORMING; then
  install_extra_skill "brainstorming" "obra/superpowers/skills/brainstorming"
fi

if $WITH_IMPECCABLE; then
  install_extra_skill "impeccable" "pbakaus/impeccable"
fi

# ─── Summary ────────────────────────────────────────────────
printf '\n'
if $DRY_RUN; then
  info "Dry-run complete. Run without --dry-run to apply changes."
else
  info "Project initialized successfully!"
  printf '\nGenerated files:\n'
  printf '  • CLAUDE.md          — Claude Code adapter entry point (AGENTS.md remains shared)\n'
  printf '  • AGENTS.md          — AI agent rules (core + %s prohibitions)\n' "$STACK_NAME"
  printf '  • openspec/project.md — Tech stack & architecture (%s)\n' "$STACK_NAME"
  printf '  • openspec/config.yaml — OpenSpec governance rules\n'
  printf '  • product/backlog.md — Product backlog (development source of truth)\n'
  printf '  • design/roadmap.md  — Global roadmap (architecture/dependencies/progress AUTO-synced)\n'
  printf '  • design/inputs/     — L0 raw design inputs (brainstorming/figma/interviews)\n'
  printf '  • design/modules/    — L1 module designs (maintained by module-designer)\n'
  printf '  • .github/workflows/ci.yml — CI quality gate (test/lint/build on push & PR)\n'
  printf '  • .logs/             — Execution logs (module-designer/prd/propose/dispatch/review)\n'
  printf '  • src/_DIR.md        — Fractal doc root\n'
  printf '  • .env.local         — Environment variables\n'
  printf '\nNext steps:\n'
  printf '  1. Fill in API keys in .env.local\n'
  printf '  2. Run: pnpm install && pnpm lint && pnpm build\n'
  printf '  3. Ensure GitHub remote exists and `gh auth status` passes (change-propose creates PRs)\n'
  printf '  4. Drop raw inspiration into design/inputs/ (brainstorming/figma/interviews)\n'
  printf '  5. Start the pipeline: /design  (module-designer builds M-NNN + decomposes into backlog)\n'
  printf '  6. Continue: /prd B-NNN → /change-propose (after PRD approved) → dispatch runner → /change-review\n'
  printf '     For a fully automated loop, also schedule review: /loop <interval> /change-review\n'
  printf '\nPick a dispatch runner and configure its cadence for your project:\n'
  printf '  A. Claude Code /loop (dev-time, zero config):   /loop <interval> /change-dispatch\n'
  printf '  B. Codex Desktop Automation (24/7):             Name: change-dispatch | Schedule: <interval> | Worktree: yes\n'
  printf '  C. cron:                                        <cron> cd %s && claude -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1\n' "$PROJECT_DIR"
  printf '  D. GitHub Actions:                              schedule workflow calling `claude -p "/change-dispatch"` or `codex exec`\n'
  printf '  E. One-shot manual:                             /change-dispatch\n'
  printf '  See skills/change-dispatch/SKILL.md for full runner recipes.\n'
fi
