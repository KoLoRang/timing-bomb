[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Platform][platform-shield]][platform-url]
[![Swift][swift-shield]][swift-url]

<br />
<div align="center">
  <h3>💣 TimingBomb</h3>

  <p align="center">
    macOS 自动化任务编排 —— 把任务拆成「节点流」，支持定时 / Webhook / 文件变化触发，沙箱 JS 节点可直接调用本机 CLI（如 Claude Code）
    <br />
    <a href="#快速开始"><strong>快速上手 »</strong></a>
    <br />
    <br />
    <a href="#快速开始">快速上手</a>
    ·
    <a href="https://github.com/KoLoRang/timing-bomb/issues">报告 Bug</a>
    ·
    <a href="https://github.com/KoLoRang/timing-bomb/issues">提出需求</a>
  </p>
</div>

<details>
  <summary>目录</summary>
  <ol>
    <li><a href="#关于项目">关于项目</a></li>
    <li>
      <a href="#快速开始">快速开始</a>
      <ul>
        <li><a href="#环境要求">环境要求</a></li>
        <li><a href="#安装">安装</a></li>
        <li><a href="#从源码构建">从源码构建</a></li>
        <li><a href="#卸载">卸载</a></li>
      </ul>
    </li>
  </ol>
</details>

## 关于项目

TimingBomb 是一款运行在 macOS 上的自动化任务编排软件：把任务拆成「节点流」去执行，支持定时、外部 API 调用、文件变化等多种触发方式。节点代码用 JavaScript 在系统内嵌沙箱运行（零环境依赖），也能直接调用本机的 Python / Shell 与系统命令行工具（如 Claude Code）。

<!-- 建议在此处补充一张 App 编排界面截图，例如： -->
<!-- [![产品截图](Resources/screenshot.png)](Resources/screenshot.png) -->

功能特性：

- **可视化编排**：`代码 / 条件分支 / 循环 / 内置动作 / 人工审批` 五种节点，应用内点击节点即可编辑（含 JS 代码编辑器）
- **人工审批**：流程运行到审批节点自动挂起并弹系统通知，在「审批」页同意（断点恢复执行）或拒绝（附备注终止）；待审/历史分栏，支持清除全部历史
- **四种触发方式**：手动、外部 API（webhook）、cron 定时（时区 + 错过策略）、文件监听（目录递归 + 去抖聚合）
- **代码节点多语言**：JavaScript（默认，内嵌沙箱）/ Python / Shell（系统解释器子进程）
- **调用系统 CLI**：JS 中 `ctx.tools.exec("claude -p '...'")` 即可在流程里调用 Claude Code、git 等本机工具并取回结果（白名单 + 增强 PATH）
- **9 种内置动作**：延时 / HTTP / shell / AppleScript（白名单）/ 系统通知 / 打开应用 / 剪贴板 / 工作区文件读写
- **安全**：本地 API 仅绑定 127.0.0.1 + Token；shell/AppleScript 白名单管控；JS 独立子进程执行（死循环可强杀）；支持 dry-run 试跑（无副作用）
- **可观测**：执行日志页展示全流程节点图（含运行状态着色），点击节点分上下两栏查看该节点的输入快照与输出/日志；失败自动系统通知
- **AI 协作**：`tb` CLI + Skill 包，让 AI Agent 按统一规范生成/校验/试跑/上线流程

技术栈：

- [Swift 6](https://www.swift.org/) / Swift Package Manager（多 target：Core / Runner / Daemon / jsrunner / CLI / SwiftUI App）
- [GRDB.swift](https://github.com/groue/GRDB.swift)（SQLite 持久化）
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)（`tb` CLI）
- JavaScriptCore（JS 沙箱）、FSEvents（文件监听）、SwiftUI（菜单栏应用）

<p align="right">（<a href="#目录">回到顶部</a>）</p>

## 快速开始

### 环境要求

- macOS 14+（Apple Silicon，DMG 为 arm64 成品包）
- 从源码构建需要 Xcode 16+ / Swift 6 工具链

### 安装

1. 双击 `dist/TimingBomb-0.1.0-arm64.dmg`，在安装窗口中把左侧 **TimingBomb.app** 拖到右侧 **Applications**，复制完成后推出磁盘镜像。也可以用命令行安装：

   ```bash
   hdiutil attach dist/TimingBomb-0.1.0-arm64.dmg
   cp -R "/Volumes/TimingBomb/TimingBomb.app" /Applications/   # 或你的应用目录
   hdiutil detach /Volumes/TimingBomb
   ```

2. 打开 TimingBomb.app：服务自动启动，右上角菜单栏出现常驻图标；「设置」页可开启**开机自启**（默认关闭）、切换**日间/夜晚/随系统**主题、一键安装 Skill 包
3. 给 AI Agent 安装 Skill（可选，跨平台）：`npm install -g timingbomb` 后，把 `$(npm root -g)/timingbomb` 软链到所用 agent 的 skills 目录——Claude Code `~/.claude/skills`、Codex `~/.codex/skills`、Pi `~/.pi/agent/skills` 等（完整指引见 [Skills/timingbomb/README.md](Skills/timingbomb/README.md)）；同时获得跨平台 Go 版 `tb` CLI，局域网内其它机器可通过 `TIMING_BOMB_HOST` + `TIMING_BOMB_API_TOKEN` 远程调用本机服务（App 设置 → 连接信息 → 开启「允许 LAN 调用」）

数据目录：`~/Library/Application Support/TimingBomb/`（流程定义、运行历史、token）；日志：`~/Library/Logs/TimingBomb/daemon.log`。

### 从源码构建

```bash
swift build             # 编译（Xcode 16+ / Swift 6 工具链）
./scripts/make-dmg.sh   # 打包 DMG → dist/
```

DMG 打包另需 Python 3.10+；首次运行会将固定版本的 `dmgbuild` 依赖安装到 `.build/dmg-venv/`，需要联网。打包会写入 660 × 360 的 Finder 安装窗口、128 点图标、透明曲线箭头和 Applications 链接，无需 Finder 自动化权限。

测试源码仅在本地保留，不随仓库分发。默认构建不注册测试 target，因此从仓库检出后可以直接构建和打包，无需创建 `Tests/` 目录。拥有本地测试源码时，用以下命令显式启用并运行测试：

```bash
TIMINGBOMB_INCLUDE_TESTS=1 swift test
```

### 卸载

1. App 设置页关闭「开机自启」并停止服务，退出 App
2. `rm -rf /Applications/TimingBomb.app /usr/local/bin/tb`
3. 可选清理数据：`rm -rf ~/Library/Application\ Support/TimingBomb ~/Library/Logs/TimingBomb`

<p align="right">（<a href="#目录">回到顶部</a>）</p>

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/KoLoRang/timing-bomb.svg?style=for-the-badge
[contributors-url]: https://github.com/KoLoRang/timing-bomb/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/KoLoRang/timing-bomb.svg?style=for-the-badge
[forks-url]: https://github.com/KoLoRang/timing-bomb/network/members
[stars-shield]: https://img.shields.io/github/stars/KoLoRang/timing-bomb.svg?style=for-the-badge
[stars-url]: https://github.com/KoLoRang/timing-bomb/stargazers
[issues-shield]: https://img.shields.io/github/issues/KoLoRang/timing-bomb.svg?style=for-the-badge
[issues-url]: https://github.com/KoLoRang/timing-bomb/issues
[platform-shield]: https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=for-the-badge
[platform-url]: https://www.apple.com/macos/
[swift-shield]: https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white
[swift-url]: https://www.swift.org/
