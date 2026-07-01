# Plan: Phase 3 — ToolCall Enhancement + AgentStatusBar

## Goal
按顺序完成 Phase 3 的前两步：ToolCall 可视化增强（quick win），然后 AgentStatusBar 底部状态栏。

---

## Step 1: ToolCall 可视化增强 (3 files)

### 1a — ToolCallInfo 增加时间戳 (LiveToolCallView.swift)

- `ToolCallInfo` 加 `startedAt: Date` 和 `completedAt: Date?`
- `ToolCallPill` 中 running 状态的显示脉冲动画 + 实时秒数
- 展开 timeline 中完成项显示总耗时 `1.2s`

### 1b — 保留历史 ToolCall 调用 (AgentManager.swift)

- 新增 `@Published var toolCallHistory: [ToolCallInfo] = []` 持久化整个 streaming session 的调用记录
- `updateToolCalls()` 追加到 history，不覆盖
- streaming 结束时不清空 history，改为在**新消息开始时**清空
- history 上限 50 条，超出移除最早的

### 1c — 完整 detail 文本 (AgentManager.swift)

- `updateToolCalls` 的 `detail` 不再截断 prefix(60)
- Timeline 中用完整 detail + 可滚动

### 1d — 调用计数 badge

- `LiveToolCallBar` 左上角显示当前 session 的总调用次数
- 运行中/成功/失败的计数分别显示

---

## Step 2: AgentStatusBar — 底部状态栏 (3 new files + 2 modified)

### 2a — 新增 `AgentStatusBar.swift` (~150 lines)

底部全局状态栏，位于 HermesChatView 最底部（build log 下方/输入框下方）：

```
┌──────────────────────────────────────────────────────┐
│ ● Gateway Online  会话: Chat 5-26  │  supervisor · 响应中  🔧×3 │
└──────────────────────────────────────────────────────┘
```

- **左侧**: 连接状态指示灯（● Gateway Online/● Offline）+ 会话名称
- **右侧**: 当前 Agent 名称 + phase 标签 + 工具调用计次徽章

### 2b — AgentManager 新增状态属性

- `@Published var isGatewayOnline: Bool` — Gateway 连接状态
- `@Published var totalToolCallsThisSession: Int` — 当前会话工具调用总数
- `@Published var successfulToolCalls: Int` — 成功数
- `@Published var failedToolCalls: Int` — 失败数

### 2c — HermesChatView 集成

- build log 下方/输入框下方加入 `AgentStatusBar`
- 在 `sendMessage()` 中周期性检测 Gateway 可达性
- Gateway 掉线时状态栏红色提示

### 2d — Gateway 心跳检测 (HermesAPIClient.swift)

- 新增 `checkHealth() async -> Bool` 方法，请求 `GET /v1/models` 或 `/health`
- AgentManager 在 app 启动后每 30s 轮询一次
- 首次检测在 `onAppear` 时触发

---

## Verification

- [ ] Build succeeds (`xcodebuild build`)
- [ ] All 104 tests pass (`xcodebuild test`)
- [ ] ToolCall timeline 显示执行时长
- [ ] ToolCall 历史在 streaming 结束后仍可见
- [ ] 底部状态栏显示 Gateway 状态
- [ ] 状态栏显示当前 agent + phase

## Risks

- Gateway 心跳可能被 macOS 防火墙阻止 — fallback 静默显示 Offline
- 底部状态栏和 build log 之间的布局关系需要处理好（build log 展开时状态栏下移）
- ToolCall 历史保留需要合适的内存上限
