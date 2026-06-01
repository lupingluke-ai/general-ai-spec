#!/usr/bin/env bash
# Stack scaffold: nextjs-react-local
# Creates a Next.js App Router project with local storage, no database.

set -euo pipefail

ROOT_DIR="${1:-.}"

echo "=== Scaffolding: nextjs-react-local ==="

# --- 1. Create Next.js app ---
if [ ! -f "$ROOT_DIR/package.json" ]; then
  TMPDIR=$(mktemp -d)
  npx create-next-app@16 "$TMPDIR/app" \
    --typescript --tailwind --eslint --app --src-dir \
    --no-git --no-import-alias --turbopack
  rsync -a --ignore-existing "$TMPDIR/app/" "$ROOT_DIR/"
  rm -rf "$TMPDIR"
  echo "[OK] Next.js app scaffolded"
else
  echo "[SKIP] package.json already exists"
fi

# --- 2. Ensure pnpm ---
cd "$ROOT_DIR"
if ! command -v pnpm &>/dev/null; then
  if command -v corepack &>/dev/null; then
    corepack enable pnpm
  else
    npm install -g pnpm
  fi
fi

# --- 3. Install dependencies ---
pnpm install
pnpm add -D vitest @testing-library/react @testing-library/jest-dom jsdom
node <<'NODE'
const fs = require("fs");
const pkgPath = "package.json";
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
pkg.scripts = pkg.scripts || {};
pkg.scripts.test = pkg.scripts.test || "vitest run --environment jsdom --passWithNoTests";
fs.writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

# --- 4. Create .env.local ---
if [ ! -f ".env.local" ]; then
  cat > .env.local << 'ENVEOF'
# AI Provider: gemini | kimi | claude
AI_PROVIDER=gemini

# Gemini
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.5-flash

# Kimi
KIMI_API_KEY=
KIMI_MODEL=kimi-k2.5

# Claude (optional)
ANTHROPIC_API_KEY=
ENVEOF
  echo "[OK] .env.local created"
else
  echo "[SKIP] .env.local already exists"
fi

echo "=== Scaffold complete ==="
