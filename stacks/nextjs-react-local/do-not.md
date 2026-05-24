# 技术栈禁令: nextjs-react-local

> 以下禁令是 core/AGENTS.md 通用禁令的技术栈特定补充。

- 不在 Server Component 中使用客户端交互 API（useState, useEffect, useRef 等）
- 不在 `"use client"` 组件中直接做服务端数据获取或访问 Node.js API
- 不在前端存储认证 token 到 localStorage
- 不在 Route Handler 中硬编码 AI provider，必须通过环境变量切换
- 不绕过 Zod 直接信任外部输入（API 请求、AI 返回、用户表单）
- 不在测试中 mock localStorage 的读写行为，直接使用 jsdom 提供的实现
- 不在 Route Handler 文件（`route.ts`）中 export 非 HTTP handler 函数——`next build` 会将非法 export 视为错误
- 不在使用 `useSearchParams()` 的页面中省略 `<Suspense>` 边界——会导致静态预渲染失败
