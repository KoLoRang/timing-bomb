[![Platform][platform-shield]][platform-url]
[![Swift][swift-shield]][swift-url]
[![Issues][issues-shield]][issues-url]

**English** · [简体中文](README.zh-CN.md)

# TimingBomb

TimingBomb turns repeatable Mac tasks into executable workflows. Build a flow
once, let the local service handle triggers and execution, and use an AI Agent
only when the task needs reasoning, generation, or a decision.

It is designed for local-first automation: the TimingBomb app runs the work on
your Mac, the `tb` CLI controls it, and the TimingBomb Skill gives AI Agents a
small, repeatable operating contract.

## What it is good for

- Scheduled jobs, webhooks, and file-arrival automations.
- Multi-step work with conditions, loops, retries, delays, and approvals.
- Local tools such as Claude Code, Git, Python, Shell, and AppleScript.
- Repeatable pipelines where the Agent should prepare the workflow once and
  the service should run it many times.

## How it works

| Part | Responsibility |
| --- | --- |
| **TimingBomb.app + daemon** | Runs flows on macOS, handles triggers, approvals, logs, and notifications. |
| **Flow JSON** | Stores the executable workflow: nodes, triggers, inputs, and policies. |
| **`tb` CLI** | Validates, saves, runs, and inspects flows through the local or remote API. |
| **TimingBomb Skill** | Teaches an AI Agent the standard workflow without requiring the full schema in every conversation. |

The service keeps deterministic work—filters, loops, waits, retries, and file
operations—inside the flow. The Agent can then focus on intent, exceptions,
and human decisions instead of replaying the same plan on every run. This is a
practical way to reduce repeated context and token usage without making a
fixed saving claim.

## Core capabilities

- **Visual flow editor** with `code`, `if`, `loop`, `action`, and `approval`
  nodes.
- **Four trigger types**: manual, webhook, cron schedule, and recursive file
  watch with debounce.
- **Multiple runtimes**: JavaScript in a built-in sandbox, plus Python and
  Shell through system interpreters.
- **Local CLI integration**: JavaScript nodes can call allowlisted tools such
  as `claude` and `git` through `ctx.tools.exec(...)`.
- **Built-in actions** for HTTP, delays, notifications, apps, clipboard,
  AppleScript, Shell, and workspace files.
- **Safety controls**: loopback binding by default, token authentication,
  shell/AppleScript allowlists, killable JS execution, and dry-run support.
- **Run inspection**: node status, input snapshots, outputs, logs, approvals,
  and failure notifications.

## Fixed workflow for local Agents

The Skill keeps Agent interactions short and predictable:

1. **Detect the service** with `tb status`. Use local mode by default; use
   `TIMING_BOMB_HOST` and `TIMING_BOMB_API_TOKEN` only for a remote Mac.
2. **Generate or edit one Flow JSON** from the user's request. Put repeatable
   logic in nodes and call a local Agent or CLI only where it adds value.
3. **Validate** the definition before saving:

   ```bash
   tb flow validate --file flow.json
   ```

4. **Save the definition**. For a `manual` flow, saving only stores the
   definition. A saved `schedule` or `fileWatch` flow becomes eligible for its
   trigger, so use `manual` while validating:

   ```bash
   tb flow create --file flow.json
   ```

5. **Dry-run, inspect, then run for real**:

   ```bash
   tb run <flow-id> --dry-run --wait
   tb run <flow-id> --wait
   ```

The full node schema, command dictionary, and Agent contract live in
[`Skills/timingbomb/SKILL.md`](Skills/timingbomb/SKILL.md). The compact Skill
README is at [`Skills/timingbomb/README.md`](Skills/timingbomb/README.md).

## Quick start

### Requirements

- macOS 14 or later for the TimingBomb app and service.
- Apple Silicon for the published arm64 DMG.
- Node.js 16+ for the npm-distributed `tb` CLI.
- Xcode 16+ and Swift 6 when building from source.

### 1. Install the macOS app

