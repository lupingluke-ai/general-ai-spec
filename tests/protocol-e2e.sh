#!/usr/bin/env bash
# Exercise atomic worker claims, validators, renderer, and governance publishing.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
TEST_ROOT=$(mktemp -d /tmp/general-ai-spec-protocol.XXXXXX)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

git init --bare -q "$TEST_ROOT/remote.git"
git clone -q "$TEST_ROOT/remote.git" "$TEST_ROOT/repo"
git -C "$TEST_ROOT/repo" config user.email audit@example.com
git -C "$TEST_ROOT/repo" config user.name Audit
mkdir -p "$TEST_ROOT/repo/openspec/changes/demo"
printf '%s\n' \
  '---' 'status: executing' '---' '# demo Tasks' \
  '## G1-A — first' \
  '<!-- 执行模式: auto | 约束: none | status: pending | claim-id: none | claimed-at: none | heartbeat-at: none -->' \
  '- [ ] first' \
  '## G1-B — second' \
  '<!-- 执行模式: auto | 约束: none | status: pending | claim-id: none | claimed-at: none | heartbeat-at: none -->' \
  '- [ ] second' > "$TEST_ROOT/repo/openspec/changes/demo/tasks.md"
git -C "$TEST_ROOT/repo" add .
git -C "$TEST_ROOT/repo" commit -qm init
git -C "$TEST_ROOT/repo" branch -M main
git -C "$TEST_ROOT/repo" push -qu origin main
git -C "$TEST_ROOT/repo" switch -qc feat/demo
git -C "$TEST_ROOT/repo" push -qu origin feat/demo
git -C "$TEST_ROOT/repo" switch -q main

git -C "$TEST_ROOT/repo" worktree add -q --detach "$TEST_ROOT/worker-a" origin/feat/demo
git -C "$TEST_ROOT/repo" worktree add -q --detach "$TEST_ROOT/worker-b" origin/feat/demo
git -C "$TEST_ROOT/worker-a" switch -qc worker/demo/G1-A/a
git -C "$TEST_ROOT/worker-b" switch -qc worker/demo/G1-A/b
git -C "$TEST_ROOT/worker-a" config user.email audit@example.com
git -C "$TEST_ROOT/worker-a" config user.name Audit
git -C "$TEST_ROOT/worker-b" config user.email audit@example.com
git -C "$TEST_ROOT/worker-b" config user.name Audit

for worker in worker-a worker-b; do
  claim_id="claim-${worker#worker-}"
  perl -0pi -e "s/status: pending \\| claim-id: none/status: executing | claim-id: $claim_id/" \
    "$TEST_ROOT/$worker/openspec/changes/demo/tasks.md"
  git -C "$TEST_ROOT/$worker" add openspec/changes/demo/tasks.md
  git -C "$TEST_ROOT/$worker" commit -qm 'claim G1-A'
done
git -C "$TEST_ROOT/worker-a" push -q origin HEAD:refs/heads/feat/demo
if git -C "$TEST_ROOT/worker-b" push -q origin HEAD:refs/heads/feat/demo 2>/dev/null; then
  printf 'Second claim unexpectedly succeeded.\n' >&2
  exit 1
fi

git -C "$TEST_ROOT/worker-b" fetch -q origin feat/demo
git -C "$TEST_ROOT/worker-b" reset -q --hard origin/feat/demo
perl -0pi -e 's/status: pending \| claim-id: none/status: executing | claim-id: claim-b2/' \
  "$TEST_ROOT/worker-b/openspec/changes/demo/tasks.md"
git -C "$TEST_ROOT/worker-b" add openspec/changes/demo/tasks.md
git -C "$TEST_ROOT/worker-b" commit -qm 'claim G1-B'
git -C "$TEST_ROOT/worker-b" push -q origin HEAD:refs/heads/feat/demo
git -C "$TEST_ROOT/repo" fetch -q origin feat/demo
git -C "$TEST_ROOT/repo" show origin/feat/demo:openspec/changes/demo/tasks.md | grep -Fq 'claim-id: claim-a'
git -C "$TEST_ROOT/repo" show origin/feat/demo:openspec/changes/demo/tasks.md | grep -Fq 'claim-id: claim-b2'

