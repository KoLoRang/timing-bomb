---
name: timingbomb
description: Create, validate, trigger and manage TimingBomb automation flows (Mac task orchestration). Use when the user asks for "scheduled tasks / automation flows / task orchestration / polling monitors / data pipelines" or mentions the tb command.
---

# TimingBomb Skill

TimingBomb is a task-orchestration service that runs on a Mac (usually the local machine; it can also run on another Mac on the LAN — see "Prerequisites & environment detection" below). Flows are composed of nodes; node code runs JavaScript inside a built-in sandbox with zero external dependencies. This skill drives the service through the `tb` CLI.

## Prerequisites & environment detection

- Install the CLI: `npm install -g timingbomb` (provides `tb`).
- The TimingBomb service must be running. **Before doing anything, decide whether you are in a local or a remote environment** (see below).

### Step 1 — detect local vs. remote

1. Assume **local** by default: run `tb status`.
   - Prints `daemon: running (…)` → local mode; use the command dictionary as-is.
   - Connection fails → ask the user to start TimingBomb on this machine (open the TimingBomb app).
2. Switch to **remote** mode when either of these signals appears:
   - The user explicitly mentions "the other Mac / remote / the TimingBomb on my other machine", or gives you an IP/host;
   - Local `tb status` fails but the user still wants TimingBomb work → confirm with the user whether the service is remote.

### Step 2 — remote only: configure the connection

In remote mode every `tb` invocation needs two environment variables (the token comes from the **remote Mac**):

```bash
TIMING_BOMB_HOST=192.168.1.5 TIMING_BOMB_API_TOKEN=<remote token> tb status
# or export them once for the session
export TIMING_BOMB_HOST=192.168.1.5      # IP / hostname / host:port / http://… ; port defaults to 47632
export TIMING_BOMB_API_TOKEN=<remote token>
```

Guide the user through two steps **on the remote Mac**:

1. TimingBomb app → Settings → Connection → turn on **Allow LAN access** (off by default; when off the service only listens on 127.0.0.1 and is unreachable from the network);
2. On the same page, copy the **API Token** (or run `tb auth token` on that machine).

Verify: `tb status` with the variables set should print `daemon: running (…) — http://<host>:<port>`.

Gotchas: setting only `TIMING_BOMB_HOST` without `TIMING_BOMB_API_TOKEN` fails immediately; a wrong token still passes `tb status` (health is unauthenticated) but business commands (flow/run/…) return 401 — trust the business commands.

Note: `tb serve` does not exist in this client. The service always runs inside the TimingBomb Mac app (or from the Swift sources on that Mac).

## Command dictionary

Local mode uses these directly; remote mode prefixes each command with `TIMING_BOMB_HOST=… TIMING_BOMB_API_TOKEN=…` (see above).

```bash
tb status                                     # daemon health / version
tb flow list [--json]                         # list flows
tb flow show <flowId> [--json]                # inspect a flow definition
tb flow create --file <flow.json>             # create/update a flow (stdin also works)
tb flow validate --file <flow.json>           # validate only, no save (must pass before every delivery)
tb flow rm <flowId>                           # delete a flow
tb run <flowId> --input '<json>' --wait       # trigger a run and wait for the result
tb run <flowId> --dry-run --wait              # dry-run: tools/actions cause no real side effects
tb runs list [--flowId <id>] [--limit 20]     # run history
tb runs show <runId>                          # node timeline / logs / final context
tb runs cancel <runId>                        # cancel a run
tb allow list|add "<pattern>"|rm "<pattern>"  # shell/appleScript allowlist
tb logging on|off|status                      # run-history logging toggle
```

## Standard agent workflow

0. At the start of a session, detect local/remote mode per "Prerequisites & environment detection" (for remote, configure `TIMING_BOMB_HOST` / `TIMING_BOMB_API_TOKEN` and verify with `tb status`);
1. Generate the flow JSON from the user's request (structure below) plus the JS code for each `code` node;
2. `tb flow validate` must report zero errors;
3. Dry-run: `tb run <flowId> --input '<sample payload>' --dry-run --wait` (no side effects; unauthorized shell commands fail right here);
4. Real run `tb run --wait` and check the output matches expectations;
5. Report to the user; save with `tb flow create` only after confirmation (if shell access is needed, prompt the user to run `tb allow add`).

## Flow JSON structure

```jsonc
{
  "id": "kebab-or-dash-id",          // [A-Za-z0-9._-], globally unique
  "name": "Human-readable name",
  "version": 1,
  "description": "Optional notes",
  "trigger": {                        // optional; defaults to manual/webhook
    "type": "schedule",               // manual | schedule | webhook | fileWatch
    "cron": "0 9 * * 1-5",            // 5-field cron, required for schedule
    "timezone": "Asia/Shanghai",
    "misfire": "skip"                 // skip | fireOnce
  },
  "nodes": [ /* node array, see below */ ]
}
```

Common node fields: `id` (globally unique), `type`, `name`, `timeoutMs`, `onError` (`abort`|`continue`, default abort), `retries`, `skipIf` (condition expression, skip when false).

### code node — `{"id": "...", "type": "code", "language": "js|python|shell", "code": "<source>"}`

**Languages** (`language` optional, defaults to js):

