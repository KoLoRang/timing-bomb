[![平台][platform-shield]][platform-url]
[![Swift][swift-shield]][swift-url]
[![Issues][issues-shield]][issues-url]

[English](README.md) · **简体中文**

# TimingBomb

TimingBomb 把重复的 macOS 任务变成可执行的工作流：流程只需编排一次，
本地服务负责触发和执行，AI Agent 只在需要理解、生成或判断时介入。

它采用本地优先的方式运行：TimingBomb App 在 Mac 上承载服务，`tb` CLI
负责控制流程，TimingBomb Skill 为 AI Agent 提供一套短而固定的操作约定。

## 适合什么场景

- 定时任务、Webhook 和文件到达后自动处理。
- 包含条件、循环、重试、延时和人工审批的多步骤流程。
- 调用 Claude Code、Git、Python、Shell、AppleScript 等本机工具。
- 需要重复运行的流水线：Agent 负责首次编排，服务负责后续执行。

## 工作方式

| 组成部分 | 作用 |
| --- | --- |
| **TimingBomb.app + daemon** | 在 macOS 上执行流程，处理触发器、审批、日志和通知。 |
| **Flow JSON** | 保存可执行流程：节点、触发器、输入和执行策略。 |
| **`tb` CLI** | 通过本地或远程 API 校验、保存、运行和查看流程。 |
| **TimingBomb Skill** | 让 AI Agent 按固定流程工作，不必在每次对话中重复加载完整 Schema。 |

把过滤、循环、等待、重试和文件操作等确定性工作放进流程，Agent 只处理
意图、异常和需要人决定的部分。这样可以减少重复上下文和 token 消耗，但
实际节省量取决于任务本身。

## 核心能力

- **可视化流程编辑**：支持 `code`、`if`、`loop`、`action`、`approval` 节点。
- **四种触发方式**：手动、Webhook、Cron 定时、递归文件监听（带去抖）。
- **多种运行时**：JavaScript 内置沙箱，以及通过系统解释器运行的 Python、Shell。
- **本机 CLI 集成**：JavaScript 节点可通过 `ctx.tools.exec(...)` 调用白名单工具，
  例如 `claude` 和 `git`。
- **内置动作**：HTTP、延时、通知、打开应用、剪贴板、AppleScript、Shell、工作区文件。
- **安全控制**：默认仅监听回环地址、Token 鉴权、Shell/AppleScript 白名单、
  可终止的 JS 子进程，以及无副作用的 dry-run。
- **运行可观测**：查看节点状态、输入快照、输出、日志、审批和失败通知。

## 本地 Agent 的固定工作流

Skill 将 Agent 的操作压缩成一条稳定流程：

1. **检测服务**：执行 `tb status`。默认使用本机；远程 Mac 才设置
   `TIMING_BOMB_HOST` 和 `TIMING_BOMB_API_TOKEN`。
2. **生成或修改一个 Flow JSON**：把可重复逻辑写进节点，只在确实需要时调用
   本地 Agent 或 CLI。
3. **先校验，不保存错误定义**：

   ```bash
   tb flow validate --file flow.json
   ```

4. **保存流程定义**。对于 `manual` 流程，保存只写入定义；`schedule` 或
   `fileWatch` 流程保存后就会进入对应触发器的执行范围，因此验证阶段应先使用
   `manual`：

   ```bash
   tb flow create --file flow.json
   ```

5. **先 dry-run，再检查，最后正式运行**：

   ```bash
   tb run <flow-id> --dry-run --wait
   tb run <flow-id> --wait
   ```

完整节点 Schema、命令字典和 Agent 约定见
[`Skills/timingbomb/SKILL.md`](Skills/timingbomb/SKILL.md)，精简安装说明见
[`Skills/timingbomb/README.md`](Skills/timingbomb/README.md)。

## 快速开始

### 环境要求

- macOS 14+：运行 TimingBomb App 和服务。
- Apple Silicon：适用于发布的 arm64 DMG。
- Node.js 16+：安装 npm 分发的 `tb` CLI。
- Xcode 16+ / Swift 6：从源码构建时需要。

### 1. 安装 macOS App

