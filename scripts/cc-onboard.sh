#!/usr/bin/env bash
# cc-onboard.sh — 为已存在的 Codex 项目接入 Claude Code
#
# 用途：General AI Spec 项目已经用 Codex 开发了一段时间，现在想同时用 Claude Code。
# 默认只补齐缺失的适配文件；--refresh-framework 显式刷新框架自有 runtime tools 与 skills。
#
# 用法：在项目根目录运行
#   bash /path/to/cc-onboard.sh
# 或者用 --dry-run 查看将要做什么：
#   bash /path/to/cc-onboard.sh --dry-run
# 显式刷新框架自有副本：
#   bash /path/to/cc-onboard.sh --refresh-framework

set -euo pipefail

DRY_RUN=false
REFRESH_FRAMEWORK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --refresh-framework) REFRESH_FRAMEWORK=true ;;
    -h|--help)
      printf 'Usage: cc-onboard.sh [--dry-run] [--refresh-framework]\n'
      exit 0
      ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { printf '\n[INFO]  %s\n' "$*"; }
ok()    { printf '[OK]    %s\n' "$*"; }
skip()  { printf '[SKIP]  %s\n' "$*"; }
would() { printf '[WOULD] %s\n' "$*"; }
fail()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

make_dir() {
  local target="$1"
  if $DRY_RUN; then would "Create directory $target"; else mkdir -p "$target"; fi
}

info "Claude Code Onboarding — project: $ROOT_DIR"
$DRY_RUN && info "(Dry-run mode — nothing will be changed)"
$REFRESH_FRAMEWORK && info "(Framework refresh enabled — runtime tools and framework skills may be updated)"

missing_prerequisites=()
for required_path in AGENTS.md openspec/config.yaml product/backlog.md; do
  [ -e "$ROOT_DIR/$required_path" ] || missing_prerequisites+=("$required_path")
