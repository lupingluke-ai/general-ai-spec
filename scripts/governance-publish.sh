#!/usr/bin/env bash
# Publish already-staged governance changes through a deterministic PR branch.

set -euo pipefail

MODE="publish"
SKILL_NAME=""
SCOPE_ID=""
PR_TITLE=""
COMMIT_FILE=""
ALLOWED_PATHS=()

usage() {
  printf '%s\n' \
    "Usage:" \
    "  governance-publish.sh --check --skill <name> --scope <id>" \
    "  governance-publish.sh --retry --skill <name> --scope <id> -- <allowed-path>..." \
    "  governance-publish.sh --skill <name> --scope <id> --title <title> --commit-file <file> -- <allowed-path>..."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --retry) MODE="retry"; shift ;;
    --skill) SKILL_NAME="$2"; shift 2 ;;
    --scope) SCOPE_ID="$2"; shift 2 ;;
    --title) PR_TITLE="$2"; shift 2 ;;
    --commit-file) COMMIT_FILE="$2"; shift 2 ;;
    --) shift; ALLOWED_PATHS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! "$SKILL_NAME" =~ ^[a-z0-9-]+$ ]]; then
  printf 'Invalid --skill: %s\n' "$SKILL_NAME" >&2
  exit 1
fi
if [[ ! "$SCOPE_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'Invalid --scope: %s\n' "$SCOPE_ID" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
GOVERNANCE_BRANCH="governance/$SKILL_NAME/$SCOPE_ID"

switch_to_main() {
  if [ "$(git branch --show-current)" != "main" ]; then
    git switch main
  fi
}

attempt_merge() {
  local pr_number="$1"
  local pr_label="$2"
  local pr_state
  local pr_mergeability

  if gh pr merge "$pr_number" --merge --delete-branch; then
    pr_state=$(gh pr view "$pr_number" --json state --jq '.state')
    switch_to_main
    if [ "$pr_state" = "MERGED" ]; then
      git pull --ff-only origin main
      git branch -D "$GOVERNANCE_BRANCH" 2>/dev/null || true
      printf 'MERGED: %s\n' "$pr_label"
      return 0
    fi
    printf 'PENDING: merge request accepted but PR is still %s: %s\n' "$pr_state" "$pr_label"
    return 2
  fi

  if gh pr merge "$pr_number" --auto --merge --delete-branch; then
    pr_state=$(gh pr view "$pr_number" --json state --jq '.state')
    switch_to_main
    if [ "$pr_state" = "MERGED" ]; then
      git pull --ff-only origin main
      git branch -D "$GOVERNANCE_BRANCH" 2>/dev/null || true
      printf 'MERGED: %s\n' "$pr_label"
      return 0
    fi
    printf 'PENDING: %s\n' "$pr_label"
    return 2
  fi

  switch_to_main
  pr_mergeability=$(gh pr view "$pr_number" --json mergeable,mergeStateStatus \
    --jq '[.mergeable,.mergeStateStatus] | @tsv')
  if [[ "$pr_mergeability" = CONFLICTING$'\t'* ]] || [[ "$pr_mergeability" = *$'\t'DIRTY ]]; then
    printf 'STOP: governance PR has merge conflicts: %s\n' "$pr_label" >&2
    return 1
  fi
  printf 'PENDING: PR needs checks or human review; auto-merge could not be enabled: %s\n' "$pr_label"
  return 2
}

existing_pr=$(gh pr list --head "$GOVERNANCE_BRANCH" --state all --limit 1 \
  --json number,state,url --jq '.[0] // empty')
if [ -n "$existing_pr" ]; then
  pr_state=$(gh pr list --head "$GOVERNANCE_BRANCH" --state all --limit 1 \
    --json state --jq '.[0].state')
  pr_number=$(gh pr list --head "$GOVERNANCE_BRANCH" --state all --limit 1 \
    --json number --jq '.[0].number')
  if [ "$pr_state" = "OPEN" ]; then
    pr_mergeability=$(gh pr view "$pr_number" --json mergeable,mergeStateStatus \
      --jq '[.mergeable,.mergeStateStatus] | @tsv')
    if [[ "$pr_mergeability" = CONFLICTING$'\t'* ]] || [[ "$pr_mergeability" = *$'\t'DIRTY ]]; then
      printf 'STOP: governance PR #%s has merge conflicts for %s\n' "$pr_number" "$GOVERNANCE_BRANCH" >&2
      exit 1
    fi
    if [ "$MODE" = "retry" ]; then
      if [ "$(git branch --show-current)" != "main" ] || [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        printf 'STOP: --retry requires a clean local main worktree\n' >&2
        exit 1
      fi
      if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
        printf 'STOP: --retry requires the original allowlist\n' >&2
        exit 1
      fi
      git fetch origin main "$GOVERNANCE_BRANCH"
      retry_files=()
      while IFS= read -r -d '' retry_file; do
        retry_files+=("$retry_file")
      done < <(git diff --name-only -z "origin/main...origin/$GOVERNANCE_BRANCH")
      if [ ${#retry_files[@]} -eq 0 ]; then
        printf 'STOP: governance PR has no diff against main\n' >&2
        exit 1
      fi
      for retry_file in "${retry_files[@]}"; do
        allowed=false
        for allowed_path in "${ALLOWED_PATHS[@]}"; do
          normalized_path=${allowed_path%/}
          if [ -z "$normalized_path" ] || [ "$normalized_path" = "." ] || [ "$normalized_path" = ".." ] \
            || [[ "$normalized_path" = /* ]] || [[ "/$normalized_path/" = *"/../"* ]]; then
            printf 'STOP: invalid or overly broad allowlist path: %s\n' "$allowed_path" >&2
            exit 1
          fi
          if [ "$retry_file" = "$normalized_path" ] || [[ "$retry_file" = "$normalized_path/"* ]]; then
            allowed=true
            break
          fi
        done
        if ! $allowed; then
          printf 'STOP: PR path is outside the retry allowlist: %s\n' "$retry_file" >&2
          exit 1
        fi
      done
      git merge --ff-only origin/main
      attempt_merge "$pr_number" "PR #$pr_number"
      exit $?
    fi
    printf 'PENDING: governance PR #%s is still open for %s\n' "$pr_number" "$GOVERNANCE_BRANCH"
    exit 2
  fi
  if [ "$pr_state" = "MERGED" ]; then
    git fetch origin main
    if [ "$(git branch --show-current)" != "main" ]; then
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        printf 'STOP: merged recovery requires a clean tracked worktree before switching to main\n' >&2
        exit 1
      fi
      git switch main
    fi
    git merge --ff-only origin/main
    if git show-ref --verify --quiet "refs/heads/$GOVERNANCE_BRANCH"; then
      git branch -D "$GOVERNANCE_BRANCH"
    fi
    printf 'MERGED: governance PR #%s already completed\n' "$pr_number"
    exit 0
  fi
  printf 'STOP: governance PR #%s was closed without merge\n' "$pr_number" >&2
  exit 1
fi

if [ "$MODE" = "retry" ]; then
  printf 'STOP: no open governance PR to retry for %s\n' "$GOVERNANCE_BRANCH" >&2
  exit 1
fi

if [ "$MODE" = "check" ]; then
  if git ls-remote --exit-code --heads origin "$GOVERNANCE_BRANCH" >/dev/null 2>&1; then
    printf 'STOP: remote governance branch exists without a PR: %s\n' "$GOVERNANCE_BRANCH" >&2
    exit 1
  fi
  printf 'READY: no unfinished governance publish for %s\n' "$GOVERNANCE_BRANCH"
  exit 0
fi

if [ -z "$PR_TITLE" ] || [ -z "$COMMIT_FILE" ] || [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  usage >&2
  exit 1
fi
if [ ! -f "$COMMIT_FILE" ]; then
  printf 'Commit message file not found: %s\n' "$COMMIT_FILE" >&2
  exit 1
fi
if [ "$(git branch --show-current)" != "main" ]; then
  printf 'STOP: governance publish must start from local main\n' >&2
  exit 1
fi

git fetch origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  printf 'STOP: local main is not exactly origin/main; reconcile before publishing\n' >&2
  exit 1
fi

staged_files=()
while IFS= read -r -d '' staged_file; do
  staged_files+=("$staged_file")
done < <(git diff --cached --name-only -z)
if [ ${#staged_files[@]} -eq 0 ]; then
  printf 'STOP: no staged governance changes\n' >&2
  exit 1
fi

for staged_file in "${staged_files[@]}"; do
  allowed=false
  for allowed_path in "${ALLOWED_PATHS[@]}"; do
    normalized_path=${allowed_path%/}
    if [ -z "$normalized_path" ] || [ "$normalized_path" = "." ] || [ "$normalized_path" = ".." ] \
      || [[ "$normalized_path" = /* ]] || [[ "/$normalized_path/" = *"/../"* ]]; then
      printf 'STOP: invalid or overly broad allowlist path: %s\n' "$allowed_path" >&2
      exit 1
    fi
    if [ "$staged_file" = "$normalized_path" ] || [[ "$staged_file" = "$normalized_path/"* ]]; then
      allowed=true
      break
    fi
  done
  if ! $allowed; then
    printf 'STOP: staged path is outside the allowlist: %s\n' "$staged_file" >&2
    exit 1
  fi
done

if git show-ref --verify --quiet "refs/heads/$GOVERNANCE_BRANCH"; then
  printf 'STOP: local governance branch already exists: %s\n' "$GOVERNANCE_BRANCH" >&2
  exit 1
fi

git switch -c "$GOVERNANCE_BRANCH" origin/main
git commit -F "$COMMIT_FILE"
git push -u origin "$GOVERNANCE_BRANCH"

pr_url=$(gh pr create --base main --head "$GOVERNANCE_BRANCH" \
  --title "$PR_TITLE" \
  --body "Governance update published by $SKILL_NAME for $SCOPE_ID.")
pr_number=$(gh pr view "$GOVERNANCE_BRANCH" --json number --jq '.number')
attempt_merge "$pr_number" "$pr_url"
