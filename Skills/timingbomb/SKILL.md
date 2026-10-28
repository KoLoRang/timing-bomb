---
name: timingbomb
description: 使用 TimingBomb（Mac 自动化任务编排）创建、校验、触发和管理任务流。当用户要求"定时任务/自动化流程/任务编排/轮询监控/数据处理流水线"或提到 tb 命令时使用。
---

# TimingBomb Skill

TimingBomb 是运行在用户 Mac 上的任务编排服务：流程（flow）由节点组成，节点代码用 JavaScript 在系统内嵌沙箱中执行（无任何外部依赖）。本 skill 通过 `tb` CLI 与 daemon 交互完成流程的开发、校验与运行。

## 使用前提

- daemon 必须在运行（`tb status` 检查；未运行时提示用户执行 `tb serve`）
- CLI 路径：仓库构建产物 `.build/debug/tb`（或用户已安装到 PATH 的 `tb`）

## 命令字典

```bash
tb status                                     # daemon 健康/版本
tb flow list [--json]                         # 列出流程
tb flow show <flowId> [--json]                # 查看流程定义
tb flow create --file <flow.json>             # 创建/更新流程（也支持 stdin）
tb flow validate --file <flow.json>           # 仅校验，不保存（每次交付前必须通过）
tb flow rm <flowId>                           # 删除流程
tb run <flowId> --input '<json>' --wait       # 触发运行并等待结果
tb run <flowId> --dry-run --wait              # 试跑：tools/动作不产生真实副作用
tb runs list [--flowId <id>] [--limit 20]     # 运行历史
tb runs show <runId>                          # 节点时间线/日志/最终上下文
tb runs cancel <runId>                        # 取消运行
tb allow list|add "<pattern>"|rm "<pattern>"  # shell/appleScript 白名单
```

## AI 标准工作流

1. 根据用户需求生成 flow JSON（结构见下）+ 各 code 节点的 JS 代码；
2. `tb flow validate` 必须零 error；
3. `tb run <flowId> --input '<示例 payload>' --dry-run --wait` 试跑（无副作用；shell 未授权会在试跑即报错）；
4. 真实运行 `tb run --wait` 验证输出符合预期；
5. 向用户报告结果，等确认后再 `tb flow create` 落盘（如需 shell 权限，提示用户执行 `tb allow add`）。

## Flow JSON 结构

```jsonc
{
  "id": "kebab-or-dash-id",          // [A-Za-z0-9._-]，全局唯一
  "name": "人类可读名称",
  "version": 1,
  "description": "可选说明",
  "trigger": {                        // 可选；M1 默认手动/webhook 触发
    "type": "schedule",               // manual | schedule | webhook
    "cron": "0 9 * * 1-5",            // 5 段 cron，schedule 时必填
    "timezone": "Asia/Shanghai",
    "misfire": "skip"                 // skip | fireOnce
  },
  "nodes": [ /* 节点数组，见下 */ ]
}
```

节点通用字段：`id`（全局唯一）、`type`、`name`、`timeoutMs`、`onError`（`abort`|`continue`，默认 abort）、`retries`、`skipIf`（条件表达式，false 时跳过）。

### code 节点 —— `{"id": "...", "type": "code", "language": "js|python|shell", "code": "<源码>"}`

**语言**（`language` 可省略，默认 js）：

- `js`：内嵌 JSCore 沙箱（零依赖）。必须且只能定义 `async function run(ctx)`；禁止 `import`/`require`。
- `python`：系统 python3 子进程（可用 env `TIMINGBOMB_PYTHON` 指定路径）。协议：**stdin 收完整 context JSON，stdout 输出结果 JSON**（非 JSON 则回退 `{raw}`），stderr 计入日志，退出码非 0 即失败。
- `shell`：zsh 子进程，同上协议（`CTX=$(cat)` 取 context，`echo '{...}'` 输出结果）。

JS 契约：

- 只能通过 `ctx` 与外界交互：
  - `ctx.trigger.payload` —— 触发时注入的输入
  - `ctx.nodes.<nodeId>.output` —— 上游节点输出
  - `ctx.loop.item` / `ctx.loop.index` —— 循环体内可用
  - `ctx.config.flowId` / `ctx.config.runId`
  - `ctx.get("a.b.0.c")` —— 深路径取值（缺失返回 null）
  - `ctx.tools.log(...)`、`ctx.tools.sleep(ms)`、`ctx.tools.fail(msg)`
  - `ctx.tools.http.fetch(url, opts)`（返回 `{status, ok, headers, body, json()}`）
  - `ctx.tools.exec(command, {timeoutMs})` —— **调用系统命令**（白名单校验；返回 `{exitCode, stdout, stderr}`）。PATH 已增强（含 `~/.local/bin`、`/opt/homebrew/bin` 等），可直接调 `claude`、`git` 等。例如调 Claude Code：`const r = await ctx.tools.exec("claude -p \"...\" --output-format json")`
  - `console.log(...)` 等价于 `ctx.tools.log`
