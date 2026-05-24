# Tech Stack Profile: nextjs-react-drizzle

> 适用于：全栈 AI SaaS 应用，PostgreSQL 持久化，LangGraph Agent 工作流。
> 典型场景：多用户 SaaS 平台、AI Agent 驱动的业务系统。

---

## Tech Stack

### Frontend
- **Framework**: Next.js 16 (App Router)
- **UI Library**: React 19
- **Language**: TypeScript 5.x (strict mode)
- **Styling**: Tailwind CSS 4
- **Validation**: Zod + react-hook-form
- **Testing**: Vitest + Playwright

### AI Layer
- **Agent Framework**: LangGraph (TypeScript SDK)
- **LLM SDK**: Anthropic SDK
- **Workflow**: StateGraph + interrupt/resume
- **Streaming**: SSE

### Backend
- **Runtime**: Node.js 22 LTS
- **API Layer**: Next.js Route Handlers
- **Authentication**: NextAuth.js v5
- **Authorization**: RBAC

### Database
- **Primary DB**: PostgreSQL 16
- **ORM**: Drizzle ORM
- **Migrations**: Drizzle Kit
- **Optional Extensions**: pgvector

### Tooling
- **Package Manager**: pnpm 10.x
- **Spec System**: OpenSpec
- **AI Coding Tools**: Claude Code（规划/审查）+ 任意 dispatch runner（Codex Automation / `/loop` / cron / GH Actions，runner-agnostic）

---

## Standard Runtime Requirements

- Node.js 22.x
- pnpm 10.x
- PostgreSQL 16
- Docker (optional, for local database bootstrap)

---

## Coding Conventions

### 语言
- 代码标识符使用英文
- 业务注释和 `_DIR.md` 使用中文
- 文件头 `@input/@output/@pos` 使用英文短句
- OpenSpec 产物以中文为主，技术术语保留英文

### TypeScript
- 禁止 `any`
- 函数参数和返回值必须有明确类型
- 使用 Zod 做运行时校验
- 优先保持文件与函数简洁

### React / Next.js
- 默认 Server Component
- 只有需要交互时才使用 `"use client"`
- 服务端数据获取优先放在 Server Component 或 Route Handler
- 避免把本应在服务端完成的逻辑下沉到客户端

### Database
- schema 变更必须通过 migration
- 优先通过 Drizzle 访问数据库
- 数据库连接配置默认与 `.env.local` 保持一致

---

## Implementation Order

DB schema → migration → DB queries → Agent tools/nodes → Agent graph → API Route → UI Components → Page → Tests → 分形文档检查

---

## Architecture

```text
Frontend (Next.js App Router)
  → Route Handlers / Server Actions
  → Agent orchestration layer (LangGraph)
  → Tool layer / domain services
  → Database layer (Drizzle + PostgreSQL)
```

推荐目录结构：

```text
src/
├── app/                # 页面、布局、路由、API handlers
├── components/         # UI 组件
├── lib/
│   ├── db/             # schema, queries, migrations helpers
│   ├── auth/           # 认证与会话配置
│   ├── agents/         # graph, nodes, tools, checkpointer
│   └── streaming/      # SSE writer / event types
├── hooks/              # 前端交互 hooks
├── stores/             # Zustand stores
├── types/              # 共享类型
└── styles/             # 设计系统或样式分层
```

---

## Verification Baseline

```bash
node -v                    # Node 22.x
pnpm -v                    # pnpm 10.x
pnpm install               # 依赖安装成功
pnpm lint                  # Linting 通过
pnpm build                 # 构建成功
pnpm dev                   # 开发服务器启动
docker ps                  # PostgreSQL 容器运行中（如果用 Docker）
```