done
if [ ${#missing_prerequisites[@]} -gt 0 ]; then
  fail "Not a complete General AI Spec project (missing: ${missing_prerequisites[*]}). Run scripts/init.sh for generic projects."
fi

# ─────────────────────────────────────────────────────────────
# 1. CLAUDE.md — entry point for Claude Code
# ─────────────────────────────────────────────────────────────
if [ -f "$ROOT_DIR/CLAUDE.md" ] && ! $REFRESH_FRAMEWORK; then
  skip "CLAUDE.md already exists"
else
  info "Creating CLAUDE.md from template ..."
  if $DRY_RUN; then
    would "cp $FRAMEWORK_DIR/templates/CLAUDE.md.tmpl $ROOT_DIR/CLAUDE.md"
  else
    cp "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" "$ROOT_DIR/CLAUDE.md"
    ok "CLAUDE.md installed (from templates/CLAUDE.md.tmpl)"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 2. .gitignore — add framework safety entries
# ─────────────────────────────────────────────────────────────
GITIGNORE="$ROOT_DIR/.gitignore"
ensure_gitignore_entry() {
  local entry="$1"
  if [ -f "$GITIGNORE" ] && grep -Fqx -- "$entry" "$GITIGNORE"; then return 0; fi
  if $DRY_RUN; then
    would "Add '$entry' to $GITIGNORE"
  else
    touch "$GITIGNORE"
    printf '%s\n' "$entry" >> "$GITIGNORE"
  fi
}
if ! $DRY_RUN && ! grep -Fqx -- '# General AI Spec safety rules' "$GITIGNORE" 2>/dev/null; then
  printf '\n# General AI Spec safety rules\n' >> "$GITIGNORE"
fi
for ignore_entry in '.worktrees/' '.env' '.env.*' '!.env.example' 'node_modules/' '.next/' 'out/' 'dist/' 'build/' 'coverage/' '.turbo/' '*.log'; do
  ensure_gitignore_entry "$ignore_entry"
done
$DRY_RUN || ok ".gitignore safety entries verified"

# ─────────────────────────────────────────────────────────────
# 3. .claude/commands/ — OpenSpec slash commands for Claude Code
#    Only runs if .claude/commands/ is missing (init already did it → skip)
# ─────────────────────────────────────────────────────────────
CLAUDE_COMMANDS="$ROOT_DIR/.claude/commands"
CLAUDE_OPENSPEC_SKILL="$ROOT_DIR/.claude/skills/openspec-propose/SKILL.md"
if [ -d "$CLAUDE_COMMANDS" ] && [ -f "$CLAUDE_OPENSPEC_SKILL" ]; then
  skip ".claude/commands/ already exists (OpenSpec slash commands ready)"
else
  info "Initialising OpenSpec for Claude Code ..."
  # Requires pnpm; adjust OPENSPEC_PKG if you pin a version
  OPENSPEC_PKG="${OPENSPEC_PKG:-@fission-ai/openspec@1.6.0}"
  if command -v pnpm >/dev/null 2>&1; then
    if $DRY_RUN; then
      would "Initialize OpenSpec Claude integration with $OPENSPEC_PKG in $ROOT_DIR"
    else
      (cd "$ROOT_DIR" && pnpm dlx "$OPENSPEC_PKG" init --tools claude --force)
    fi
    if ! $DRY_RUN && [ ! -f "$CLAUDE_OPENSPEC_SKILL" ]; then
      fail "OpenSpec Claude init completed but .claude/skills/openspec-propose/SKILL.md is missing."
    fi
    $DRY_RUN || ok ".claude/commands/ created"
  else
    fail "pnpm not found. Install pnpm, then run: pnpm dlx $OPENSPEC_PKG init --tools claude --force"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 3.5 design/ — fill each missing design artifact (idempotent)
#     L0 inputs/ + L1 modules/ + roadmap.md，module-designer / prd-writer
#     / change-propose / change-review 都依赖此层。
# ─────────────────────────────────────────────────────────────
info "Checking design/ layer (roadmap + inputs + modules) ..."
make_dir "$ROOT_DIR/design/inputs/brainstorming"
make_dir "$ROOT_DIR/design/inputs/figma"
make_dir "$ROOT_DIR/design/inputs/interviews"
make_dir "$ROOT_DIR/design/modules"
for template_pair in \
  "templates/roadmap.md.tmpl:design/roadmap.md" \
  "templates/design/_DIR.md:design/_DIR.md" \
  "templates/design/inputs/_DIR.md:design/inputs/_DIR.md" \
  "templates/design/modules/_DIR.md:design/modules/_DIR.md"; do
  source_rel=${template_pair%%:*}
  target_rel=${template_pair#*:}
  if [ -f "$ROOT_DIR/$target_rel" ]; then
    skip "$target_rel already exists"
  elif $DRY_RUN; then
    would "Create $target_rel"
  else
    cp "$FRAMEWORK_DIR/$source_rel" "$ROOT_DIR/$target_rel"
    ok "$target_rel created"
  fi
done
for input_kind in brainstorming figma interviews; do
  input_doc="$ROOT_DIR/design/inputs/$input_kind/_DIR.md"
  if [ -f "$input_doc" ]; then
    skip "design/inputs/$input_kind/_DIR.md already exists"
  elif $DRY_RUN; then
    would "Create $input_doc"
  else
    cp "$FRAMEWORK_DIR/templates/design/inputs/$input_kind/_DIR.md" "$input_doc"
    ok "design/inputs/$input_kind/_DIR.md created"
  fi
done

# ─────────────────────────────────────────────────────────────
# 3.55 openspec/specs/ — ensure main specs directory has fractal docs
# ─────────────────────────────────────────────────────────────
if [ ! -f "$ROOT_DIR/openspec/specs/_DIR.md" ]; then
  if $DRY_RUN; then
    would "Create $ROOT_DIR/openspec/specs/_DIR.md"
  else
    mkdir -p "$ROOT_DIR/openspec/specs"
    printf '# openspec/specs/_DIR.md\n\n主规格目录。归档时 change-review 会将 delta specs 同步到这里。\n' > "$ROOT_DIR/openspec/specs/_DIR.md"
  fi
fi

if [ ! -f "$ROOT_DIR/_DIR.md" ]; then
  if $DRY_RUN; then
    would "Create $ROOT_DIR/_DIR.md"
  else
    printf '# 项目根目录\n\nGeneral AI Spec 项目入口；需求、规格、实现与自动化目录均由本文件索引。\n' > "$ROOT_DIR/_DIR.md"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 3.6 .logs/ — ensure framework log subdirs exist
# ─────────────────────────────────────────────────────────────
if [ ! -f "$ROOT_DIR/.logs/_DIR.md" ]; then
  if $DRY_RUN; then
    would "Create $ROOT_DIR/.logs/_DIR.md"
  else
    mkdir -p "$ROOT_DIR/.logs"
    printf '# .logs/\n\n执行问题日志目录。记录各阶段 skill 的 STOP/WARN 与复盘偏离。\n' > "$ROOT_DIR/.logs/_DIR.md"
  fi
fi

for sub in module-designer prd propose dispatch review; do
  if [ -d "$ROOT_DIR/.logs/$sub" ]; then
    skip ".logs/$sub/ already exists"
  else
    make_dir "$ROOT_DIR/.logs/$sub"
    $DRY_RUN || ok ".logs/$sub/ created"
  fi
  if [ ! -f "$ROOT_DIR/.logs/$sub/_DIR.md" ]; then
    if $DRY_RUN; then
      would "Create $ROOT_DIR/.logs/$sub/_DIR.md"
    else
      printf '# .logs/%s/_DIR.md\n\n%s 阶段日志目录。\n' "$sub" "$sub" > "$ROOT_DIR/.logs/$sub/_DIR.md"
    fi
  fi
done

# ─────────────────────────────────────────────────────────────
# 4. Runtime tools — portable copies used by the shared skills
# ─────────────────────────────────────────────────────────────
make_dir "$ROOT_DIR/scripts"
if [ ! -f "$ROOT_DIR/scripts/_DIR.md" ]; then
  if $DRY_RUN; then
    would "Create $ROOT_DIR/scripts/_DIR.md"
  else
    printf '# scripts/_DIR.md\n\n项目自动化脚本目录。\n' > "$ROOT_DIR/scripts/_DIR.md"
  fi
fi
for runtime_tool in governance-publish.sh validate-change.mjs render-roadmap.mjs; do
  target_tool="$ROOT_DIR/scripts/$runtime_tool"
  if [ -e "$target_tool" ] && ! $REFRESH_FRAMEWORK; then
    skip "  scripts/$runtime_tool already exists"
  elif $DRY_RUN; then
    would "Copy scripts/$runtime_tool into project"
  else
    cp "$FRAMEWORK_DIR/scripts/$runtime_tool" "$target_tool"
    chmod +x "$target_tool"
    ok "  → scripts/$runtime_tool"
  fi
done

# ─────────────────────────────────────────────────────────────
# 5. Portable framework skills + Claude relative links
# ─────────────────────────────────────────────────────────────
AGENTS_SKILLS="$ROOT_DIR/.agents/skills"
CLAUDE_SKILLS="$ROOT_DIR/.claude/skills"
make_dir "$AGENTS_SKILLS"
make_dir "$CLAUDE_SKILLS"
for framework_skill in "$FRAMEWORK_DIR"/skills/*/; do
  [ -d "$framework_skill" ] || continue
  name=$(basename "$framework_skill")
  agent_target="$AGENTS_SKILLS/$name"
  if [ -L "$agent_target" ]; then
    if $DRY_RUN; then
      would "Replace $agent_target with portable copy"
    else
      rm "$agent_target"
      cp -R "$framework_skill" "$agent_target"
    fi
  elif [ ! -e "$agent_target" ]; then
    if $DRY_RUN; then would "Copy framework skill $name"; else cp -R "$framework_skill" "$agent_target"; fi
  elif $REFRESH_FRAMEWORK && [ -d "$agent_target" ]; then
    if $DRY_RUN; then
      would "Refresh framework skill $name"
    else
      cp -R "$framework_skill/." "$agent_target/"
      ok "  → refreshed $name"
    fi
  else
    skip "  .agents/skills/$name already exists"
  fi

  link="$CLAUDE_SKILLS/$name"
  relative_target="../../.agents/skills/$name"
  if [ -L "$link" ] && [ "$(readlink "$link")" = "$relative_target" ]; then
    skip "  $name portable link already exists"
  elif [ -e "$link" ] && [ ! -L "$link" ] && $REFRESH_FRAMEWORK && [ -d "$link" ]; then
    if $DRY_RUN; then
      would "Refresh real Claude skill directory $name"
    else
      cp -R "$framework_skill/." "$link/"
      ok "  → refreshed Claude copy $name"
    fi
  elif [ -e "$link" ] && [ ! -L "$link" ]; then
    skip "  $name is a real Claude skill directory — not replaced"
  elif $DRY_RUN; then
    would "Link $link to $relative_target"
  else
    [ -L "$link" ] && rm "$link"
    ln -s "$relative_target" "$link"
    ok "  → $name"
  fi
done

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
printf '\n'
if $DRY_RUN; then
  info "Dry-run complete. Run without --dry-run to apply changes."
else
  info "Claude Code onboarding complete."
  printf '\nClaude Code can now:\n'
  printf '  • Read CLAUDE.md as its entry point\n'
  printf '  • Use /design /prd /change-propose /change-review (main path) via .claude/skills/\n'
  printf '  • Use OpenSpec official skills/commands for proposal/spec/validate/archive rules\n'
  printf '  • Access all project skills via .claude/skills/\n'
  printf '  • Use git worktrees safely (.worktrees in .gitignore)\n'
  printf '  • Drive the design layer via design/inputs/ → /design → design/modules/\n'
  printf '  • Run portable governance/validation/roadmap tools from scripts/\n'
  if ! $REFRESH_FRAMEWORK; then
    printf '  • Existing framework copies were preserved; use --refresh-framework for an explicit refresh\n'
  fi
fi