mkdir -p "$TEST_ROOT/project/design/modules" "$TEST_ROOT/project/product"
cp "$REPO_ROOT/templates/roadmap.md.tmpl" "$TEST_ROOT/project/design/roadmap.md"
cp "$REPO_ROOT/templates/backlog.md.tmpl" "$TEST_ROOT/project/product/backlog.md"
printf '%s\n' '---' 'id: M-001' 'slug: alpha' 'status: active' 'created: 2026-01-01' 'depends-on: []' '---' '' '# M-001 Alpha' \
  > "$TEST_ROOT/project/design/modules/M-001-alpha.md"
printf '%s\n' '| B-001 | Demo | M-001 | feature | idea | — | — | — |' >> "$TEST_ROOT/project/product/backlog.md"
node "$REPO_ROOT/scripts/render-roadmap.mjs" --write --root "$TEST_ROOT/project" >/dev/null
node "$REPO_ROOT/scripts/render-roadmap.mjs" --check --root "$TEST_ROOT/project" >/dev/null
printf '%s\n' '| B-001 | Duplicate | M-001 | feature | idea | — | — | — |' >> "$TEST_ROOT/project/product/backlog.md"
if node "$REPO_ROOT/scripts/render-roadmap.mjs" --write --root "$TEST_ROOT/project" >/dev/null 2>&1; then
  printf 'Duplicate backlog id unexpectedly passed roadmap validation.\n' >&2
  exit 1
fi
sed -i.bak '$d' "$TEST_ROOT/project/product/backlog.md"
node "$REPO_ROOT/scripts/render-roadmap.mjs" --write --root "$TEST_ROOT/project" >/dev/null

mkdir -p "$TEST_ROOT/project/openspec/changes/demo/specs"
printf '%s\n' '# Proposal' > "$TEST_ROOT/project/openspec/changes/demo/proposal.md"
printf '%s\n' '# Design' > "$TEST_ROOT/project/openspec/changes/demo/design.md"
printf '%s\n' '# Change' > "$TEST_ROOT/project/openspec/changes/demo/_DIR.md"
printf '%s\n' 'delta-specs: none' 'reason: internal refactor only' > "$TEST_ROOT/project/openspec/changes/demo/specs/README.md"
printf '%s\n' \
  '---' 'status: ready' '---' '# demo Tasks' \
  '## G0 — work' \
  '<!-- 执行模式: auto | 约束: none | status: pending | claim-id: none | claimed-at: none | heartbeat-at: none -->' \
  '- [ ] work' '## 文档与分形同步' \
  '<!-- 执行模式: interactive | 约束: after auto | status: pending -->' '- [ ] docs' \
  '## Verify' '<!-- 执行模式: interactive | 约束: after docs | status: pending -->' '- [ ] verify' \
  '## 归档' '<!-- 执行模式: interactive | 约束: after verify | status: pending -->' '- [ ] archive' \
  > "$TEST_ROOT/project/openspec/changes/demo/tasks.md"
node "$REPO_ROOT/scripts/validate-change.mjs" --root "$TEST_ROOT/project" --change demo --type chore --phase propose >/dev/null

cp -R "$TEST_ROOT/project/openspec/changes/demo" "$TEST_ROOT/project/openspec/changes/done-unchecked"
perl -0pi -e 's/status: ready/status: review/; s/status: pending \| claim-id: none \| claimed-at: none \| heartbeat-at: none/status: done | claim-id: none | claimed-at: none | heartbeat-at: none/' \
  "$TEST_ROOT/project/openspec/changes/done-unchecked/tasks.md"
if node "$REPO_ROOT/scripts/validate-change.mjs" --root "$TEST_ROOT/project" --change done-unchecked --type chore --phase review >/dev/null 2>&1; then
  printf 'Done group with unchecked tasks unexpectedly passed validation.\n' >&2
  exit 1
fi

