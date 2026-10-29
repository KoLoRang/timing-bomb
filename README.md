[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Platform][platform-shield]][platform-url]
[![Swift][swift-shield]][swift-url]

**English** · [简体中文](README.zh-CN.md)

<br />
<div align="center">
  <h3>💣 TimingBomb</h3>

  <p align="center">
    macOS automation orchestration — break tasks into node flows, trigger them by schedule / webhook / file changes, and let sandboxed JS nodes call local CLIs (e.g. Claude Code)
    <br />
    <a href="#quick-start"><strong>Get started »</strong></a>
    <br />
    <br />
    <a href="#quick-start">Get started</a>
    ·
    <a href="https://github.com/KoLoRang/timing-bomb/issues">Report a bug</a>
    ·
    <a href="https://github.com/KoLoRang/timing-bomb/issues">Request a feature</a>
  </p>
</div>

<details>
  <summary>Table of contents</summary>
  <ol>
    <li><a href="#about">About</a></li>
    <li>
      <a href="#quick-start">Quick start</a>
      <ul>
        <li><a href="#requirements">Requirements</a></li>
        <li><a href="#install">Install</a></li>
        <li><a href="#build-from-source">Build from source</a></li>
        <li><a href="#uninstall">Uninstall</a></li>
      </ul>
    </li>
  </ol>
</details>

## About

TimingBomb is an automation orchestrator for macOS: tasks are broken into node flows to execute, with manual, external API, cron-schedule, and file-watch triggers. Node code runs JavaScript in a built-in sandbox (zero external dependencies) and can also drive local Python / Shell interpreters and system CLI tools such as Claude Code.

Features:

- **Visual orchestration**: five node types — `code / condition / loop / built-in action / approval` — editable in-app with a click (including a JS code editor)
- **Manual approval**: flows suspend at approval nodes with a system notification; approve (resume from the breakpoint) or reject (terminate with a comment) in the Approvals page; pending/history split with one-click history clearing
- **Four trigger types**: manual, external API (webhook), cron schedule (timezone + misfire policy), file watching (recursive + debounced)
- **Multi-language code nodes**: JavaScript (default, embedded sandbox) / Python / Shell (system interpreters as subprocesses)
- **Call system CLIs**: `ctx.tools.exec("claude -p '...'")` invokes Claude Code, git, or any local tool from a flow and returns the result (allowlist + enriched PATH)
- **9 built-in actions**: delay / HTTP / shell / AppleScript (allowlisted) / system notification / open app / clipboard / workspace file read & write
- **Security**: the local API binds 127.0.0.1 with token auth (LAN exposure opt-in); shell/AppleScript allowlists; JS runs in a separate killable subprocess; dry-run support with no side effects
- **Observability**: the Runs page renders the full node graph with status coloring; click a node to inspect its input snapshot and output/logs; failures trigger system notifications
- **AI collaboration**: `tb` CLI + Skill package let AI agents create, validate, dry-run and ship flows through one standard workflow

Tech stack:

- [Swift 6](https://www.swift.org/) / Swift Package Manager (multi-target: Core / Runner / Daemon / jsrunner / CLI / SwiftUI app)
- [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite persistence)
- Go for the cross-platform `tb` CLI client (see `cli/`, distributed on npm)

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

## Quick start

### Requirements

- macOS 14+ (Apple Silicon; the DMG is an arm64 build)
- Building from source requires the Xcode 16+ / Swift 6 toolchain

### Install

1. Download the latest `TimingBomb-<version>-arm64.dmg` from [Releases](https://github.com/KoLoRang/timing-bomb/releases), open it, and drag **TimingBomb.app** to **Applications**. Or from the terminal:

   ```bash
   hdiutil attach TimingBomb-<version>-arm64.dmg
   cp -R "/Volumes/TimingBomb/TimingBomb.app" /Applications/   # or your applications folder
   hdiutil detach /Volumes/TimingBomb
   ```

   > The CI-built DMG is ad-hoc signed and not notarized, so Gatekeeper warns on first launch. Go to System Settings → Privacy & Security → **Open Anyway**, or strip the quarantine flag: `xattr -dr com.apple.quarantine /Applications/TimingBomb.app`
2. Open TimingBomb.app: the service starts automatically and a menu-bar icon appears. In Settings you can enable **launch at login** (off by default), switch the **light/dark/system** theme and UI language, and manage the API allowlist
3. Install the skill for your AI agent (optional): `npx skills add KoLoRang/timing-bomb --skill timingbomb --agent <agent> -y` — `<agent>` supports `claude-code` / `codex` / `pi` / `qoder` / `cursor` and 70+ more, or `'*'` for every agent detected on this machine (project-level by default, `-g` for global; see [Skills/timingbomb/README.md](Skills/timingbomb/README.md))
4. CLI (optional, cross-platform): `npm install -g timingbomb` installs the Go `tb` CLI (macOS / Linux / Windows). Other machines can call this Mac's service remotely with `TIMING_BOMB_HOST` + `TIMING_BOMB_API_TOKEN` — enable **Allow LAN access** in Settings → Connection first. VPN addresses work too: with LAN access on, the service listens on every interface, so a Tailscale IP (`100.x.y.z`) is the easiest way to reach a Mac behind a home network from a cloud server

Data directory: `~/Library/Application Support/TimingBomb/` (flow definitions, run history, token). Logs: `~/Library/Logs/TimingBomb/daemon.log`.

### Build from source

```bash
swift build             # compile (Xcode 16+ / Swift 6 toolchain)
./scripts/make-dmg.sh   # package the DMG → dist/
```

DMG packaging additionally needs Python 3.10+; the first run installs pinned `dmgbuild` dependencies into `.build/dmg-venv/` and requires network access. Packaging writes a 660 × 360 Finder install window with a 128-point icon and an Applications link — no Finder automation permission needed.

Test sources are kept locally only and are not distributed with the repository. The default build registers no test targets, so a fresh checkout builds and packages directly without creating a `Tests/` directory. With local test sources present, opt in explicitly:

```bash
TIMINGBOMB_INCLUDE_TESTS=1 swift test
```

### Uninstall

1. Disable **launch at login** in the app's Settings, stop the service, and quit the app
2. `rm -rf /Applications/TimingBomb.app`
3. Optional cleanup: `rm -rf ~/Library/Application\ Support/TimingBomb ~/Library/Logs/TimingBomb`; if you installed the CLI via npm: `npm uninstall -g timingbomb`

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

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
