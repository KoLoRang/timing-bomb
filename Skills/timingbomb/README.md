# TimingBomb Skill (npm)

This npm package is the **TimingBomb skill** for AI coding agents: it teaches
your agent (Claude Code, Codex, Pi, …) how to build, validate, dry-run and
ship automation flows on [TimingBomb](https://github.com/KoLoRang/timing-bomb)
— a macOS task orchestrator with `code / if / loop / approval / action` nodes,
sandboxed JavaScript, and manual / cron / webhook / file-watch triggers.

The package also bundles the cross-platform `tb` CLI client (Go, prebuilt for
macOS / Linux / Windows on amd64 + arm64), which the skill — and you — use to
talk to a TimingBomb service.

## 1. Install the package

```bash
npm install -g timingbomb
```

This gives you the `tb` command (a postinstall step prunes `assets/` down to
your platform's single binary), plus the skill folder at
`$(npm root -g)/timingbomb`.

## 2. Link the skill into your agent(s)

Agents discover skills from their own skill directories. Symlink the package
folder there — pick the agents you use (all optional, mix freely):

```bash
SKILL="$(npm root -g)/timingbomb"

# Claude Code
mkdir -p ~/.claude/skills && ln -sfn "$SKILL" ~/.claude/skills/timingbomb

# Codex
mkdir -p ~/.codex/skills && ln -sfn "$SKILL" ~/.codex/skills/timingbomb

# Pi
mkdir -p ~/.pi/agent/skills && ln -sfn "$SKILL" ~/.pi/agent/skills/timingbomb

# Generic agents.md convention (works with any agent that reads ~/.agents/skills)
mkdir -p ~/.agents/skills && ln -sfn "$SKILL" ~/.agents/skills/timingbomb
```

Restart the agent (or start a new session) and the `timingbomb` skill is
available — just ask, e.g. *"create a flow that fetches X every day at 9 and
notifies me"*.

Project-level alternative (only this repo's agent sessions see the skill):

```bash
npm install timingbomb
mkdir -p .claude/skills && ln -sfn "$(pwd)/node_modules/timingbomb" .claude/skills/timingbomb
# same pattern works for .codex/skills, .pi/agent/skills, …
```

On the Mac, the TimingBomb app can also install the skill for you:
Settings → Skill → Install (copies to `~/.agents/skills` and links every
agent directory that already exists).

## 3. The service & remote usage

The TimingBomb service runs on a Mac (the SwiftUI app hosts the daemon).
The `tb` CLI works from any machine:

```bash
tb status                                     # service health / version
tb flow list                                  # list flows
tb flow create --file myflow.json             # create / update a flow
tb flow validate --file myflow.json           # validate without saving
tb run myflow --input '{"base": 5}' --wait    # trigger and wait for the result
tb runs list --limit 10                       # run history
tb allow add "git *"                          # shell allowlist rule
```

From another machine on the LAN, on the hosting Mac enable
Settings → Connection → **Allow LAN access** and copy the **API Token**, then:

```bash
export TIMING_BOMB_HOST=192.168.1.5           # IP / host / host:port / http(s)://…
export TIMING_BOMB_API_TOKEN=<token from that Mac>
tb status
```

Without `TIMING_BOMB_HOST`, `tb` targets `http://127.0.0.1:47632` and reads
the local token file. Full agent guidance lives in `SKILL.md`.

## License

All rights reserved (no open-source license attached yet — see the GitHub
repository for updates).
