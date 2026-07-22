#!/usr/bin/env bash
# Fast static and executable checks for the framework repository.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

bash -n scripts/init.sh scripts/cc-onboard.sh scripts/governance-publish.sh \
  scripts/framework-check.sh tests/protocol-e2e.sh stacks/*/scaffold.sh
node --check scripts/render-roadmap.mjs
node --check scripts/validate-change.mjs
git diff --check

if grep -R --line-number -- '--no-git' stacks; then
  printf 'Invalid create-next-app --no-git flag found.\n' >&2
  exit 1
fi
for scaffold in stacks/*/scaffold.sh; do
  grep -Fq -- '--use-pnpm' "$scaffold"
  grep -Fq -- '--disable-git' "$scaffold"
  grep -Fq -- 'create-next-app@16.2.11' "$scaffold"
  grep -Fq -- 'npx --yes' "$scaffold"
  grep -Fq -- 'fs.cpSync' "$scaffold"
  grep -Fq -- 'force: false' "$scaffold"
  grep -Fq -- '"node_modules", ".next"' "$scaffold"
  grep -Fq -- '@input Next.js request context' "$scaffold"
done

for required_ignore in '.worktrees/' '.env.*' 'node_modules/' '.next/'; do
  grep -Fq "ensure_gitignore_entry \"$required_ignore\"" scripts/init.sh
done
grep -Fq 'Target is nested inside another Git worktree' scripts/init.sh
grep -Fq 'git -C "$PROJECT_DIR" init -q -b main' scripts/init.sh
grep -Fq 'portable copy' scripts/init.sh
grep -Fq 'relative_target="../../.agents/skills/$name"' scripts/init.sh
grep -Fq -- '--refresh-framework' scripts/cc-onboard.sh
grep -Fq 'missing_prerequisites' scripts/cc-onboard.sh
grep -Fq 'template_pair' scripts/cc-onboard.sh
grep -Fq 'refreshed Claude copy' scripts/cc-onboard.sh
for input_kind in brainstorming figma interviews; do
  test -f "templates/design/inputs/$input_kind/_DIR.md"
done
grep -Fq '@fission-ai/openspec@1.6.0' scripts/init.sh
grep -Fq 'START_LOCAL_SERVICES:-false' stacks/nextjs-react-drizzle/scaffold.sh
grep -Fq 'public/_DIR.md' scripts/init.sh
grep -Fq 'PROJECT_DIR/_DIR.md' scripts/init.sh
grep -Fq '每个 ADDED/MODIFIED 需求至少包含两个' skills/change-propose/SKILL.md
grep -Fq '单纯等待 required checks' core/git-safe-push.md
grep -Fq -- '--retry --skill' scripts/governance-publish.sh
grep -Fq 'PR path is outside the retry allowlist' scripts/governance-publish.sh

grep -Fq 'HEAD:refs/heads/<branch-prefix>/<change-id>' skills/change-dispatch/SKILL.md
grep -Fq 'claim <group-id> as executing [<claim-id>]' skills/change-dispatch/SKILL.md
grep -Fq 'Step 7.5 — 提交实现并清洁工作区' skills/change-dispatch/SKILL.md
grep -Fq 'stale-after-minutes: 150' core/config.yaml

if grep -R --line-number -E '^git add -A[[:space:]]*$' skills; then
  printf 'Unscoped git add -A found in a skill.\n' >&2
  exit 1
fi
if grep -R --line-number -F 'git push origin main' skills; then
  printf 'Direct main push found in a skill.\n' >&2
  exit 1
fi
if grep -R --line-number -F '<你的 agent CLI>' README.md guides skills templates; then
  printf 'Unresolved agent CLI placeholder found.\n' >&2
  exit 1
fi

grep -Fq 'delta-specs: none' skills/change-propose/SKILL.md
grep -Fq 'specs/README.md' scripts/validate-change.mjs
grep -Fq 'done group has unchecked tasks' scripts/validate-change.mjs
grep -Fq 'Module dependency cycle detected' scripts/render-roadmap.mjs
grep -Fq 'terminal task groups must be' scripts/validate-change.mjs
grep -Fq -- '--phase premerge' skills/change-review/SKILL.md

verify_line=$(grep -n 'Step 3.9 — 合并前全景一致性与三维 Verify' skills/change-review/SKILL.md | cut -d: -f1)
merge_line=$(grep -n 'Step 4 — 合并 PR' skills/change-review/SKILL.md | cut -d: -f1)
if [ -z "$verify_line" ] || [ -z "$merge_line" ] || [ "$verify_line" -ge "$merge_line" ]; then
  printf 'Pre-merge Verify must appear before merge.\n' >&2
  exit 1
fi

for workflow in dispatch propose review; do
  file="templates/github-workflows/$workflow.yml"
  grep -Fq 'fetch-depth: 0' "$file"
  grep -Fq 'ref: main' "$file"
  grep -Fq 'DISPATCH_GITHUB_TOKEN' "$file"
  grep -Fq '@openai/codex@' "$file"
  grep -Fq 'contents: write' "$file"
  grep -Fq 'version: 10.34.5' "$file"
done
if grep -R --line-number -E 'uses: (actions/(checkout|setup-node)|pnpm/action-setup)@v[0-9]+' \
  templates/github-workflows .github/workflows; then
  printf 'Floating GitHub Action major tag found. Pin actions to immutable commits.\n' >&2
  exit 1
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; ARGV.each { |f| YAML.load(File.read(f)); puts "YAML OK: #{f}" }' \
    core/config.yaml stacks/*/config-ext.yaml templates/github-workflows/*.yml
fi

tests/protocol-e2e.sh
printf 'Framework checks passed.\n'
