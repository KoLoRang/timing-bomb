/// Simplified Chinese translations keyed by English template.
/// Missing keys fall back to the English template at lookup time.
enum ZhHans {
    static let table: [String: String] = [
        // MARK: Error envelope (TBError.api / wire)

        "not found: {what}": "未找到：{what}",
        "validation error: {message}": "校验错误：{message}",
        "script error: {message}": "脚本错误：{message}",
        "node '{nodeId}' failed: {message}": "节点 “{nodeId}” 执行失败：{message}",
        "timeout: {what}": "超时：{what}",
        "cancelled": "已取消",
        "unsupported action: {action}": "不支持的动作：{action}",
        "invalid request: {message}": "请求无效：{message}",
        "internal error: {message}": "内部错误：{message}",
        "unauthorized": "未授权",
        "unauthorized: missing or invalid token": "未授权：token 缺失或无效",
        "invalid JSON body: {detail}": "请求体不是合法 JSON：{detail}",
        "request body is empty": "请求体为空",
        "HTTP {status}": "HTTP {status}",
        "--input is not valid JSON: {detail}": "--input 不是合法 JSON：{detail}",
        "failed to decode response: {detail}": "响应解析失败：{detail}",

        // MARK: Daemon lifecycle & HTTP layer

        "TimingBomb v{version} — listening on http://{host}:{port}":
            "TimingBomb v{version} — 监听 http://{host}:{port}",
        "LAN access enabled — the API is reachable from the local network (token still required)":
            "LAN 调用已开启 —— 局域网内的机器可访问 API（仍需 Token 鉴权）",
        "data dir: {path} ({count} flow(s) registered)": "数据目录：{path}（已注册 {count} 个流程）",
        "daemon: running ({status}, v{version}) — {url}":
            "daemon：运行中（{status}，v{version}）— {url}",
        "daemon is shutting down": "daemon 正在关闭",
        "daemon is not ready": "daemon 尚未就绪",
        "daemon unavailable": "daemon 不可用",
        "method {method} is not allowed for {path}": "方法 {method} 不适用于 {path}",
        "no route for {method} {path}": "没有匹配 {method} {path} 的路由",
        "missing {name}": "缺少 {name}",
        "run {runId} produced no record": "运行 {runId} 未产生记录",
        "flow not found": "流程不存在",
        "run not found": "运行记录不存在",
        "approval not found": "审批记录不存在",
        "flow validation failed ({count} error(s))": "流程校验失败（{count} 个错误）",
        "body must be [pattern] or {\"patterns\": [...]}": "请求体必须是 [pattern] 或 {\"patterns\": [...]}",
        "loggingEnabled must be a boolean": "loggingEnabled 必须是布尔值",
        "pending approval cannot be deleted; handle it first": "待审批记录不可删除，请先处理",

        // MARK: Run service

        "run {runId} is already running": "运行 {runId} 已在运行中",
        "run {runId} is still running; cancel it or wait for it to finish":
            "运行 {runId} 仍在运行中，请先取消或等待完成",
        "flow {flowId} has running tasks; cancel them or wait for them to finish":
            "流程 {flowId} 有运行中的任务，请先取消或等待完成",
        "there are running tasks; cancel them or wait for them to finish":
            "存在运行中的任务，请先取消或等待完成",

        // MARK: Approvals

        "TimingBomb · {name} failed": "TimingBomb · {name} 失败",
        "TimingBomb · {name} is waiting for approval": "TimingBomb · {name} 等待审批",
        "TimingBomb · {name} was rejected": "TimingBomb · {name} 已被拒绝",
        "Open the Approvals page to handle it": "请到「审批」页处理",
        "approval was already handled (current status: {status})": "审批已处理过（当前状态：{status}）",
        "run {runId} is not awaiting approval; cannot resume": "运行 {runId} 不处于待审批状态，无法恢复",
        "approval rejected{commentSuffix} (node {node})": "审批被拒绝{commentSuffix}（节点 {node}）",
        ": {comment}": "：{comment}",
        "failed to decode approval response": "审批响应解析失败",

        // MARK: CLI shared

        "TimingBomb — Mac task automation orchestration": "TimingBomb — Mac 自动化任务编排",
        "API token not found (expected at {path}). Start the daemon first: tb serve":
            "未找到 API token（预期位置 {path}）。请先启动 daemon：tb serve",
        "cannot connect to daemon ({url}). Start it first: tb serve":
            "无法连接 daemon（{url}）。请先运行：tb serve",
        "cannot connect to daemon. Start it first: tb serve": "无法连接 daemon。请先运行：tb serve",
        "failed to read file: {file}": "无法读取文件：{file}",
        "stdin is empty; provide --file or pipe flow JSON in": "stdin 为空；请提供 --file 或通过管道传入 flow JSON",
        "View daemon status": "查看 daemon 状态",
        "Start the daemon in the foreground": "前台启动 daemon",
        "Authentication info": "认证信息",
        "Print the API token": "打印 API token",
        "Output as JSON": "以 JSON 输出",
        "flow id": "流程 id",
        "run id": "run id",

        // MARK: CLI flow

        "Manage flows": "管理流程",
        "List flows": "列出流程",
        "Show a flow definition": "查看流程定义",
        "Create/update a flow (pass JSON via --file or stdin)": "创建/更新流程（--file 或 stdin 传入 JSON）",
        "path to the flow JSON file": "flow JSON 文件路径",
        "Validate a flow (without saving)": "校验流程（不保存）",
        "Delete a flow": "删除流程",
        "no flows yet. Create one with `tb flow create --file <flow.json>`.":
            "暂无流程。用 `tb flow create --file <flow.json>` 创建。",
        "✓ saved flow {id} ({name}, {count} node(s))": "✓ 已保存流程 {id}（{name}，{count} 个节点）",
        "✓ deleted flow {id}": "✓ 已删除流程 {id}",
        "✓ validation passed": "✓ 校验通过",
        "✗ validation failed:": "✗ 校验失败：",
        "NAME": "名称",
        "NODES": "节点",
        "TRIGGER": "触发",
        "UPDATED": "更新时间",

        // MARK: CLI run

        "Trigger a flow run": "触发一次流程运行",
        "input payload (JSON string); injected as ctx.trigger.payload":
            "输入 payload（JSON 字符串），注入 ctx.trigger.payload",
        "wait for the run to finish and print the result": "等待运行完成并打印结果",
        "dry-run: no real side effects (http/commands/file writes are skipped)":
            "试运行：不产生真实副作用（http/命令/文件写入等均被跳过）",
        "Run history": "运行历史",
        "List run history": "列出运行历史",
        "filter by flow id": "按流程 id 过滤",
        "number of records to return": "返回条数",
        "Show run details (node timeline / logs)": "查看运行详情（节点时间线/日志）",
        "Cancel a running run": "取消运行中的 run",
        "Delete one run record": "删除一条运行记录",
        "Clear run records": "清空运行记录",
        "only clear the given flow (default: all flows)": "只清空指定流程（缺省清空全部）",
        "skip confirmation": "跳过确认",
        "no run records yet": "暂无运行记录",
        "FLOW": "流程",
        "STATUS": "状态",
        "DURATION": "耗时",
        "STARTED": "开始时间",
        "✓ cancel request sent (runId={runId})": "✓ 已发送取消请求（runId={runId}）",
        "✓ deleted run record {runId}": "✓ 已删除运行记录 {runId}",
        "all flows": "全部流程",
        "flow {id}": "流程 {id}",
        "This will delete all run records for {scope}; it cannot be undone. Re-run with --yes to confirm.":
            "将删除 {scope} 的全部运行记录，不可恢复。确认请加 --yes",
        "✓ deleted {count} run record(s) for {scope}": "✓ 已删除 {scope} 的 {count} 条运行记录",
        "dry-run started: runId={runId} (no side effects; check `tb runs show {runId}`)":
            "试运行已启动：runId={runId}（无副作用；用 `tb runs show {runId}` 查看）",
        "started: runId={runId} (check `tb runs show {runId}` for progress)":
            "已启动：runId={runId}（用 `tb runs show {runId}` 查看进度）",
        "{mark} run {runId} — {status} ({duration})": "{mark} run {runId} — {status}（{duration}）",
        "  Error: {detail}": "  错误：{detail}",
        "        Error: {detail}": "        错误：{detail}",
        "        Log: {detail}": "        日志：{detail}",
        "  Trigger: {type}": "  触发：{type}",
        "  Node timeline:": "  节点时间线：",
        "  Final context:": "  最终上下文：",

        // MARK: CLI allow / logging

        "Manage the shell/appleScript allowlist": "管理 shell/appleScript 白名单",
        "List allowlist rules": "列出白名单规则",
        "Add an allowlist rule": "添加白名单规则",
        "rule: `git status` matches exactly; `git *` matches by prefix; `*` allows everything":
            "规则：`git status` 精确匹配；`git *` 前缀匹配；`*` 放行一切",
        "Remove an allowlist rule": "移除白名单规则",
        "rule to remove (exact text)": "要移除的规则（精确文本）",
        "(no rules)": "（无规则）",
        "already exists: {rule}": "已存在：{rule}",
        "✓ added: {rule}": "✓ 已添加：{rule}",
        "✓ removed: {rule}": "✓ 已移除：{rule}",
        "rule cannot be empty": "规则不能为空",
        "rule not found: {rule}": "规则不存在：{rule}",
        "Run history logging toggle (off: new runs are not written to the log)":
            "运行历史记录开关（关闭后新运行不写入执行日志）",
        "Show current state": "查看当前状态",
        "Enable run logging": "开启运行记录",
        "Disable run logging": "关闭运行记录",
        "run logging: on": "运行记录：开启",
        "run logging: off (new runs are not written to the log)": "运行记录：关闭（新运行不写入执行日志）",
        "✓ run logging enabled": "✓ 运行记录已开启",
        "✓ run logging disabled (new runs are not written to the log)":
            "✓ 运行记录已关闭（新运行不写入执行日志）",

        // MARK: App sidebar / status bar / theme

        "Flows": "任务",
        "Approvals": "审批",
        "Runs": "执行日志",
        "Settings": "设置",
        "Open Main Window": "打开主窗口",
        "Quit TimingBomb (service keeps running)": "退出 TimingBomb（服务继续运行）",
        "Quit and Stop Service": "退出并停止服务",
        "Service running": "服务运行中",
        "Service stopped": "服务已停止",
        "Checking service state": "正在检测服务状态",
        "System": "随系统",
        "Light": "日间",
        "Dark": "夜晚",

        // MARK: App flows page

        "New flow": "新建流程",
        "Refresh": "刷新",
        "No flows yet\nClick + to create, or import with tb flow create":
            "暂无任务\n点击 + 新建，或用 tb flow create 导入",
        "Delete": "删除",
        "Select a flow on the left to view its workflow": "选择左侧任务查看工作流",
        "{count} node(s)": "{count} 节点",
        "Manual trigger": "手动触发",
        "Scheduled trigger": "定时触发",
        "Webhook trigger": "外部API触发",
        "File watch trigger": "文件监听",
        "Dry-run": "试运行",
        "Workflow · click a node to edit": "工作流 · 点击节点编辑",
        "Triggered": "已触发",
        "OK": "好",
        "Flow name": "任务名称",
        "Unsaved": "未保存",
        "Save changes": "保存修改",
        "Run now": "立即运行",
        "Trigger": "触发方式",
        "Manual": "手动",
        "Webhook": "外部API",
        "Schedule": "定时",
        "File watch": "文件监听",
        "cron (e.g. 0 9 * * 1-5)": "cron（如 0 9 * * 1-5）",
        "Skip missed": "错过跳过",
        "Catch up once": "错过补跑",
        "Watched directory (e.g. ~/Downloads/inbox)": "监听目录（如 ~/Downloads/inbox）",
        "Fires on file create/modify/delete inside the directory (recursive, 2.5s debounce)":
            "目录内文件新增/修改/删除时触发（递归监听，2.5s 去抖聚合）",
        "Description": "描述",
        "Optional": "可选",
        "New Flow": "新建任务",
        "Flow ID (letters/digits/._-, e.g. daily-report)": "任务 ID（字母数字._-，如 daily-report）",
        "Creates a flow with one skeleton code node. After saving, click the node to edit its JS.":
            "将创建包含一个代码节点骨架的流程，保存后点击节点即可编辑 JS。",
        "Cancel": "取消",
        "Create": "创建",
        "Step 1": "第一步",
        "Run · {flowId}": "运行 · {flowId}",
        "Input payload (injected as ctx.trigger.payload; optional)":
            "输入 payload（注入 ctx.trigger.payload，可留空）",
        "Dry-run (no real side effects)": "试运行（dry-run，不产生真实副作用）",
        "Launch": "启动",
        "payload is not valid JSON": "payload 不是合法 JSON",
        "Dry-run {runId} started (no side effects). See the Runs page":
            "试运行 {runId} 已启动（无副作用），到「执行日志」页查看",
        "Run {runId} started. See the Runs page for progress": "已启动 run {runId}，到「执行日志」页查看进度",

        // MARK: App runs page

        "Select a run on the left to view details": "选择左侧运行记录查看详情",
        "Delete this run record?": "删除这条运行记录？",
        "This cannot be undone: {runId}": "删除后不可恢复：{runId}",
        "Clear all run records?": "清空全部运行记录？",
        "Clear run records for {scope}?": "清空「{scope}」的运行记录？",
        "Clear": "清空",
        "This cannot be undone (running tasks are not affected)": "删除后不可恢复（运行中的任务不受影响）",
        "Filter by flow": "按任务过滤",
        "Delete the selected run record": "删除选中的运行记录",
        "Clear all run records": "清空全部运行记录",
        "Clear run records of the filtered flow": "清空当前过滤流程的运行记录",
        "No run records yet": "暂无运行记录",
        "Delete this record": "删除这条记录",
        "The flow definition for this run could not be found": "找不到该运行对应的流程定义",
        "Flow graph · click a node to view its input / output": "流程图 · 点击节点查看输入 / 输出",
        "{count} node execution(s) in total": "共 {count} 次节点执行",
        "No node selected": "未选择节点",
        "Node “{name}” has no execution record in this run": "节点「{name}」在本次运行中没有执行记录",
        "The flow may have taken another branch, or ended before reaching it":
            "可能流程走了其他分支，或在到达该节点前已结束",
        "Click a node in the flow graph above": "在上方流程图中点击一个节点",
        "Its input and output will appear below in two panes": "下方将分上下两栏展示该节点的输入与输出",
        "#{index} · {status}": "第{index}次 · {status}",
        "This node ran {count} time(s) in this run; pick which one to view":
            "该节点在本次运行中执行了 {count} 次，可选择查看哪一次",
        "Input": "输入",
        "iter {n}": "迭代 {n}",
        "(no input snapshot for this record; it may come from an older TimingBomb version)":
            "（该记录没有输入快照：可能由旧版本 TimingBomb 生成）",
        "Output": "输出",
        "Trigger payload & final context": "触发 payload 与最终上下文",
        "Close": "关闭",
        "Final context": "最终 context",
        "Trigger: {type}": "触发：{type}",
        "Duration {duration}": "耗时 {duration}",
        "View trigger payload & final context": "查看触发 payload 与最终上下文",

        // MARK: App approvals page

        "Pending": "待审批",
        "History": "审批历史",
        "{label} ({count})": "{label}（{count}）",
        "Clear the whole approval history": "清除全部审批历史",
        "Clear the whole approval history?": "清除全部审批历史？",
        "Deletes all decided approval records (pending ones are kept); this cannot be undone":
            "将删除全部已决审批记录（待审批不受影响），不可恢复",
        "Nothing pending approval": "暂无待审批事项",
        "No approval history yet": "暂无审批历史",
        "Select an approval on the left": "选择左侧审批事项",
        "Node": "节点",
        "{name} ({nodeId})": "{name}（{nodeId}）",
        "Run": "运行",
        "Created": "发起时间",
        "Decided": "处理时间",
        "Comment": "备注",
        "Comment (optional, stored with the decision)": "备注（可选，随决策记录）",
        "Approve & resume": "同意并继续执行",
        "Reject": "拒绝",
        "Approved": "已同意",
        "Rejected": "已拒绝",
        "Comment: {comment}": "备注：{comment}",

        // MARK: App node editor

        "Edit Node · {name}": "编辑节点 · {name}",
        "Basics": "基础",
        "Node ID": "节点 ID",
        "Type": "类型",
        "Name (optional)": "名称（可选）",
        "Language": "语言",
        "JavaScript (built-in sandbox)": "JavaScript（内嵌沙箱）",
        "Python (system interpreter)": "Python（系统解释器）",
        "Shell (zsh)": "Shell（zsh）",
        "Execution Policy": "执行策略",
        "Timeout (ms)": "超时 (ms)",
        "Retries on failure": "失败重试次数",
        "On failure": "失败策略",
        "Abort the flow": "中止流程",
        "Log and continue": "记录后继续",
        "Skip condition (optional, JS expression)": "跳过条件（可选，JS 表达式）",
        "Save Node": "保存节点",
        "JavaScript code (must define async function run(ctx))": "JavaScript 代码（必须定义 async function run(ctx)）",
        "Python code (context JSON on stdin, result JSON on stdout)":
            "Python 代码（stdin 收 context JSON，stdout 输出结果 JSON）",
        "Shell script (zsh; context JSON on stdin, result JSON on stdout)":
            "Shell 脚本（zsh，stdin 收 context JSON，stdout 输出结果 JSON）",
        "Uses the system python3 (override the path with TIMINGBOMB_PYTHON); stderr goes to node logs; a non-zero exit code fails the node":
            "依赖系统 python3（可用 TIMINGBOMB_PYTHON 指定路径）；stderr 计入节点日志，退出码非 0 即失败",
        "stdin carries the full context JSON (trigger/nodes/loop); stdout must be JSON, otherwise the output falls back to {raw}":
            "stdin 是完整 context JSON（含 trigger/nodes/loop）；stdout 需为 JSON，否则输出回退为 {raw}",
        "tools: log/sleep/fail/http.fetch/exec (allowlisted); the return value is stored as nodes.<id>.output; inside a loop, returning {$loop:\"break\"} stops it":
            "tools：log/sleep/fail/http.fetch/exec（白名单）；返回值写入 nodes.<id>.output；循环内返回 {$loop:\"break\"} 可中断",
        "Code (code)": "代码 (code)",
        "Condition (if)": "条件分支 (if)",
        "Loop (loop)": "循环 (loop)",
        "Built-in action (action)": "内置动作 (action)",
        "Manual approval (approval)": "人工审批 (approval)",
        "Condition (JS expression, e.g. nodes.a.output.x > 0)": "条件（JS 表达式，如 nodes.a.output.x > 0）",
        "Branches": "分支",
        "then: {then} node(s) · else: {else} node(s)": "then：{then} 个节点 · else：{else} 个节点",
        "Loop": "循环",
        "Mode": "模式",
        "Fixed count (count)": "固定次数 (count)",
        "Iterate array (forEach)": "遍历数组 (forEach)",
        "While condition (while)": "条件循环 (while)",
        "condition for the loop to continue": "循环继续的条件",
        "over ({{ template }} / number / JSON array)": "over（模板 {{...}} / 数字 / JSON 数组）",
        "Concurrency (1-32)": "并发数 (1-32)",
        "Max iterations": "最大迭代次数",
        "loop body": "循环体",
        "(empty branch)": "（空分支）",
        "Approval": "审批",
        "Approval message (shown to the approver; say what to check)":
            "审批说明（展示给审批人，说明要检查什么）",
        "The run suspends here until someone approves or rejects it on the Approvals page; approval resumes from this node onward":
            "运行到此处会挂起，等待人在「审批」页同意或拒绝；同意后从本节点继续执行后续节点",
        "Action": "动作",
        "Action type": "动作类型",
        "delay · wait": "delay · 延时",
        "http · request": "http · 请求",
        "shell · command (needs allowlist)": "shell · 命令（需白名单）",
        "appleScript (needs allowlist)": "appleScript（需白名单）",
        "notify · system notification": "notify · 系统通知",
        "openApp · open app": "openApp · 打开应用",
        "clipboard · clipboard": "clipboard · 剪贴板",
        "fileRead · read workspace file": "fileRead · 读工作区文件",
        "fileWrite · write workspace file": "fileWrite · 写工作区文件",
        "params: { command, timeoutMs } · the command must match an allowlist rule (Settings page or tb allow)":
            "params：{ command, timeoutMs } · 命令需命中白名单（设置页或 tb allow 管理）",
        "params: { script } · the script must match an allowlist rule": "params：{ script } · 脚本需命中白名单",
        "params: { name } (app name or bundleId)": "params：{ name }（应用名或 bundleId）",
        "params: { path } · relative to the flow workspace; cannot escape it":
            "params：{ path } · 相对流程工作区，不能越界",
        "params: { path, content } · relative to the flow workspace; cannot escape it":
            "params：{ path, content } · 相对流程工作区，不能越界",
        "Params (JSON, supports {{ templates }})": "参数（JSON，支持 {{ 模板 }}）",
        "action params are not valid JSON": "动作参数不是合法 JSON",

        // MARK: App settings page

        "Run Logging": "运行日志",
        "Record run history (source of the Runs page)": "记录运行历史（执行日志页数据来源）",
        "When off, new runs are not written to history (live results remain visible during the run); existing history is kept and can be deleted on the Runs page":
            "关闭后新的运行不再写入历史（仍可在运行时查看实时结果）；已有历史会保留，可到「执行日志」页删除",
        "Command Allowlist (shell / appleScript)": "命令白名单（shell / appleScript）",
        "No rules yet. shell/appleScript actions are denied until allowlisted.":
            "暂无规则。shell/appleScript 动作在放行前会被拒绝。",
        "New rule, e.g. git * or ls": "新规则，如 git * 或 ls",
        "Add": "添加",
        "Rules: `git status` matches exactly; `git *` matches by prefix; `*` allows everything (be careful)":
            "规则：`git status` 精确匹配；`git *` 前缀匹配；`*` 放行一切（谨慎）",
        "Service": "服务",
        "Start the service when TimingBomb opens": "打开 TimingBomb 时自动启动服务",
        "Stop Service": "停止服务",
        "Start Service": "启动服务",
        "The service runs independently of the window; log {path}": "服务独立于窗口运行；日志 {path}",
        "Checking…": "检测中…",
        "Running (managed by this app)": "运行中（由本应用管理）",
        "Running (external process, e.g. tb serve)": "运行中（外部进程，如 tb serve）",
        "Stopped": "已停止",
        "Appearance": "外观",
        "Theme": "主题",
        "Launch at Login": "开机自启",
        "Start automatically at macOS login": "登录 macOS 时自动启动",
        "Not enabled": "未启用",
        "Enabled · TimingBomb opens and starts the service at login": "已启用 · 登录时自动打开 TimingBomb 并启动服务",
        "Awaiting approval · allow TimingBomb in System Settings → General → Login Items":
            "等待批准 · 请到 系统设置 → 通用 → 登录项 中允许 TimingBomb",
        "App not found; make sure TimingBomb.app was not moved": "未找到应用，请确认 TimingBomb.app 未被移动",
        "Unknown state": "未知状态",
        "Setting failed: {detail}": "设置失败：{detail}",
        "Allow LAN access": "允许 LAN 调用",
        "When on, the API listens on all network interfaces so machines on the LAN can call it (still token-protected); when off, only 127.0.0.1 is accepted":
            "开启后 API 监听所有网卡，局域网内的机器可调用（仍需 Token 鉴权）；关闭后仅接受本机 127.0.0.1",
        "TIMING_BOMB_API_TOKEN is required when TIMING_BOMB_HOST is set":
            "设置 TIMING_BOMB_HOST 时必须同时提供 TIMING_BOMB_API_TOKEN",
        "invalid TIMING_BOMB_HOST: {host}": "TIMING_BOMB_HOST 无效：{host}",
        "lanAccess must be a boolean": "lanAccess 必须为布尔值",
        "Connection": "连接信息",
        "Local API": "本地 API",
        "Data Directory": "数据目录",
        "Open": "打开",
        "(generated after the service starts)": "（启动服务后生成）",
        "Copied": "已复制",
        "Copy": "复制",
        "External trigger example": "外部触发示例",
        "About": "关于",
        "Version": "版本",
        "Open About": "查看关于页",
        "Version {version}": "版本 {version}",
        "Check for Updates": "检查更新",
        "Up to date (v{version})": "已是最新版本（v{version}）",
        "No releases published yet": "还没有发布任何 Release",
        "Latest Release": "最新 Release",
        "Update to {version}": "更新到 {version}",
        "Downloading update…": "正在下载更新…",
        "Installing… the app will relaunch shortly": "正在安装，应用稍后将自动重启…",
        "Update check failed: {detail}": "检查更新失败：{detail}",
        "Update failed: {detail}": "更新失败：{detail}",
        "Open Releases page": "打开 Releases 页面",
        "In-app update requires running from TimingBomb.app": "应用内更新需要从 TimingBomb.app 运行",
        "GitHub API returned 404 — no Release published yet, or a private repository without a logged-in gh CLI":
            "GitHub API 返回 404 —— 可能尚未发布 Release，或私有仓库需要已登录的 gh CLI",
        "Release has no DMG asset": "该 Release 没有 DMG 附件",
        "No .app found in the downloaded image": "下载的镜像中没有找到 .app",
        "gh CLI error (exit {code}): {detail}": "gh CLI 出错（退出码 {code}）：{detail}",
        "Mac task automation orchestration: flows are built from code / if / loop / action nodes.\nNode code runs as JavaScript in the built-in system sandbox (zero environment dependencies).\nSupports external API and manual triggers; a CLI (tb) and Skill package provide a unified AI development surface.":
            "Mac 端自动化任务编排：流程由 code / if / loop / action 节点组成，\n节点代码用 JavaScript 在系统内嵌沙箱执行（零环境依赖）。\n支持外部 API 触发与手动触发，CLI（tb）与 Skill 包供 AI 统一开发。",
        "App Location": "应用位置",
        "Project Source": "项目源码",
        "daemon executable not found (must run from TimingBomb.app)": "未找到 daemon 可执行文件（需要从 TimingBomb.app 内运行）",
        "daemon failed to start: {detail}": "daemon 启动失败：{detail}",

        // MARK: Process support / dry-run log

        "(dry-run) {language} script not executed": "(dry-run) {language} 脚本未执行",

        // MARK: Flow validation

        "flow id must match {pattern} (got '{actual}')": "flow id 必须匹配 {pattern}（当前为 '{actual}'）",
        "flow name is required": "flow 名称必填",
        "schedule trigger requires a cron expression": "定时触发需要 cron 表达式",
        "unknown timezone '{timezone}'": "未知时区 '{timezone}'",
        "misfire must be 'skip' or 'fireOnce' (got '{actual}')": "misfire 必须是 'skip' 或 'fireOnce'（当前为 '{actual}'）",
        "directory does not exist (yet): {path}": "目录（尚）不存在：{path}",
        "fileWatch trigger requires a directory 'path'": "文件监听触发需要目录 'path'",
        "flow has no nodes": "流程没有节点",
        "node id must match {pattern} (got '{actual}')": "节点 id 必须匹配 {pattern}（当前为 '{actual}'）",
        "duplicate node id '{nodeId}'": "节点 id 重复：'{nodeId}'",
        "empty node name": "节点名称为空",
        "retries must be >= 0": "retries 必须 >= 0",
        "timeoutMs must be > 0": "timeoutMs 必须 > 0",
        "unsupported language '{language}' (js | python | shell)": "不支持的语言 '{language}'（js | python | shell）",
        "code node requires 'code'": "代码节点需要 'code'",
        "if node requires 'condition'": "if 节点需要 'condition'",
        "if node has empty 'then' and 'else' branches": "if 节点的 'then' 和 'else' 分支均为空",
        "'over' is ignored in while mode; use 'condition'": "while 模式下忽略 'over'；请使用 'condition'",
        "while loop requires 'condition'": "while 循环需要 'condition'",
        "'over' must be a number, a JSON array or a {{ template }}": "'over' 必须是数字、JSON 数组或 {{ 模板 }}",
        "forEach loop needs an array, not a count": "forEach 循环需要数组，不是次数",
        "{mode} loop requires 'over'": "{mode} 循环需要 'over'",
        "concurrency must be 1...32": "concurrency 必须在 1...32",
        "while loops do not support concurrency > 1": "while 循环不支持 concurrency > 1",
        "loop body is empty": "循环体为空",
        "action node requires 'action'": "动作节点需要 'action'",
        "unknown action '{action}'; available: {available}": "未知动作 '{action}'；可用：{available}",
        "approval node cannot be placed inside a loop body (cannot resume mid-iteration)":
            "审批节点不能放在循环体内（无法在迭代中途恢复）",
        "approval node works better with a 'message' explaining what to check":
            "审批节点最好带 'message' 说明要检查什么",
        "script is empty": "脚本为空",
        "import is not allowed; use ctx.tools only": "不允许 import；只能使用 ctx.tools",
        "require() is not allowed; use ctx.tools only": "不允许 require()；只能使用 ctx.tools",
        "process.* globals do not exist in the sandbox": "沙箱中不存在 process.* 全局对象",
        "internal runner globals are reserved": "内部 runner 全局对象已保留",
        "Java/ObjC bridges are disabled": "Java/ObjC 桥接已禁用",
        "code node must define `async function run(ctx)`": "代码节点必须定义 `async function run(ctx)`",
        "bare fetch() does not exist in the sandbox; use ctx.tools.http.fetch":
            "沙箱中不存在裸 fetch()；请使用 ctx.tools.http.fetch",
        "`while(true)` without any await cannot be preempted; add an await (e.g. ctx.tools.sleep) or it will hang until timeout":
            "不含 await 的 `while(true)` 无法被抢占；请添加 await（如 ctx.tools.sleep），否则会挂起直到超时",

        // MARK: Cron syntax

        "cron expression is empty": "cron 表达式为空",
        "cron expression must have 5 fields (minute hour day-of-month month day-of-week)":
            "cron 表达式必须是 5 段（minute hour day-of-month month day-of-week）",
        "cron field {index} '{field}': {reason}": "cron 第 {index} 段 '{field}'：{reason}",
        "invalid step in '{field}'": "'{field}' 中的步长非法",
        "'{value}' out of range {low}-{high}": "'{value}' 超出范围 {low}-{high}",
        "range end {high} < start {low}": "范围终点 {high} < 起点 {low}",
    ]
}
