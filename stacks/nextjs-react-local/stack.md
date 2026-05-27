# Tech Stack Profile: nextjs-react-local

> 适用于：移动优先的前端应用，数据存储在 localStorage，AI 能力通过 API Route 对接。
> 典型场景：工具类 App MVP（记账、备忘、健康追踪等）。

---

## Tech Stack

### Frontend
- **Framework**: Next.js 16 (App Router)
- **UI Library**: React 19
- **Language**: TypeScript 5.x (strict mode)
- **Styling**: Tailwind CSS 4
- **Validation**: Zod + react-hook-form
- **Testing**: Vitest + @testing-library/react

### AI Layer
- **Provider**: 通过环境变量 `AI_PROVIDER` 切换（支持 Gemini / Kimi / Claude 等）
- **调用方式**: Next.js Route Handler → 服务端 SDK 调用 → 结构化 JSON 返回

### Backend
- **Runtime**: Node.js 22 LTS
- **API Layer**: Next.js Route Handlers
- **Authentication**: 无（MVP 阶段，本地单用户）

### Storage
- **Primary**: localStorage（MVP 阶段）
- **Migration Path**: 后续可迁移至 PostgreSQL + Drizzle ORM

### Tooling
- **Package Manager**: pnpm 10.x
- **Spec System**: OpenSpec
- **AI Coding Tools**: 交互式 agent（Claude Code / Codex，用于规划/审查）+ 任意 dispatch runner（Codex Automation / Claude Code `/loop` / cron / GH Actions，runner-agnostic）

---

## Standard Runtime Requirements

- Node.js 22.x
- pnpm 10.x

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
- **Route Handler 约束**：`src/app/**/route.ts` 只允许 export HTTP handler（GET / POST / PUT / DELETE / PATCH），禁止 export 其他函数，否则 `next build` 会报错
- **useSearchParams 约束**：使用 `useSearchParams()` 的客户端组件必须被 `<Suspense>` 包裹，否则静态预渲染会失败

---

## Implementation Order

安装依赖 → 类型定义 → 业务逻辑/工具函数 → 测试 → API Route → UI 组件 → 页面集成 → 文档同步

---

## Architecture

```text
Frontend (Next.js App Router)
  → Route Handlers (API Layer)
  → AI Provider SDK (Gemini / Kimi / Claude)
  → localStorage (Client-side persistence)
```

推荐目录结构：

```text
src/
├── app/                # 页面、布局、路由、API handlers
├── components/         # UI 组件
├── lib/
│   ├── finance/        # 领域逻辑（以 finance 为例）
│   └── hooks/          # 前端交互 hooks
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
pnpm test                  # 测试通过
```
