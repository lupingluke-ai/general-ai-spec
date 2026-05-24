# 技术栈禁令: nextjs-react-drizzle

> 以下禁令是 core/AGENTS.md 通用禁令的技术栈特定补充。

- 不在 Server Component 中使用客户端交互 API（useState, useEffect, useRef 等）
- 不在 `"use client"` 组件中直接做服务端数据获取或访问 Node.js API
- 不在前端存储认证 token 到 localStorage
- 不绕过 Drizzle 直接手写 SQL 或手动修改数据库
- 不手动改数据库 schema，必须通过 Drizzle Kit migration
- 不绕过 Zod 直接信任外部输入（API 请求、AI 返回、用户表单）
- 不在 Agent graph 中做未经 interrupt 的危险操作（删除、付款等）
- 不在流式输出中省略错误事件类型
