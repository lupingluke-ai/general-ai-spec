#!/usr/bin/env bash
# Stack scaffold: nextjs-react-drizzle
# Creates a Next.js App Router project with PostgreSQL + Drizzle ORM.

set -euo pipefail

ROOT_DIR="${1:-.}"

echo "=== Scaffolding: nextjs-react-drizzle ==="

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
pnpm add drizzle-orm pg @auth/drizzle-adapter next-auth@beta @anthropic-ai/sdk @langchain/langgraph
pnpm add -D drizzle-kit @types/pg vitest @playwright/test
node <<'NODE'
const fs = require("fs");
const pkgPath = "package.json";
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
pkg.scripts = pkg.scripts || {};
pkg.scripts.test = pkg.scripts.test || "vitest run --passWithNoTests";
pkg.scripts["test:e2e"] = pkg.scripts["test:e2e"] || "playwright test";
fs.writeFileSync(pkgPath, `${JSON.stringify(pkg, null, 2)}\n`);
NODE

# --- 4. Create .env.local ---
if [ ! -f ".env.local" ]; then
  cat > .env.local << 'ENVEOF'
# Database
DATABASE_URL=postgresql://dev:devpassword@localhost:5432/aidev

# Auth
AUTH_SECRET=dev-secret-change-in-production
NEXTAUTH_URL=http://localhost:3000

# AI
ANTHROPIC_API_KEY=
ENVEOF
  echo "[OK] .env.local created"
else
  echo "[SKIP] .env.local already exists"
fi

# --- 5. Initialize PostgreSQL (optional) ---
if command -v docker &>/dev/null; then
  if ! docker ps --format '{{.Ports}}' | grep -q '5432'; then
    docker run -d \
      --name aidev-postgres \
      -e POSTGRES_USER=dev \
      -e POSTGRES_PASSWORD=devpassword \
      -e POSTGRES_DB=aidev \
      -p 5432:5432 \
      postgres:16
    echo "[OK] PostgreSQL 16 container started"
  else
    echo "[SKIP] Port 5432 already in use"
  fi
else
  echo "[WARN] Docker not found — skip PostgreSQL setup. Provide your own database."
fi

echo "=== Scaffold complete ==="
