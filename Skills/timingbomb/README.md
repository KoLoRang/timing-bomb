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
tb flow create --file myflow.json             # create / update a flow
tb flow validate --file myflow.json           # validate without saving
tb run myflow --input '{"base": 5}' --wait    # trigger and wait for the result
tb runs list --limit 10                       # run history
tb allow add "git *"                          # shell allowlist rule
```

Remote usage — on the hosting Mac enable Settings → Connection → **Allow LAN
access** and copy the **API Token**, then from any machine:

```bash
export TIMING_BOMB_HOST=192.168.1.5           # IP / host / host:port / http(s)://…
export TIMING_BOMB_API_TOKEN=<token from that Mac>
tb status
```

## License

All rights reserved (no open-source license attached yet — see the GitHub
repository for updates).