- 返回值写入 `ctx.nodes.<本节点id>.output`（任意 JSON 值）；
- 循环体内返回 `{ "$loop": "break" }` 或 `{ "$loop": "continue" }` 控制循环。

### if 节点

```jsonc
{ "id": "check", "type": "if", "condition": "nodes.a.output.count > 3",
  "then": [ /* 子节点 */ ], "else": [ /* 子节点 */ ] }
```
`condition` 是 JS 表达式（作用域即 ctx，如 `nodes.a.output.x === 1`）；也可写含 `return` 的函数体。多条件用 `&&`/`||`。

### approval 节点 —— `{"id": "...", "type": "approval", "message": "金额 {{nodes.a.output.amount}} 元，请确认"}`

运行到此节点会**挂起**（run 状态 awaitingApproval），在 App「审批」页或 API 处理：
- 同意 → 从该节点之后继续执行（上下文/时间线延续，同一 runId）
- 拒绝（可附备注）→ run 失败终止
- `message` 支持 `{{ 模板 }}`；**不允许放在循环体内**（校验器会报错）；if 分支内可用

API：`GET /approvals`；`POST /approvals/<id>/approve|reject`（body 可带 `{"comment": "..."}`）；`DELETE /approvals`（清除全部已决历史，待审保留）

### loop 节点

```jsonc
{ "id": "each", "type": "loop", "mode": "forEach",
  "over": "{{nodes.a.output.items}}",   // 模板取数组；count 模式取数字（或字面量 "5" / "[1,2]"）
  "concurrency": 1, "maxIterations": 1000,
  "body": [ /* 子节点，可用 ctx.loop.item / ctx.loop.index */ ] }
```
`mode`: `count`（N 次）| `forEach`（遍历数组）| `while`（用 `condition` 替代 `over`，配合 `{ $loop: "break" }` 使用）。

### action 节点（内置动作，无需写代码）

- `delay`：`{"ms": 500}`
- `http`：`{"method": "POST", "url": "...", "headers": {}, "body": {}, "timeoutMs": 10000}` → `{status, ok, headers, body}`
- `shell`：`{"command": "git status", "timeoutMs": 30000}` → `{exitCode, stdout, stderr}`（**需白名单**：`tb allow add "git *"`）
- `appleScript`：`{"script": "display notification \"hi\""}`（需白名单）
- `notify`：`{"title": "...", "body": "..."}`（系统通知）
- `openApp`：`{"name": "Safari"}`
- `clipboard`：`{"op": "read"}` 或 `{"op": "write", "text": "..."}`
- `fileRead` / `fileWrite`：`{"path": "out/a.txt"}` / `{"path": "out/a.txt", "content": "..."}` —— 路径相对流程工作区（`~/Library/Application Support/TimingBomb/workspaces/<flowId>/`），禁止 `..` 与绝对路径

params 中的字符串支持 `{{ 模板 }}` 引用上下文。

### 触发方式（trigger.type）

- `manual`：手动（默认）
- `webhook`：外部 API（`POST /hooks/<flowId>` + Bearer Token）
- `schedule`：`{"cron": "0 9 * * 1-5", "timezone": "Asia/Shanghai", "misfire": "skip|fireOnce"}`（迟到 >5 分钟默认跳过）
- `fileWatch`：`{"path": "~/Downloads/inbox"}` —— 目录递归监听（FSEvents），去抖 2.5s 聚合，payload 注入 `{events: [{path, event}]}`

## 模板语法

任何字符串配置（如 `over`、action params）中：`{{ path.to.value }}` 会被上下文值替换；整串恰为一个模板时保留原始类型（对象/数组/数字）。

## 校验要点（validate 会检查）

- 所有节点 id 全局唯一且匹配 `[A-Za-z0-9._-]+`
- code 必须定义 `async function run(ctx)`，且不含 import/require
- forEach 的 `over` 必须解析为数组；while 必须有 `condition`；action 必须是已知动作
- cron 必须是合法 5 段表达式

## 参考文件

- `schemas/flow.schema.json` —— flow JSON 的完整 Schema
- `templates/code-node.js` —— 代码节点模板
- `examples/hello-flow.json` —— 完整示例（code + if + loop + action 组合）
