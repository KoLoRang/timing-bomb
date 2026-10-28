# TimingBomb — skill package & CLI client

TimingBomb is a macOS automation orchestrator: flows are built from
`code / if / loop / approval / action` nodes, node code runs JavaScript in a
built-in sandbox, and flows are triggered manually, by cron schedule, by
webhook, or by watching files.

This npm package ships:

- **`tb`** — a cross-platform CLI client (Go, prebuilt for macOS / Linux /
  Windows on amd64 + arm64) that talks to a TimingBomb service over its HTTP
  API.
- **The agent skill** (`SKILL.md` + JSON Schema + templates + examples) that
  teaches AI agents how to create, validate, dry-run and ship TimingBomb
  flows.

## Install

```bash
npm install -g timingbomb     # provides the `tb` command
```

The tarball carries prebuilt binaries for every platform; a postinstall step
prunes `assets/` down to your own platform (`tb-darwin-arm64` etc.), so only
one ~6 MB binary stays on disk. (npm ≥ 11 may print an install-scripts
warning — the prune is best-effort and never blocks the install.)

The TimingBomb service itself runs on a Mac (the SwiftUI app hosts the
daemon). This client works from any machine — locally on the Mac, or remotely
from anywhere on the LAN.

## Usage

```bash
tb status                                     # service health / version
tb flow list                                  # list flows
tb flow create --file myflow.json             # create / update a flow
tb flow validate --file myflow.json           # validate without saving
tb run myflow --input '{"base": 5}' --wait    # trigger and wait for the result
tb runs list --limit 10                       # run history
tb allow add "git *"                          # shell allowlist rule
```

### Talking to a remote TimingBomb service

On the Mac hosting TimingBomb: Settings → Connection → enable **Allow LAN
access**, and copy the **API Token**. Then from any machine:

```bash
export TIMING_BOMB_HOST=192.168.1.5           # IP / host / host:port / http(s)://…
export TIMING_BOMB_API_TOKEN=<token from that Mac>
tb status
```

When `TIMING_BOMB_HOST` is unset, `tb` targets `http://127.0.0.1:47632` and
reads the local token file.

## License

All rights reserved (no open-source license attached yet — see the GitHub
repository for updates).
