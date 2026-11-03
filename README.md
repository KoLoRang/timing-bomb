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
- **Reusable favorite nodes** with editable input/output notes, scripts and
  action configuration. Save a configured node once and copy it into other flows.
- **Four trigger types**: manual, webhook, cron schedule, and recursive file
  watch with debounce. Pause a flow (right-click it in the flow list, or
  `tb flow pause <id>`) to skip its automatic triggers until it is resumed;
  manual runs still work.
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
2. **Check favorites, then generate or edit one Flow JSON**. Use `tb node list`
   and `tb node show <favorite-id>` to inspect suitable configured nodes and
   reuse them. Put repeatable logic in nodes and call a local Agent or CLI only
   where it adds value.
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

## Favorite nodes

Select **Favorite Nodes** in the sidebar to browse saved nodes. Click a node to
view its input/output descriptions and script or action configuration. Save
nodes from their editor or from an existing flow, then add them to another
workflow as independent copies. Conditional and loop nodes include their
children; changing a favorite does not change copies already added to flows.
The app adjusts conflicting IDs and recognized direct references. Check dynamic
indexes, aliases, Python f-string expressions and notes after an ID changes.

Every installation includes the built-in **Desktop notification** favorite
(`builtin-desktop-notification`). It is ready to add to a flow and uses
`trigger.payload.title` and `trigger.payload.message` as its title and body;
you can edit those templates in the favorite detail page. This built-in favorite
cannot be deleted; user-created favorites can. Notifications are sent natively
by TimingBomb.app with its app icon, so keep the app running and allow its macOS
notifications. A real run returns `{notified: true}` when the request is submitted;
this does not confirm that macOS displayed it. A dry-run returns `{dryRun: true}`.

```bash
tb node list --json
tb node show <favorite-id> --node-only > node.json
tb node save --flow <flow-id> --node <node-id> --name "Notification channel"
tb node save --file node.json
tb node rm <favorite-id> # user-created favorites only
```

`--node-only` exports a node object to place in a flow definition. Review unique
IDs and upstream references before validating the new flow. The optional
`inputDescription` and `outputDescription` fields document required inputs and
produced values. The Skill reuses suitable favorites first and suggests saving
general-purpose nodes, such as notification channels, after creating a flow.

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

Install the Skill with the `skills` CLI.

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

Prefer an SSH tunnel to the Mac's loopback service, or an HTTPS reverse proxy.
For HTTPS, configure the client with the proxy URL and load
`TIMING_BOMB_API_TOKEN` from a private environment or secret manager. Do not
put real tokens in commands, scripts, flow definitions, or shared logs.

```bash
export TIMING_BOMB_HOST=https://timingbomb.example.com:443
tb status
tb flow list # verifies authentication; status only checks service health
```

`TIMING_BOMB_HOST` accepts an IP, hostname, `host:port`, or an `http(s)://`
URL. Direct LAN/VPN access requires **Settings → Connection → Allow LAN
access**, which binds all network interfaces. Bearer authentication does not
encrypt traffic. The CLI refuses non-loopback HTTP unless you explicitly set
`TIMINGBOMB_ALLOW_INSECURE_HTTP=1`; use this only for a network you have chosen
to trust, including a VPN/Tailscale connection. Keep LAN access off when using
an SSH tunnel to the loopback service.

## Development and packaging

```bash
swift build
./scripts/make-dmg.sh
```

The DMG script needs Python 3.10+ and installs pinned `dmgbuild` dependencies
into `.build/dmg-venv/` on first use. It detects a compatible Python on PATH;
set `TB_PYTHON=/path/to/python3.12` to choose one explicitly. An older generated
DMG tool environment is recreated automatically. Local test sources are optional; when
they are present, run:

```bash
TIMINGBOMB_INCLUDE_TESTS=1 swift test
```

Release checks use disposable data and an automatically selected loopback
port; they never connect to the installed service:

```bash
./scripts/build-cli.sh --all
python3 scripts/release-smoke.py --daemon dist/app-staging/TimingBomb.app/Contents/MacOS/timingbombd --cli Skills/timingbomb/assets/tb-darwin-arm64
python3 scripts/release-scan.py --source --app dist/app-staging/TimingBomb.app
```

For other manual checks, set `TIMINGBOMB_HOME` to a temporary directory and
`TIMINGBOMB_PORT` to an unused loopback port. Never seed sample flows or test
payloads into the normal data directory. CI verifies source, isolated runtime
behavior, the mounted DMG and the npm archive on pull requests, `main` pushes,
and manual runs. A matching `v<version>` tag publishes only after both package
jobs pass. npm archives must include all six CLI platform binaries; the scanner
rejects unexpected files, recognizable credentials and local build paths.

Useful references:

- [`examples/hello.json`](examples/hello.json) — code, condition, loop, and action nodes.
- [`examples/claude-assist.json`](examples/claude-assist.json) — calling a local Claude Code CLI.
- [`Skills/timingbomb/schemas/flow.schema.json`](Skills/timingbomb/schemas/flow.schema.json) — full Flow schema.

## Data, logs, and uninstall

- Data: `~/Library/Application Support/TimingBomb/`
- Daemon log: `~/Library/Logs/TimingBomb/daemon.log`

The app uses owner-only data directories and files. Run history is enabled by
default; completed runs are retained for 30 days. History and API run views
redact common credential fields and recognizable token patterns. Pending
approvals retain the original execution context in the private database so
they can resume; terminal records are then redacted or removed when history
is off. Existing historical content is not retroactively scrubbed. Protection
uses file permissions, not database encryption; deletion or redaction does not
guarantee immediate physical erasure from SQLite journals, snapshots or backups.

Flow and favorite definitions, their descriptions and exported JSON preserve
what you save. Keep credentials out of these fields and avoid logging secrets
from node code. Redaction is a best-effort safeguard, not a secret vault or a
guarantee against every sensitive value. Review exports and logs before sharing.

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