- `js`: embedded JSCore sandbox (zero dependencies). Must define exactly one `async function run(ctx)`; `import`/`require` are forbidden.
- `python`: system python3 subprocess (path overridable via env `TIMINGBOMB_PYTHON`). Protocol: **full context JSON on stdin, result JSON on stdout** (non-JSON falls back to `{raw}`), stderr goes to logs, non-zero exit fails the node.
- `shell`: zsh subprocess, same protocol (`CTX=$(cat)` reads the context, `echo '{...}'` emits the result).

JS contract:

- Interact with the world only through `ctx`:
  - `ctx.trigger.payload` — input injected at trigger time
  - `ctx.nodes.<nodeId>.output` — upstream node outputs
  - `ctx.loop.item` / `ctx.loop.index` — available inside loop bodies
  - `ctx.config.flowId` / `ctx.config.runId`
  - `ctx.get("a.b.0.c")` — deep-path lookup (null when missing)
  - `ctx.tools.log(...)`, `ctx.tools.sleep(ms)`, `ctx.tools.fail(msg)`
  - `ctx.tools.http.fetch(url, opts)` (returns `{status, ok, headers, body, json()}`)
  - `ctx.tools.exec(command, {timeoutMs})` — **run system commands** (allowlist-checked; returns `{exitCode, stdout, stderr}`). PATH is enriched (includes `~/.local/bin`, `/opt/homebrew/bin`, …), so `claude`, `git` etc. work directly. Example calling Claude Code: `const r = await ctx.tools.exec("claude -p \"...\" --output-format json")`
  - `console.log(...)` is equivalent to `ctx.tools.log`
- The return value lands in `ctx.nodes.<this node's id>.output` (any JSON value);
- Inside loops return `{ "$loop": "break" }` or `{ "$loop": "continue" }` to control iteration.

### if node

```jsonc
{ "id": "check", "type": "if", "condition": "nodes.a.output.count > 3",
  "then": [ /* child nodes */ ], "else": [ /* child nodes */ ] }
```
`condition` is a JS expression (scope is ctx, e.g. `nodes.a.output.x === 1`); a function body with `return` also works. Combine with `&&`/`||`.

### approval node — `{"id": "...", "type": "approval", "message": "Amount {{nodes.a.output.amount}} — please confirm"}`

Execution **suspends** at this node (run status awaitingApproval) until handled in the app's Approvals page or via API:

- Approve → execution resumes after the node (context/timeline preserved, same runId)
- Reject (optional comment) → the run fails and stops
- `message` supports `{{ templates }}`; **not allowed inside loop bodies** (the validator rejects it); fine inside if-branches

API: `GET /approvals`; `POST /approvals/<id>/approve|reject` (body may carry `{"comment": "..."}`); `DELETE /approvals` (clears decided history, keeps pending).

### loop node

```jsonc
{ "id": "each", "type": "loop", "mode": "forEach",
  "over": "{{nodes.a.output.items}}",   // template resolving to an array; count mode takes a number (or literals "5" / "[1,2]")
  "concurrency": 1, "maxIterations": 1000,
  "body": [ /* child nodes; use ctx.loop.item / ctx.loop.index */ ] }
```
`mode`: `count` (N iterations) | `forEach` (iterate array) | `while` (uses `condition` instead of `over`, combine with `{ $loop: "break" }`).

### action nodes (built-in, no code)

- `delay`: `{"ms": 500}`
- `http`: `{"method": "POST", "url": "...", "headers": {}, "body": {}, "timeoutMs": 10000}` → `{status, ok, headers, body}`
- `shell`: `{"command": "git status", "timeoutMs": 30000}` → `{exitCode, stdout, stderr}` (**allowlist required**: `tb allow add "git *"`)
- `appleScript`: `{"script": "display notification \"hi\""}` (allowlist required)
- `notify`: `{"title": "...", "body": "..."}` (system notification)
- `openApp`: `{"name": "Safari"}`
- `clipboard`: `{"op": "read"}` or `{"op": "write", "text": "..."}`
- `fileRead` / `fileWrite`: `{"path": "out/a.txt"}` / `{"path": "out/a.txt", "content": "..."}` — paths are relative to the flow workspace (`~/Library/Application Support/TimingBomb/workspaces/<flowId>/`); `..` and absolute paths are rejected

Strings inside params support `{{ templates }}` referencing the context.

### Triggers (trigger.type)

- `manual`: by hand (default)
- `webhook`: external API (`POST /hooks/<flowId>` + Bearer token)
- `schedule`: `{"cron": "0 9 * * 1-5", "timezone": "Asia/Shanghai", "misfire": "skip|fireOnce"}` (late fire > 5 minutes is skipped by default)
- `fileWatch`: `{"path": "~/Downloads/inbox"}` — recursive directory watching (FSEvents), 2.5s debounce, payload injects `{events: [{path, event}]}`

## Template syntax

In any string config (e.g. `over`, action params): `{{ path.to.value }}` is replaced by the context value; when the whole string is exactly one template the original type is preserved (object/array/number).

## Validation rules (checked by validate)

- All node ids are globally unique and match `[A-Za-z0-9._-]+`
- code nodes define `async function run(ctx)` and contain no import/require
- forEach `over` resolves to an array; while has a `condition`; actions are known types
- cron is a valid 5-field expression

## Reference files

- `schemas/flow.schema.json` — the full JSON Schema for flows
- `templates/code-node.js` — code node template
- `examples/hello-flow.json` — complete example (code + if + loop + action combined)
- `examples/claude-assist.json` — calling the local Claude Code CLI from a flow