mkdir -p "$TEST_ROOT/project/openspec/changes/feature-demo/specs"
cp "$TEST_ROOT/project/openspec/changes/demo/proposal.md" "$TEST_ROOT/project/openspec/changes/feature-demo/proposal.md"
cp "$TEST_ROOT/project/openspec/changes/demo/design.md" "$TEST_ROOT/project/openspec/changes/feature-demo/design.md"
cp "$TEST_ROOT/project/openspec/changes/demo/_DIR.md" "$TEST_ROOT/project/openspec/changes/feature-demo/_DIR.md"
cp "$TEST_ROOT/project/openspec/changes/demo/tasks.md" "$TEST_ROOT/project/openspec/changes/feature-demo/tasks.md"
printf '%s\n' \
  '## ADDED Requirements' '### REQ: Demo behavior' \
  '#### Scenario: normal success' '- Given valid input' '- When the action runs' '- Then a result is returned' \
  '#### Scenario: invalid input error' '- Given invalid input' '- When the action runs' '- Then an error is returned' \
  > "$TEST_ROOT/project/openspec/changes/feature-demo/specs/demo.md"
node "$REPO_ROOT/scripts/validate-change.mjs" --root "$TEST_ROOT/project" --change feature-demo --type feature --phase propose >/dev/null

printf '%s\n' \
  '## ADDED Requirements' '### REQ: Demo behavior' \
  '#### Scenario: normal success' '- Given valid input' '- When the action runs' '- Then a result is returned' \
  > "$TEST_ROOT/project/openspec/changes/feature-demo/specs/demo.md"
if node "$REPO_ROOT/scripts/validate-change.mjs" --root "$TEST_ROOT/project" --change feature-demo --type feature --phase propose >/dev/null 2>&1; then
  printf 'Incomplete feature scenarios unexpectedly passed validation.\n' >&2
  exit 1
fi

cp -R "$TEST_ROOT/project/openspec/changes/demo" "$TEST_ROOT/project/openspec/changes/claim-bad"
perl -0pi -e 's/status: ready/status: executing/; s/status: pending \| claim-id: none/status: executing | claim-id: none/' \
  "$TEST_ROOT/project/openspec/changes/claim-bad/tasks.md"
if node "$REPO_ROOT/scripts/validate-change.mjs" --root "$TEST_ROOT/project" --change claim-bad --type chore --phase dispatch >/dev/null 2>&1; then
  printf 'Executing group without claim timestamps unexpectedly passed validation.\n' >&2
  exit 1
fi

mkdir -p "$TEST_ROOT/mock-bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'if [ "$1 $2" = "pr list" ]; then exit 0; fi' \
  'if [ "$1 $2" = "pr create" ]; then echo https://example.test/pr/1; exit 0; fi' \
  'if [ "$1 $2" = "pr view" ]; then case "$*" in *".number"*) echo 1;; *".state"*) echo MERGED;; *mergeStateStatus*) printf "MERGEABLE\\tCLEAN\\n";; esac; exit 0; fi' \
  'if [ "$1 $2" = "pr merge" ]; then git push -q origin HEAD:main; exit 0; fi' \
  'exit 1' > "$TEST_ROOT/mock-bin/gh"
chmod +x "$TEST_ROOT/mock-bin/gh"
printf 'governed\n' > "$TEST_ROOT/repo/governance.txt"
printf 'user file\n' > "$TEST_ROOT/repo/unrelated.txt"
git -C "$TEST_ROOT/repo" add governance.txt
printf '%s\n' 'chore: governance test' > "$TEST_ROOT/message.txt"
(cd "$TEST_ROOT/repo" && PATH="$TEST_ROOT/mock-bin:$PATH" "$REPO_ROOT/scripts/governance-publish.sh" \
  --skill audit --scope demo --title 'chore: governance test' \
  --commit-file "$TEST_ROOT/message.txt" -- governance.txt >/dev/null)
git -C "$TEST_ROOT/repo" status --short | grep -Fq '?? unrelated.txt'
git --git-dir="$TEST_ROOT/remote.git" show main:governance.txt | grep -Fq governed

