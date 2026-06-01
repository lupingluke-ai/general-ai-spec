#!/usr/bin/env bash
# cc-onboard.sh — 为已存在的 Codex 项目接入 Claude Code
#
# 用途：项目已经用 Codex 开发了一段时间，现在想同时用 Claude Code。
# 只补充 Claude Code 需要的文件，不触碰任何已有代码、文档或配置。
#
# 用法：在项目根目录运行
#   bash /path/to/cc-onboard.sh
# 或者用 --dry-run 查看将要做什么：
#   bash /path/to/cc-onboard.sh --dry-run

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { printf '\n[INFO]  %s\n' "$*"; }
ok()    { printf '[OK]    %s\n' "$*"; }
skip()  { printf '[SKIP]  %s\n' "$*"; }
would() { printf '[WOULD] %s\n' "$*"; }
fail()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

run() {
  if $DRY_RUN; then would "$*"; else eval "$*"; fi
}

info "Claude Code Onboarding — project: $ROOT_DIR"
$DRY_RUN && info "(Dry-run mode — nothing will be changed)"

# ─────────────────────────────────────────────────────────────
# 1. CLAUDE.md — entry point for Claude Code
# ─────────────────────────────────────────────────────────────
if [ -f "$ROOT_DIR/CLAUDE.md" ]; then
  skip "CLAUDE.md already exists"
else
  info "Creating CLAUDE.md from template ..."
  if $DRY_RUN; then
    would "cp $FRAMEWORK_DIR/templates/CLAUDE.md.tmpl $ROOT_DIR/CLAUDE.md"
  else
    cp "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" "$ROOT_DIR/CLAUDE.md"
    ok "CLAUDE.md created (from templates/CLAUDE.md.tmpl)"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 2. .gitignore — add .worktrees entry
# ─────────────────────────────────────────────────────────────
GITIGNORE="$ROOT_DIR/.gitignore"
if [ -f "$GITIGNORE" ] && grep -q '\.worktrees' "$GITIGNORE"; then
  skip ".gitignore already contains .worktrees"
else
  info "Adding .worktrees to .gitignore ..."
  run "printf '\\n# Git worktrees for parallel development\\n.worktrees\\n' >> \"$GITIGNORE\""
  $DRY_RUN || ok ".worktrees added to .gitignore"
fi

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
  OPENSPEC_PKG="${OPENSPEC_PKG:-@fission-ai/openspec@1.2.0}"
  if command -v pnpm >/dev/null 2>&1; then
    run "pnpm dlx \"$OPENSPEC_PKG\" init --tools claude --force"
    if ! $DRY_RUN && [ ! -f "$CLAUDE_OPENSPEC_SKILL" ]; then
      fail "OpenSpec Claude init completed but .claude/skills/openspec-propose/SKILL.md is missing."
    fi
    $DRY_RUN || ok ".claude/commands/ created"
  else
    fail "pnpm not found. Install pnpm, then run: pnpm dlx $OPENSPEC_PKG init --tools claude --force"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 3.5 design/ — scaffold design layer if missing (idempotent)
#     L0 inputs/ + L1 modules/ + roadmap.md，module-designer / prd-writer
#     / change-propose / change-review 都依赖此层。
# ─────────────────────────────────────────────────────────────
if [ -d "$ROOT_DIR/design" ]; then
  skip "design/ already exists — leaving untouched"
