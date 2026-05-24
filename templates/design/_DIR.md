# design/

设计层根目录。产品从灵感到可执行 backlog 的收敛过程在这里沉淀。

## 结构

```
design/
├── _DIR.md            ← 本文件
├── roadmap.md         ← 全局统筹（愿景 + 架构 + 依赖 + 进度）
├── inputs/            ← L0 原始设计输入（纯人工录入）
│   ├── brainstorming/ ← 头脑风暴、灵感笔记
│   ├── figma/         ← figma 链接 + 截图说明
│   └── interviews/    ← 用户访谈记录
└── modules/           ← L1 模块设计（module-designer 生成）
    └── M-NNN-<slug>.md
```

## 维护边界

| 文件 | 维护方 | 说明 |
|---|---|---|
| `roadmap.md`（非 AUTO 段） | 人工 | 愿景、设计原则、里程碑 |
| `roadmap.md`（AUTO 段） | skill | 架构 / 依赖 / 进度，实时写入 |
| `inputs/**` | 人工 | 原始设计资产永久保留 |
| `modules/M-NNN-*.md` | `module-designer` | 建模块 + 拆 idea 时生成/更新 |

## 调用关系

```
inputs/ ──► /design M-NNN ──► modules/M-NNN.md
                │
                └──► product/backlog.md（写入 idea）
                └──► roadmap.md（更新 AUTO 段）
```

执行规则以 `skills/module-designer/SKILL.md`、`openspec/config.yaml` 和本目录 `_DIR.md` 为准。
