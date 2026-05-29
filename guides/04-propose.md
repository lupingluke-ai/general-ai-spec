# 规划阶段：从 PRD 到四件套

本阶段由交互式 agent（Claude Code / Codex）执行，使用 `change-propose` skill。

## 前提

- 对应的 backlog 条目存在
- PRD 已生成且 `approved`（见 [03-prd.md](./03-prd.md)）

## 触发方式

```
你：基于 B-003 做 AI 语音记账
你：帮我规划 B-003
你：/change-propose B-003
```

交互式 agent 收到后自动进入 change-propose 流程。

### 自动触发

配置定时扫描后，PRD approved 即可自动触发 propose：

```
/loop 15m /change-propose
```

`change-propose` 自动扫描 backlog 中 PRD 已 approved 但尚未 proposed 的条目，检查依赖就绪性后自动生成四件套。详见 `skills/change-propose/SKILL.md`。

## Phase 0 — 定位 Backlog、检查 PRD

### 0.1 定位

交互式 agent 读取 `product/backlog.md`，找到 B-003 条目。如果不存在，停止 propose，先通过 `/design` 或 `/design review M-NNN` 建立模块归属和 backlog 条目。

### 0.2 检查 PRD

交互式 agent 读取 `product/prd/PRD-003.md`：

- **PRD approved** → 继续，后续 proposal 从 PRD 的用户故事和功能需求出发
- **PRD 存在但未 approved** → 提示先审阅 PRD
- **PRD 不存在** → 停止 propose，先执行 `/prd B-003`

> 变更粒度评估不在 propose 阶段做——拆分已由 `module-designer` 在 `/design` 阶段与用户对话时确定。propose 阶段信任 backlog/PRD 的粒度决定，不做二次检查，以免阻塞 `/loop` 自动化。

## Phase 1 — 生成四件套

交互式 agent 在 `openspec/changes/<change-id>/` 下创建：

### proposal.md

必须包含：
- **Backlog Ref**: `B-003`（关联 backlog 条目）
- **PRD Ref**: `PRD-003`（关联 PRD；PRD 是硬前置）
- **Intent**: 为什么做这个变更（从 PRD 背景与问题提炼）
- **Scope**: 覆盖什么 / 不覆盖什么
- **Approach**: 技术路线，包含并行策略
- **Impact**: 受影响目录、_DIR.md 清单、环境变量、Breaking Changes
- **复杂度估算**: S / M / L / XL
- **依赖说明**（如果是多 change 序列）

### specs/（Delta Specs）

按受影响的领域分文件，使用三个标记：

```markdown
## ADDED Requirements

### REQ: 语音输入识别
用户语音输入 SHALL 被转换为文本并发送到 AI 提取接口。

**Scenario: 成功识别中文语音**
- GIVEN 用户点击语音按钮并说 "午饭花了32块"
- WHEN 浏览器 Speech API 完成识别
- THEN 系统获得文本 "午饭花了32块"

## MODIFIED Requirements

### REQ: 首页快捷操作区
首页快捷操作区 SHALL 包含语音按钮。
（之前：仅包含"快速记一笔"和"查看统计"两个按钮）

## REMOVED Requirements
（无）
```

**规则：** 每个需求至少一个 Given/When/Then 场景。归档时这些 delta specs 会合并到 `openspec/specs/` 主文件中。

### design.md

必须包含：
- Technical Approach
- 新增/修改的目录与文件清单
- 需要新增或更新的 `_DIR.md` 清单
- 需要新增或更新头注释的关键文件清单
- API 设计（如涉及）
- 并行开发设计：G0/G1/G2 分组 + 文件冲突矩阵

### tasks.md

```yaml
---
status: draft
backlog-ref: B-003
depends-on: []
---
```

按任务组分节，每组用 HTML 注释标注元信息：

```markdown
## 共享基础设施

<!-- 执行模式: auto | 约束: 串行，必须先完成 | status: pending -->

- [ ] 创建 AI 提取类型定义和 Zod schema
- [ ] 创建分类匹配工具函数和单元测试
- [ ] 创建 AI 提取 API 路由

## 语音入口组件

<!-- 执行模式: auto | 约束: G0 完成后 | status: pending -->

- [ ] 创建 Web Speech API Hook
- [ ] 创建语音记账按钮组件和测试

## 文档与分形同步

<!-- 执行模式: interactive | 约束: 全部合并完成后 | status: pending -->

- [ ] 同步更新新增目录的 _DIR.md
- [ ] 更新 openspec/project.md 目录结构
- [ ] 运行 pnpm test、pnpm lint、pnpm build

## Verify

<!-- 执行模式: interactive | 约束: 分形同步完成后 | status: pending -->

- [ ] Completeness / Correctness / Coherence

## 归档

<!-- 执行模式: interactive | 约束: verify 通过后 | status: pending -->

- [ ] Sync delta specs → 归档 → 更新 backlog
```

**关键约束：**
- tasks.md 不超过 300 行（典型 15-50 行）
- 不内联代码 — dispatch runner 有代码库访问权限和 design.md
- "文档与分形同步"和"归档"是固定的最后两个任务组

## Phase 2 — Pre-flight & 标记 Ready

### Pre-flight 检查清单

交互式 agent 在标记 ready 前自动验证：

- [ ] proposal.md 已落盘（含 Backlog Ref）
- [ ] specs/ 已落盘（至少一个 delta spec 文件）
- [ ] design.md 已落盘
- [ ] tasks.md 已落盘（含 YAML 状态头）
- [ ] _DIR.md 已落盘
- [ ] openspec/changes/_DIR.md 已更新
- [ ] delta specs 每个需求至少一个 Given/When/Then
- [ ] tasks.md ≤ 300 行
- [ ] 并行组内无文件写入冲突

### 标记 Ready

Pre-flight 通过后：

1. tasks.md YAML 头 `status` → `ready`
2. 创建 feature branch `<branch-prefix>/<change-id>`（前缀由 change-id 类型派生，见 [11-task-types.md](./11-task-types.md)），将四件套提交到该分支
3. 推送分支并创建 Draft PR
4. 在 main 上更新 `product/backlog.md` 对应条目阶段 → `proposed`，Change 列写入 change-id（1:1）
5. 更新 `openspec/changes/_DIR.md` 索引表（含 branch、PR link）

**此时人工工作结束。** 后续由 dispatch runner（Codex Automation / `/loop` / cron / GH Actions 任选其一）自动接管执行。

## 输出物

```
openspec/changes/ai-voice-entry/
├── _DIR.md
├── proposal.md         ← Backlog Ref: B-003
├── specs/
│   └── ai-voice.md     ← ADDED/MODIFIED/REMOVED
├── design.md           ← 文件清单 + 并行设计
└── tasks.md            ← status: ready, backlog-ref: B-003
```

## 下一步

tasks.md 标记为 ready 后，dispatch runner 会在下一个 5 分钟周期自动领取（runner 配置见 [05-execution.md](./05-execution.md)）。

> **自动化提示：** 使用 `/loop 15m /change-propose` 可跳过手动触发，PRD approved 后自动进入 propose 流程。
