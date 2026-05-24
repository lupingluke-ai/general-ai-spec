# design/inputs/

L0 原始设计输入。纯人工录入，永久保留。

## 子目录

| 子目录 | 内容 | 命名 |
|---|---|---|
| `brainstorming/` | 头脑风暴、灵感笔记、方案讨论 | `YYYY-MM-DD-<topic>.md` |
| `figma/` | figma 原型链接 + 截图说明（接入方式待定，先以文本形式存放）| `<feature>-v<N>.md` |
| `interviews/` | 用户访谈、问卷、调研 | `user-<id>-<date>.md` |

## 引用约定

这些文件会被 PRD 的 `design-inputs` 字段引用，`prd-writer` 生成 PRD 时必读。
路径写全，例如：

```yaml
design-inputs:
  - design/modules/M-001-chat-assistant.md
  - design/inputs/brainstorming/2026-04-14-chat-assistant.md
  - design/inputs/figma/chat-ui-v1.md
```
