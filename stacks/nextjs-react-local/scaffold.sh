#!/usr/bin/env bash
# Stack scaffold: nextjs-react-local
# Creates a Next.js App Router project with local storage, no database.

set -euo pipefail

ROOT_DIR="${1:-.}"

echo "=== Scaffolding: nextjs-react-local ==="

# --- 1. Ensure pnpm ---
if ! command -v pnpm &>/dev/null; then
  if command -v corepack &>/dev/null; then
    corepack enable pnpm
  else
    npm install -g pnpm
  fi
fi

# --- 2. Create Next.js app ---
if [ ! -f "$ROOT_DIR/package.json" ]; then
  SCAFFOLD_TMP_DIR=$(mktemp -d)
  cleanup_scaffold_tmp() {
    if [ -n "${SCAFFOLD_TMP_DIR:-}" ] && [ -d "$SCAFFOLD_TMP_DIR" ]; then
      rm -rf -- "$SCAFFOLD_TMP_DIR"
    fi
  }
  trap cleanup_scaffold_tmp EXIT
  npx --yes create-next-app@16.2.11 "$SCAFFOLD_TMP_DIR/app" \
    --typescript --tailwind --eslint --app --src-dir \
    --use-pnpm --disable-git --no-agents-md \
    --no-import-alias --turbopack
  node - "$SCAFFOLD_TMP_DIR/app" "$ROOT_DIR" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [source, target] = process.argv.slice(2);
fs.cpSync(source, target, {
  recursive: true,
  force: false,
  errorOnExist: false,
  filter: (entry) => ![".git", "node_modules", ".next"].includes(path.basename(entry)),
});
NODE
  cleanup_scaffold_tmp
  SCAFFOLD_TMP_DIR=""
  echo "[OK] Next.js app scaffolded"
else
  echo "[SKIP] package.json already exists"
fi

# --- 3. Install dependencies ---
cd "$ROOT_DIR"
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

node <<'NODE'
const fs = require("node:fs");
const headers = new Map([
  ["src/app/page.tsx", `/**
 * @input Next.js request context and application assets.
 * @output Application home page.
 * @pos Root App Router page.
 */\n`],
  ["src/app/layout.tsx", `/**
 * @input React children, metadata, fonts, and global styles.
 * @output Root HTML layout for every route.
 * @pos Root App Router layout.
 */\n`],
  ["src/app/globals.css", `/*
 * @input Tailwind CSS and application theme variables.
 * @output Global styles shared by all routes.
 * @pos Root stylesheet imported by the App Router layout.
 */\n`],
]);
for (const [file, header] of headers) {
  if (!fs.existsSync(file)) continue;
  const source = fs.readFileSync(file, "utf8");
  if (!source.includes("@input")) fs.writeFileSync(file, header + source);
}
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
