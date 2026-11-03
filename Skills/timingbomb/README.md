# TimingBomb

[TimingBomb](https://github.com/KoLoRang/timing-bomb) is a macOS automation
orchestrator: flows are built from `code / if / loop / approval / action`
nodes, node code runs JavaScript in a built-in sandbox, and flows are
triggered manually, by cron schedule, by webhook, or by watching files.

Two pieces are distributed from this repository:

- **The agent skill** — teaches your AI agent (Claude Code, Codex, Pi, Qoder,
  …) how to create, validate, dry-run and ship TimingBomb flows. Installed
  with the `skills` CLI from the GitHub repo.
- **The `tb` CLI** (this npm package) — a cross-platform Go HTTP client for a
  TimingBomb service (macOS / Linux / Windows, amd64 + arm64).

## Install the skill for your agent

```bash
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent <agent> -y
```

Pick your agent — `claude-code`, `codex`, `pi`, `qoder`, `cursor`,
`gemini-cli`, `opencode`, … or `'*'` to install for every agent detected on
this machine:

```bash
# Claude Code
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent claude-code -y

# Codex
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent codex -y

# Pi
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent pi -y

# Qoder
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent qoder -y

# All detected agents
npx skills add KoLoRang/timing-bomb --skill timingbomb --agent '*' -y
```

By default the skill is installed for the current project; add `-g` for a
user-level (global) install. To see what would be installed first:
`npx skills add KoLoRang/timing-bomb --list`.

## Install the tb CLI

```bash
npm install -g timingbomb
```

A postinstall step keeps only your platform's prebuilt binary in `assets/`;
`bin/tb.js` dispatches to it. The CLI talks to the TimingBomb service on the
Mac (locally at `http://127.0.0.1:47632`, or remotely from any machine):

```bash
tb status                                     # service health / version
tb flow list                                  # list flows
tb node list                                  # list reusable favorite nodes
tb node show <favoriteId> --node-only          # export a node for use in another flow
tb flow create --file myflow.json             # create / update a flow
tb flow validate --file myflow.json           # validate without saving
tb flow pause myflow                          # pause automatic triggers; tb flow resume myflow to undo
tb run myflow --input '{"base": 5}' --wait    # trigger and wait for the result
tb runs list --limit 10                       # run history
tb approvals list                             # pending approvals; tb approvals approve <id> to resume
tb allow add "git *"                          # shell allowlist rule
```

## Reuse favorite nodes

Open **Favorite Nodes** in the app to browse saved nodes, then select one to
read its input/output notes and script or action configuration. Nodes can be
favorited from their editor or selected from existing flows. Adding one to
another flow creates an independent copy, including nested children.

New installations include the ready-to-use **Desktop notification** favorite
(`builtin-desktop-notification`). It maps `trigger.payload.title` to the
notification title and `trigger.payload.message` to the body. Reuse it directly
or edit its templates in the app. The built-in favorite cannot be deleted;
user-created favorites can. TimingBomb.app sends native macOS notifications with
its app icon and must be running with notifications allowed. A real run returns
`{notified: true}` for a submitted request, not proof that macOS displayed it;
a dry-run returns `{dryRun: true}`.

```bash
tb node list --json
tb node show <favoriteId>                     # notes, source and full node configuration
tb node show <favoriteId> --node-only > node.json
tb node save --flow myflow --node notify --name "Desktop notification"
tb node save --file node.json --name "Reusable step"
tb node rm <favoriteId>                     # user-created favorites only
```

The Skill checks suitable favorites before creating a flow, verifies their
inputs and dependencies, and reuses them where appropriate. Node JSON supports
optional `inputDescription` and `outputDescription` notes. It also suggests
favoriting useful general-purpose nodes such as notification channels after
creating a flow, without saving them automatically. See [SKILL.md](SKILL.md#favorite-nodes)
for copying rules, including unique IDs and upstream references.

## Remote access and private data

Prefer an SSH tunnel to the Mac's loopback service or an HTTPS reverse proxy.
Load `TIMING_BOMB_API_TOKEN` from a private environment or secret manager;
avoid putting real tokens in shell history or shared files.

```bash
export TIMING_BOMB_HOST=https://timingbomb.example.com:443
tb status
tb flow list # authenticated check
```

Direct LAN/VPN access requires **Allow LAN access** on the hosting Mac and
binds every network interface. Non-loopback HTTP requires the explicit
`TIMINGBOMB_ALLOW_INSECURE_HTTP=1` opt-in, including on Tailscale/VPN; bearer
authentication alone does not encrypt traffic. Choose a trusted network or
use HTTPS instead.

Do not embed secrets in flows, favorite nodes, input/output notes or exports.
Run history is enabled by default, redacts common credentials and retains
completed runs for 30 days. Pending approval contexts stay in the private
database for execution to resume. Redaction is best effort; existing history
is not retroactively scrubbed. Review files before sharing them, and use a
temporary `TIMINGBOMB_HOME` plus an unused `TIMINGBOMB_PORT` for testing.

## License

All rights reserved (no open-source license attached yet — see the GitHub
repository for updates).