printf 'allowed\n' > "$TEST_ROOT/repo/allowed.txt"
printf 'not allowed\n' > "$TEST_ROOT/repo/not-allowed.txt"
git -C "$TEST_ROOT/repo" add allowed.txt not-allowed.txt
if (cd "$TEST_ROOT/repo" && PATH="$TEST_ROOT/mock-bin:$PATH" "$REPO_ROOT/scripts/governance-publish.sh" \
  --skill audit --scope reject --title 'chore: reject scope' \
  --commit-file "$TEST_ROOT/message.txt" -- allowed.txt >/dev/null 2>&1); then
  printf 'Out-of-allowlist staged file unexpectedly passed governance publisher.\n' >&2
  exit 1
fi
git -C "$TEST_ROOT/repo" restore --staged allowed.txt not-allowed.txt

mkdir -p "$TEST_ROOT/mock-pending-bin"
printf '%s\n' '#!/usr/bin/env bash' \
  'state_file=${MOCK_GH_STATE_FILE:?}' \
  'state=$(test -f "$state_file" && sed -n "1p" "$state_file" || true)' \
  'if [ "$1 $2" = "pr list" ]; then' \
  '  [ -z "$state" ] && exit 0' \
  '  case "$*" in *".[0] // empty"*) echo present;; *".[0].state"*) echo "$state";; *".[0].number"*) echo 2;; esac' \
  '  exit 0' \
  'fi' \
  'if [ "$1 $2" = "pr create" ]; then echo OPEN > "$state_file"; echo https://example.test/pr/2; exit 0; fi' \
  'if [ "$1 $2" = "pr view" ]; then' \
  '  state=$(sed -n "1p" "$state_file")' \
  '  case "$*" in *".number"*) echo 2;; *".state"*) echo "$state";; *mergeStateStatus*) printf "MERGEABLE\\tCLEAN\\n";; esac' \
  '  exit 0' \
  'fi' \
  'if [ "$1 $2" = "pr merge" ]; then' \
  '  if [ "${MOCK_ALLOW_MERGE:-false}" = "true" ]; then git push -q origin governance/audit/pending:main; echo MERGED > "$state_file"; exit 0; fi' \
  '  case "$*" in *"--auto"*) exit 0;; *) exit 1;; esac' \
  'fi' \
  'exit 1' > "$TEST_ROOT/mock-pending-bin/gh"
chmod +x "$TEST_ROOT/mock-pending-bin/gh"
printf 'pending\n' > "$TEST_ROOT/repo/pending.txt"
git -C "$TEST_ROOT/repo" add pending.txt
if (cd "$TEST_ROOT/repo" && MOCK_GH_STATE_FILE="$TEST_ROOT/gh-state" PATH="$TEST_ROOT/mock-pending-bin:$PATH" \
  "$REPO_ROOT/scripts/governance-publish.sh" --skill audit --scope pending \
  --title 'chore: pending test' --commit-file "$TEST_ROOT/message.txt" -- pending.txt >/dev/null); then
  printf 'Pending governance publish unexpectedly returned success.\n' >&2
  exit 1
else
  pending_status=$?
  [ "$pending_status" -eq 2 ] || exit "$pending_status"
fi
if (cd "$TEST_ROOT/repo" && MOCK_GH_STATE_FILE="$TEST_ROOT/gh-state" PATH="$TEST_ROOT/mock-pending-bin:$PATH" \
  "$REPO_ROOT/scripts/governance-publish.sh" --check --skill audit --scope pending >/dev/null); then
  printf 'Open governance PR unexpectedly returned success from --check.\n' >&2
  exit 1
else
  pending_status=$?
  [ "$pending_status" -eq 2 ] || exit "$pending_status"
fi
(cd "$TEST_ROOT/repo" && MOCK_ALLOW_MERGE=true MOCK_GH_STATE_FILE="$TEST_ROOT/gh-state" \
  PATH="$TEST_ROOT/mock-pending-bin:$PATH" "$REPO_ROOT/scripts/governance-publish.sh" \
  --retry --skill audit --scope pending -- pending.txt >/dev/null)
git -C "$TEST_ROOT/repo" merge-base --is-ancestor origin/main main
git --git-dir="$TEST_ROOT/remote.git" show main:pending.txt | grep -Fq pending

printf 'Protocol E2E checks passed.\n'
