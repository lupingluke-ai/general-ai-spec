# design/modules/

L1 模块设计文档。由 `module-designer` skill 生成和维护。

## 命名

`M-NNN-<slug>.md`，其中：
- `M-NNN`：全局递增，由 `module-designer` 自动分配
- `<slug>`：kebab-case 短名

示例：`M-001-chat-assistant.md`、`M-002-voice-entry.md`

## 生命周期

| 状态 | 含义 | 谁回写 |
|---|---|---|
| `planning` | 模块设计刚完成，尚无 backlog 进入 exploring | `module-designer`（首次建）|
| `active` | 至少一个关联 backlog 进入 exploring+ | `prd-writer`（状态跃迁时）|
| `done` | 所有关联 backlog 已 done | `change-review`（最后一个归档时）|
| `deprecated` | 模块废弃（新需求不再落入）| 人工（`/design review M-NNN` 显式标记）|

## 自动同步

每次模块或 backlog 状态变更后，从 `design/modules/` + `product/backlog.md` 全量重渲染 `design/roadmap.md` 的三段 AUTO 区。

`## 关联 Backlog` 行必须保留 backlog 级依赖，格式为：

`- B-NNN <需求描述> [depends-on: B-XXX, B-YYY | none]`

阶段唯一存于 `product/backlog.md`，模块文档不保存阶段镜像。