从 [Releases](https://github.com/KoLoRang/timing-bomb/releases) 下载最新的
`TimingBomb-<version>-arm64.dmg`，打开后将 **TimingBomb.app** 拖到
**Applications**。打开 App 后服务会自动启动。

CI 生成的 DMG 采用 ad-hoc 签名且未公证。首次启动被 Gatekeeper 拦截时，前往
**系统设置 → 隐私与安全性 → 仍要打开**，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/TimingBomb.app
```

### 2. 安装 `tb` CLI

CLI 是跨平台客户端，TimingBomb 服务本身运行在 macOS 上：

```bash
npm install -g timingbomb
tb status
```

在 Agent 创建或运行流程前，`tb status` 应能显示 daemon 正在运行。

### 3. 为 Agent 安装 Skill

本项目使用 `skills` CLI 安装 Skill。如果你把它称为“skilld”，实际命令仍然是
`npx skills ...`；仓库中没有单独的 `skilld install` 命令。

只给当前项目安装时，不加 `-g`：

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent codex -y
```

希望在多个项目中都能使用时，加 `-g` 做用户级全局安装：

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent codex -g -y
```

将 `codex` 替换为 `claude-code`、`pi`、`qoder`、`cursor` 或其他受支持的 Agent。
给所有受支持的 Agent 安装时，对通配符加引号：

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent '*' -g -y
```

先预览安装内容：

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --list
```

### 4. 运行内置示例

以下命令请在仓库根目录执行（如果只安装了 App，请先从仓库下载示例文件）。
该示例是手动触发，不会自行启动：

```bash
tb flow validate --file examples/hello.json
tb flow create --file examples/hello.json
tb run hello --input '{"base":5}' --dry-run --wait
tb run hello --input '{"base":5}' --wait
```

dry-run 会跳过外部调用和写入，但仍会检查运行到的命令是否通过白名单，适合检查
流程结构；它不能证明外部服务、本地 Agent 或真实命令一定会返回某个结果。

## 远程执行

在承载 TimingBomb 的 Mac 上打开 **设置 → 连接信息**，开启 **允许 LAN 调用**
并复制 API Token，然后在客户端机器上设置：

```bash
export TIMING_BOMB_HOST=192.168.1.5
export TIMING_BOMB_API_TOKEN='粘贴主机 Mac 上的 token'
tb status
```

`TIMING_BOMB_HOST` 支持 IP、主机名、`host:port` 或 `http(s)://` URL。两台机器
可以互相访问时，也可以使用 Tailscale/VPN 地址。

## 开发与打包

```bash
swift build
./scripts/make-dmg.sh
```

DMG 脚本需要 Python 3.10+；首次运行会把固定版本的 `dmgbuild` 依赖安装到
`.build/dmg-venv/`。测试源码是可选的；本地存在测试源码时运行：

```bash
TIMINGBOMB_INCLUDE_TESTS=1 swift test
```

参考文件：

- [`examples/hello.json`](examples/hello.json) — code、condition、loop、action 综合示例。
- [`examples/claude-assist.json`](examples/claude-assist.json) — 调用本地 Claude Code CLI。
- [`Skills/timingbomb/schemas/flow.schema.json`](Skills/timingbomb/schemas/flow.schema.json) — 完整 Flow Schema。

## 数据、日志与卸载

- 数据目录：`~/Library/Application Support/TimingBomb/`
- daemon 日志：`~/Library/Logs/TimingBomb/daemon.log`

卸载前先在设置中关闭开机自启，停止服务并退出 App，再删除应用。需要时一并
清理数据和日志；npm CLI 用 `npm uninstall -g timingbomb` 删除。

```bash
rm -rf /Applications/TimingBomb.app
rm -rf ~/Library/Application\ Support/TimingBomb ~/Library/Logs/TimingBomb
npm uninstall -g timingbomb
```

## 许可证

仓库目前尚未附带开源许可证，后续信息请以 GitHub 仓库为准。

<!-- MARKDOWN LINKS & IMAGES -->
[issues-shield]: https://img.shields.io/github/issues/KoLoRang/timing-bomb.svg?style=for-the-badge
[issues-url]: https://github.com/KoLoRang/timing-bomb/issues
[platform-shield]: https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=for-the-badge
[platform-url]: https://www.apple.com/macos/
[swift-shield]: https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white
[swift-url]: https://www.swift.org/