else
  info "Scaffolding design/ layer (roadmap + inputs + modules) ..."
  if $DRY_RUN; then
    would "Create design/roadmap.md, design/_DIR.md, design/inputs/, design/modules/"
  else
    mkdir -p "$ROOT_DIR/design/inputs/brainstorming"
    mkdir -p "$ROOT_DIR/design/inputs/figma"
    mkdir -p "$ROOT_DIR/design/inputs/interviews"
    mkdir -p "$ROOT_DIR/design/modules"
    cp "$FRAMEWORK_DIR/templates/roadmap.md.tmpl"            "$ROOT_DIR/design/roadmap.md"
    cp "$FRAMEWORK_DIR/templates/design/_DIR.md"             "$ROOT_DIR/design/_DIR.md"
    cp "$FRAMEWORK_DIR/templates/design/inputs/_DIR.md"      "$ROOT_DIR/design/inputs/_DIR.md"
    cp "$FRAMEWORK_DIR/templates/design/modules/_DIR.md"     "$ROOT_DIR/design/modules/_DIR.md"
    printf '# design/inputs/brainstorming/_DIR.md\n\n头脑风暴与早期灵感记录目录。\n' > "$ROOT_DIR/design/inputs/brainstorming/_DIR.md"
    printf '# design/inputs/figma/_DIR.md\n\nFigma 原型、截图说明和交互注释目录。\n' > "$ROOT_DIR/design/inputs/figma/_DIR.md"
    printf '# design/inputs/interviews/_DIR.md\n\n用户访谈和调研记录目录。\n' > "$ROOT_DIR/design/inputs/interviews/_DIR.md"
    ok "design/ scaffolded (roadmap + inputs/ + modules/)"
    printf '[NOTE]  Existing backlog entries will have 模块 column = "—" — module-designer\n'
    printf '        skips them unless you explicitly associate via /design review M-NNN.\n'
  fi
fi

# ─────────────────────────────────────────────────────────────
# 3.55 openspec/specs/ — ensure main specs directory has fractal docs
# ─────────────────────────────────────────────────────────────
if [ ! -f "$ROOT_DIR/openspec/specs/_DIR.md" ]; then
  run "mkdir -p \"$ROOT_DIR/openspec/specs\""
  run "printf '# openspec/specs/_DIR.md\\n\\n主规格目录。归档时 change-review 会将 delta specs 同步到这里。\\n' > \"$ROOT_DIR/openspec/specs/_DIR.md\""
fi

# ─────────────────────────────────────────────────────────────
# 3.6 .logs/ — ensure framework log subdirs exist
# ─────────────────────────────────────────────────────────────
if [ ! -f "$ROOT_DIR/.logs/_DIR.md" ]; then
  run "mkdir -p \"$ROOT_DIR/.logs\""
  run "printf '# .logs/\\n\\n执行问题日志目录。记录各阶段 skill 的 STOP/WARN 与复盘偏离。\\n' > \"$ROOT_DIR/.logs/_DIR.md\""
fi

for sub in module-designer prd propose dispatch review; do
  if [ -d "$ROOT_DIR/.logs/$sub" ]; then
    skip ".logs/$sub/ already exists"
  else
    run "mkdir -p \"$ROOT_DIR/.logs/$sub\""
    $DRY_RUN || ok ".logs/$sub/ created"
  fi
  if [ ! -f "$ROOT_DIR/.logs/$sub/_DIR.md" ]; then
    run "printf '# .logs/$sub/_DIR.md\\n\\n%s 阶段日志目录。\\n' \"$sub\" > \"$ROOT_DIR/.logs/$sub/_DIR.md\""
  fi
done

# ─────────────────────────────────────────────────────────────
# 4. .claude/skills/ — symlink .agents/skills/* into .claude/skills/
#    Idempotent: only creates missing symlinks, never overwrites real dirs
# ─────────────────────────────────────────────────────────────
AGENTS_SKILLS="$ROOT_DIR/.agents/skills"
CLAUDE_SKILLS="$ROOT_DIR/.claude/skills"
if [ -d "$AGENTS_SKILLS" ]; then
  info "Syncing .agents/skills → .claude/skills/ symlinks ..."
  run "mkdir -p \"$CLAUDE_SKILLS\""
  for skill_path in "$AGENTS_SKILLS"/*/; do
    [ -d "$skill_path" ] || continue
    name=$(basename "$skill_path")
    link="$CLAUDE_SKILLS/$name"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      skip "  $name (real directory — not replaced)"
    elif [ -L "$link" ]; then
      skip "  $name (symlink already exists)"
    else
      run "ln -sfn \"../../.agents/skills/$name\" \"$link\""
      $DRY_RUN || ok "  → $name"
    fi
  done
else
  skip ".agents/skills/ not found — no symlinks created (project may not use shared skills)"
fi

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
fi
