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
#   9. 创建 GitHub workflows（ci/propose/dispatch/review）
#  10. 运行 stacks/<name>/scaffold.sh（安装依赖、创建 .env.local 等）
#  11. 配置 .gitignore
#  12. 初始化 OpenSpec
#  13. 安装 runtime tools 与 skills
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
if [ -d "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
elif $DRY_RUN; then
  case "$PROJECT_DIR" in
    /*) ;;
    *) PROJECT_DIR="$(pwd)/$PROJECT_DIR" ;;
  esac
else
  case "$PROJECT_DIR" in
    /*) PROJECT_CANDIDATE="$PROJECT_DIR" ;;
    *) PROJECT_CANDIDATE="$(pwd -P)/$PROJECT_DIR" ;;
  esac
  PARENT_PROBE=$(dirname "$PROJECT_CANDIDATE")
  while [ ! -d "$PARENT_PROBE" ] && [ "$PARENT_PROBE" != "/" ]; do
    PARENT_PROBE=$(dirname "$PARENT_PROBE")
  done
  PARENT_GIT_TOP=$(git -C "$PARENT_PROBE" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$PARENT_GIT_TOP" ]; then
    printf 'Error: target would be nested inside Git worktree %s. Choose a path outside it.\n' "$PARENT_GIT_TOP" >&2
    exit 1
  fi
  mkdir -p "$PROJECT_DIR"
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
fi

# ─── Helpers ────────────────────────────────────────────────
info()  { printf '\n[INFO]  %s\n' "$*"; }
ok()    { printf '[OK]    %s\n' "$*"; }
skip()  { printf '[SKIP]  %s\n' "$*"; }
would() { printf '[WOULD] %s\n' "$*"; }
fail()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

make_dir() {
  local target="$1"
  if $DRY_RUN; then would "Create directory $target"; else mkdir -p "$target"; fi
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

if ! command -v node >/dev/null 2>&1; then
  fail "Node.js 22 is required. Install it and rerun init.sh."
fi
NODE_MAJOR=$(node -p 'Number(process.versions.node.split(".")[0])')
if [ "$NODE_MAJOR" -lt 22 ]; then
  fail "Node.js 22+ is required; found $(node --version)."
fi

GIT_PROBE_DIR="$PROJECT_DIR"
while [ ! -d "$GIT_PROBE_DIR" ] && [ "$GIT_PROBE_DIR" != "/" ]; do
  GIT_PROBE_DIR=$(dirname "$GIT_PROBE_DIR")
done
TARGET_GIT_TOP=$(git -C "$GIT_PROBE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$TARGET_GIT_TOP" ]; then
  TARGET_GIT_TOP=$(cd "$TARGET_GIT_TOP" && pwd -P)
fi
if [ -n "$TARGET_GIT_TOP" ] && [ "$TARGET_GIT_TOP" != "$PROJECT_DIR" ]; then
  fail "Target is nested inside another Git worktree ($TARGET_GIT_TOP). Choose that repository root or a path outside it."
fi
if [ -z "$TARGET_GIT_TOP" ]; then
  if $DRY_RUN; then
    would "Initialize Git repository with main branch at $PROJECT_DIR"
  else
    git -C "$PROJECT_DIR" init -q -b main
    ok "Git repository initialized on main"
  fi
fi

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

write_file_if_missing "$PROJECT_DIR/_DIR.md" "# 项目根目录

项目级入口目录。\`AGENTS.md\` 与 \`CLAUDE.md\` 定义 Agent 入口，\`openspec/\`、\`product/\`、\`design/\` 承载需求与规格，\`src/\` 承载实现，\`scripts/\` 与 \`.github/\` 承载自动化。"

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

make_dir "$PROJECT_DIR/product/prd"

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
make_dir "$PROJECT_DIR/design/inputs/brainstorming"
make_dir "$PROJECT_DIR/design/inputs/figma"
make_dir "$PROJECT_DIR/design/inputs/interviews"

for input_kind in brainstorming figma interviews; do
  INPUT_DIR_DOC=$(cat "$FRAMEWORK_DIR/templates/design/inputs/$input_kind/_DIR.md")
  write_file_if_missing "$PROJECT_DIR/design/inputs/$input_kind/_DIR.md" "$INPUT_DIR_DOC"
done

# ─── 8. Create .logs/ directory ────────────────────────────────
info "Creating .logs/ directory ..."

make_dir "$PROJECT_DIR/.logs/dispatch"
make_dir "$PROJECT_DIR/.logs/propose"
make_dir "$PROJECT_DIR/.logs/review"
make_dir "$PROJECT_DIR/.logs/prd"
make_dir "$PROJECT_DIR/.logs/module-designer"

write_file_if_missing "$PROJECT_DIR/.logs/module-designer/_DIR.md" "# .logs/module-designer/_DIR.md

module-designer 阶段日志目录。记录模块设计、idea 拆分、roadmap 同步中的 STOP/WARN 与复盘偏离。"

write_file_if_missing "$PROJECT_DIR/.logs/prd/_DIR.md" "# .logs/prd/_DIR.md

prd-writer 阶段日志目录。记录 PRD 字段、模块边界、roadmap 同步中的 STOP/WARN 与复盘偏离。"

write_file_if_missing "$PROJECT_DIR/.logs/propose/_DIR.md" "# .logs/propose/_DIR.md

change-propose 阶段日志目录。记录 PRD readiness、四件套一致性、pre-flight 和 governance PR 发布中的 STOP/WARN。"

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
DISPATCH_WORKFLOW=$(cat "$FRAMEWORK_DIR/templates/github-workflows/dispatch.yml")
write_file_if_missing "$PROJECT_DIR/.github/workflows/dispatch.yml" "$DISPATCH_WORKFLOW"
PROPOSE_WORKFLOW=$(cat "$FRAMEWORK_DIR/templates/github-workflows/propose.yml")
write_file_if_missing "$PROJECT_DIR/.github/workflows/propose.yml" "$PROPOSE_WORKFLOW"
REVIEW_WORKFLOW=$(cat "$FRAMEWORK_DIR/templates/github-workflows/review.yml")
write_file_if_missing "$PROJECT_DIR/.github/workflows/review.yml" "$REVIEW_WORKFLOW"

write_file_if_missing "$PROJECT_DIR/.github/_DIR.md" "# .github/_DIR.md

GitHub automation configuration directory.

## 子目录

- \`workflows/\` — GitHub Actions workflows used by the delivery pipeline."

write_file_if_missing "$PROJECT_DIR/.github/workflows/_DIR.md" "# .github/workflows/_DIR.md

GitHub Actions workflow directory.

## 文件

- \`ci.yml\` — test / lint / build required check
- \`propose.yml\` — Codex CLI 定时把 approved PRD 发布为 change
- \`dispatch.yml\` — Codex CLI 定时领取一个 auto 任务组
- \`review.yml\` — Codex CLI 定时审查、恢复和归档一个 change

dispatch/review 需要 \`OPENAI_API_KEY\` 与 \`DISPATCH_GITHUB_TOKEN\` secrets。后者必须是可触发后续 workflows 的 fine-grained PAT 或 GitHub App token，并拥有 contents / pull requests write。"

# ─── 10. Run stack scaffold.sh ──────────────────────────────
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

if [ -d "$PROJECT_DIR/public" ]; then
  write_file_if_missing "$PROJECT_DIR/public/_DIR.md" "# public/_DIR.md

静态资源目录。仅存放需要由应用原样公开的图片、图标和下载文件；新增或删除资源时同步更新本索引。"
fi

# ─── 11. .gitignore — required safety patterns ───────────────
info "Checking .gitignore safety patterns ..."

GITIGNORE="$PROJECT_DIR/.gitignore"

ensure_gitignore_entry() {
  local entry="$1"
  if [ -f "$GITIGNORE" ] && grep -Fqx -- "$entry" "$GITIGNORE"; then
    return 0
  fi
  if $DRY_RUN; then
    would "Add '$entry' to $GITIGNORE"
  else
    touch "$GITIGNORE"
    printf '%s\n' "$entry" >> "$GITIGNORE"
  fi
}

if ! $DRY_RUN && ! grep -Fqx -- "# General AI Spec safety rules" "$GITIGNORE" 2>/dev/null; then
  printf '\n# General AI Spec safety rules\n' >> "$GITIGNORE"
fi
ensure_gitignore_entry ".worktrees/"
ensure_gitignore_entry ".env"
ensure_gitignore_entry ".env.*"
ensure_gitignore_entry "!.env.example"
ensure_gitignore_entry "node_modules/"
ensure_gitignore_entry ".next/"
ensure_gitignore_entry "out/"
ensure_gitignore_entry "dist/"
ensure_gitignore_entry "build/"
ensure_gitignore_entry "coverage/"
ensure_gitignore_entry ".turbo/"
ensure_gitignore_entry "*.log"
$DRY_RUN || ok ".gitignore safety patterns verified"

# ─── 12. Initialize OpenSpec ────────────────────────────────
info "Initializing OpenSpec ..."

OPENSPEC_PKG="${OPENSPEC_PKG:-@fission-ai/openspec@1.6.0}"

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
  info "OpenSpec may label openspec/project.md as legacy; General AI Spec intentionally keeps it as the detailed technical/directory baseline and links it from config.yaml context."
fi

# ─── 13. Install runtime tools and skills ───────────────────
info "Installing framework runtime tools ..."

make_dir "$PROJECT_DIR/scripts"
write_file_if_missing "$PROJECT_DIR/scripts/_DIR.md" "# scripts/_DIR.md

项目自动化脚本目录。General AI Spec 安装的治理发布、change 校验和 roadmap 渲染工具位于本目录；业务脚本可并列放置并补充本索引。"

for runtime_tool in governance-publish.sh validate-change.mjs render-roadmap.mjs; do
  source_tool="$FRAMEWORK_DIR/scripts/$runtime_tool"
  target_tool="$PROJECT_DIR/scripts/$runtime_tool"
  if $DRY_RUN; then
    would "Copy runtime tool $runtime_tool to $target_tool"
  else
    cp "$source_tool" "$target_tool"
    chmod +x "$target_tool"
    ok "  → scripts/$runtime_tool"
  fi
done

info "Installing skills ..."

FRAMEWORK_SKILLS="$FRAMEWORK_DIR/skills"
PROJECT_SKILLS_AGENTS="$PROJECT_DIR/.agents/skills"
PROJECT_SKILLS_CLAUDE="$PROJECT_DIR/.claude/skills"

if [ -d "$FRAMEWORK_SKILLS" ]; then
  for skill_path in "$FRAMEWORK_SKILLS"/*/; do
    [ -d "$skill_path" ] || continue
    name=$(basename "$skill_path")

    # .agents/skills/ (portable, project-owned copy for Codex)
    target_agents="$PROJECT_SKILLS_AGENTS/$name"
    if [ -L "$target_agents" ]; then
      if $DRY_RUN; then
        would "Replace .agents/skills/$name symlink with portable copy"
      else
        rm "$target_agents"
        mkdir -p "$PROJECT_SKILLS_AGENTS"
        cp -R "$skill_path" "$target_agents"
        ok "  → .agents/skills/$name (portable copy)"
      fi
    elif [ -e "$target_agents" ]; then
      skip "  .agents/skills/$name (already exists)"
    else
      if $DRY_RUN; then
        would "Copy $skill_path to .agents/skills/$name"
      else
        mkdir -p "$PROJECT_SKILLS_AGENTS"
        cp -R "$skill_path" "$target_agents"
        ok "  → .agents/skills/$name (portable copy)"
      fi
    fi

    # .claude/skills/ (portable relative link to the project-owned copy)
    target_claude="$PROJECT_SKILLS_CLAUDE/$name"
    relative_target="../../.agents/skills/$name"
    if [ -L "$target_claude" ]; then
      current_target=$(readlink "$target_claude")
      if [ "$current_target" = "$relative_target" ]; then
        skip "  .claude/skills/$name (portable symlink already exists)"
      elif $DRY_RUN; then
        would "Replace .claude/skills/$name with portable relative symlink"
      else
        rm "$target_claude"
        ln -s "$relative_target" "$target_claude"
        ok "  → .claude/skills/$name (portable symlink)"
      fi
    elif [ -e "$target_claude" ]; then
      skip "  .claude/skills/$name (already exists)"
    else
      if $DRY_RUN; then
        would "Link .claude/skills/$name to $relative_target"
      else
        mkdir -p "$PROJECT_SKILLS_CLAUDE"
        ln -s "$relative_target" "$target_claude"
        ok "  → .claude/skills/$name (portable symlink)"
      fi
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
  printf '  • .github/workflows/ — CI plus runnable propose/dispatch/review Codex runners\n'
  printf '  • .logs/             — Execution logs (module-designer/prd/propose/dispatch/review)\n'
  printf '  • scripts/           — Portable governance publish, validation, and roadmap tools\n'
  printf '  • src/_DIR.md        — Fractal doc root\n'
  printf '  • .env.local         — Environment variables\n'
  printf '\nNext steps:\n'
  printf '  1. Fill in API keys in .env.local\n'
  printf '  2. Run: pnpm install && pnpm test && pnpm lint && pnpm build\n'
  printf '  3. Ensure GitHub remote exists and `gh auth status` passes (change-propose creates PRs)\n'
  printf '  4. Drop raw inspiration into design/inputs/ (brainstorming/figma/interviews)\n'
  printf '  5. Start the pipeline: /design  (module-designer builds M-NNN + decomposes into backlog)\n'
  printf '  6. Continue: /prd B-NNN → /change-propose (after PRD approved) → dispatch runner → /change-review\n'
  printf '     For a fully automated loop, also schedule review: /loop <interval> /change-review\n'
  printf '\nPick a dispatch runner and configure its cadence for your project:\n'
  printf '  A. Claude Code /loop (dev-time, zero config):   /loop <interval> /change-dispatch\n'
  printf '  B. Codex Desktop Automation (24/7):             Name: change-dispatch | Schedule: <interval> | Worktree: yes\n'
  printf '  C. cron:                                        <cron> cd %s && claude -p "/change-dispatch" >> .logs/dispatch/cron.log 2>&1\n' "$PROJECT_DIR"
  printf '  D. GitHub Actions:                              set OPENAI_API_KEY + DISPATCH_GITHUB_TOKEN, then enable generated workflows\n'
  printf '  E. One-shot manual:                             /change-dispatch\n'
  printf '  See skills/change-dispatch/SKILL.md for full runner recipes.\n'
fi