Download the latest `TimingBomb-<version>-arm64.dmg` from
[Releases](https://github.com/KoLoRang/timing-bomb/releases), open it, and drag
**TimingBomb.app** to **Applications**. The service starts when the app opens.

The CI DMG is ad-hoc signed and not notarized. If Gatekeeper blocks the first
launch, use **System Settings → Privacy & Security → Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/TimingBomb.app
```

### 2. Install the `tb` CLI

The CLI is a cross-platform client; the service itself runs on macOS.

```bash
npm install -g timingbomb
tb status
```

`tb status` should report a running daemon before an Agent creates or runs a
flow.

### 3. Install the Skill for an Agent

This repository uses the `skills` CLI for Skill installation. If you call it
“skilld”, the actual command is still `npx skills ...`; there is no separate
`skilld install` command in this repository.

For the current project, omit `-g`:

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent codex -y
```

For a user-level install that can be used across projects, add `-g`:

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent codex -g -y
```

Replace `codex` with `claude-code`, `pi`, `qoder`, `cursor`, or another
supported Agent. To install for all supported Agents, quote the wildcard:

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent '*' -g -y
```

Preview the installation first with:

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --list
```

### 4. Run the included example

Run these commands from the repository root (or download the example file
from the repository first). The example is manual, so it will not start by
itself:

```bash
tb flow validate --file examples/hello.json
tb flow create --file examples/hello.json
tb run hello --input '{"base":5}' --dry-run --wait
tb run hello --input '{"base":5}' --wait
```

Dry-run skips external calls and writes, while still checking allowlists for
commands reached by the run. It is useful for checking flow structure, but it
does not prove that an external service, local Agent, or real command will
return a particular result.

## Remote execution

On the Mac that hosts TimingBomb, open **Settings → Connection**, enable
**Allow LAN access**, and copy the API token. Then configure the client machine:

```bash
export TIMING_BOMB_HOST=192.168.1.5
export TIMING_BOMB_API_TOKEN='paste-token-from-the-host-Mac-here'
tb status
```

`TIMING_BOMB_HOST` accepts an IP, hostname, `host:port`, or an `http(s)://`
URL. A Tailscale/VPN address works when both machines can reach the service.

## Development and packaging

```bash
swift build
./scripts/make-dmg.sh
```

The DMG script needs Python 3.10+ and installs pinned `dmgbuild` dependencies
into `.build/dmg-venv/` on first use. Local test sources are optional; when
they are present, run:

```bash
TIMINGBOMB_INCLUDE_TESTS=1 swift test
```

Useful references:

- [`examples/hello.json`](examples/hello.json) — code, condition, loop, and action nodes.
- [`examples/claude-assist.json`](examples/claude-assist.json) — calling a local Claude Code CLI.
- [`Skills/timingbomb/schemas/flow.schema.json`](Skills/timingbomb/schemas/flow.schema.json) — full Flow schema.

## Data, logs, and uninstall

- Data: `~/Library/Application Support/TimingBomb/`
- Daemon log: `~/Library/Logs/TimingBomb/daemon.log`

To uninstall, disable launch at login, stop and quit the app, then remove the
application. Optional cleanup removes the data and logs; remove the CLI with
`npm uninstall -g timingbomb`.

```bash
rm -rf /Applications/TimingBomb.app
rm -rf ~/Library/Application\ Support/TimingBomb ~/Library/Logs/TimingBomb
npm uninstall -g timingbomb
```

## License

No open-source license is attached to the repository yet. See the GitHub
repository for updates.

<!-- MARKDOWN LINKS & IMAGES -->
[issues-shield]: https://img.shields.io/github/issues/KoLoRang/timing-bomb.svg?style=for-the-badge
[issues-url]: https://github.com/KoLoRang/timing-bomb/issues
[platform-shield]: https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=for-the-badge
[platform-url]: https://www.apple.com/macos/
[swift-shield]: https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white
[swift-url]: https://www.swift.org/
