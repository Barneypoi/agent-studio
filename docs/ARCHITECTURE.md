# 实现结构

- `game/main.gd`：Godot 原生界面、可调宽度的房间与对话侧栏、人物编辑、技能与任务操作。对话面板按任务保留输入草稿和阅读位置，与场景共用主视口；设置类窗口使用独立弹窗。
- `game/conversation_view.gd`：按消息 ID 更新左右气泡，支持文本选择、完整对话复制和阅读位置保留；工具记录继续使用独立文本视图。
- `game/world.gd`：绘制俯视像素场景、角色移动与入座/离座状态、地图交互。角色在可行走的椅侧入口结束寻路，再过渡到坐姿；坐姿、名称和点击区域共用显示位置，椅背独立绘制以正确遮挡人物。
- `game/pixel_art.gd`：自绘角色和家具，所有像素美术均包含在源码中。
- `game/studio_model.gd`：房间/家具数据、连通性校验、寻路、撤销与原子存档。
- `bridge/server.mjs`：Node.js 标准库实现的本地桥接，不依赖 npm 包。
- `bridge/approvals.mjs`：将原生审批选项转换成带授权范围的界面选项；提交时按待审批请求重新解析选择，拒绝无效选项，不接受前端自拟规则。
- `bridge/conversation.mjs`：保存有序的用户/角色消息，按 `clientUserMessageId`、原生 turn/item ID 合并回显、流式输出和完成事件；失败的追加输入撤回。首次打开旧任务通过 `/conversation` 读取本机原始历史迁移，无法恢复时展示带说明的旧版记录。

桥接仅监听 127.0.0.1 的随机端口，用每次启动生成的随机 token 鉴权，并拒绝来自浏览器 Origin 的请求。Godot 使用 HTTPRequest 发送指令并轮询快照；桥接通过 JSONL RPC 连接 Codex App Server。

对话收尾使用桥接 `/finish`，在 `tasks.json` 保存 `endedAt`，保留原执行状态、结果和时间顺序。界面将已结束的当前对话映射为待命，历史仍可读；新一轮执行事件会清除结束标记。负责人及后代全部处于终态后才可一起结束，此操作不调用 Codex。

角色档案与任务实例分开。每个任务保存创建时的外观/职责/技能快照。新任务启用当前角色的技能配置，并用真实 `skill` 输入调用；配置不写入用户全局 config.toml。团队模式将其他角色的职责和技能交给负责人，用原生 subagent 执行。`thread/started`、`collabAgentToolCall` 和 `subAgentActivity` 用于发现子任务。

状态来源是实际协议事件。任务结束区分 completed、failed、interrupted；完成含义是执行结束，仍需用户验收。用户审批和问题逐条转回原来的 RPC 请求。角色待命时的散步仅是环境动画。

审批优先使用 `availableDecisions`，旧版本未提供时按协议支持的决策和建议规则构建选项。规则授权原样回传 `acceptWithExecpolicyAmendment` 或 `applyNetworkPolicyAmendment`；任务会话授权使用 `acceptForSession` 或权限请求的 `scope: session`。规则保存交由 Codex 完成，应用不另建绕过审批的白名单。停止任务只拒绝待审批请求，不建立持久拒绝规则。

数据：`studio.json` 保存布局与角色；`tasks.json` 保存消息/日志/任务快照；`codex-state/` 和 `codex-logs/` 是桥接管理的本地运行数据。任务消息和工具结果属于项目数据，不打包分享给其他人。

Codex App Server 有版本差异，桥接基于本机 CLI 生成的协议核对。恢复子 agent 时先恢复其父任务；直接输入若不被后端允许，会通过父 agent 转达，界面明确显示转达状态。角色映射优先使用原生 task_name 和委派中的档案标记，并处理迟到的角色信息。游戏通过实际 HTTP 连接检查已有桥接，避免依赖 macOS 上仅适用于子进程的 Godot PID 查询。端到端验证状态见 VALIDATION.md。
