---
name: timingbomb
description: Create, validate, trigger and manage TimingBomb automation flows (Mac task orchestration). Use when the user asks for "scheduled tasks / automation flows / task orchestration / polling monitors / data pipelines" or mentions the tb command.
---

# TimingBomb Skill

TimingBomb is a task-orchestration service that runs on a Mac (usually the local machine; it can also run on another Mac on the LAN — see "Prerequisites & environment detection" below). Flows are composed of nodes; node code runs JavaScript inside a built-in sandbox with zero external dependencies. This skill drives the service through the `tb` CLI.

## Prerequisites & environment detection

- Install the CLI: `npm install -g timingbomb` (provides `tb`).
  - Target machine cannot reach registry.npmjs.org (e.g. restricted DNS)? Copy the
    matching prebuilt binary from `assets/` (`tb-linux-amd64`, `tb-darwin-arm64`,
    `tb-windows-amd64.exe`, …) onto it, put it on PATH, and call it directly.
- The TimingBomb service must be running. **Before doing anything, decide whether you are in a local or a remote environment** (see below).

### Step 1 — detect local vs. remote

1. Assume **local** by default: run `tb status`.
   - Prints `daemon: running (…)` → local mode; use the command dictionary as-is.
   - Connection fails → ask the user to start TimingBomb on this machine (open the TimingBomb app).
2. Switch to **remote** mode when either of these signals appears:
   - The user explicitly mentions "the other Mac / remote / the TimingBomb on my other machine", or gives you an IP/host;
   - Local `tb status` fails but the user still wants TimingBomb work → confirm with the user whether the service is remote.

### Step 2 — remote only: configure the connection

Prefer an SSH tunnel to the Mac's loopback service or an HTTPS reverse proxy.
Remote mode needs `TIMING_BOMB_HOST` and `TIMING_BOMB_API_TOKEN` (the token comes
from the **remote Mac**). Load the token from a private environment or secret
manager; never put its value in shell command arguments, history, flow JSON,
documentation or tool output.

```bash
export TIMING_BOMB_HOST=https://timingbomb.example.com:443
tb status
tb flow list # verifies authentication; status only checks health
```

For direct LAN/VPN access, guide the user through two steps **on the remote Mac**:

1. TimingBomb app → Settings → Connection → turn on **Allow LAN access** (off by default; when off the service only listens on 127.0.0.1 and is unreachable from the network);
2. On the same page, copy the **API Token** into their private client configuration. Do not run `tb auth token` through captured tools or request that the user paste the token into chat.

With LAN access on, the service listens on **every** interface, including VPN
tunnels. Bearer authentication does not encrypt traffic. The CLI rejects
non-loopback HTTP unless `TIMINGBOMB_ALLOW_INSECURE_HTTP=1` is explicitly set;
this also applies to Tailscale/VPN addresses. Explain this tradeoff and use the
opt-in only when the user chooses to trust that network. With an SSH tunnel to
the loopback service, LAN access can remain off. Host values may be an IP,
hostname, `host:port`, or an `http(s)://` URL; bare hosts default to port 47632.

Gotchas: setting only `TIMING_BOMB_HOST` without `TIMING_BOMB_API_TOKEN` fails immediately; a wrong token still passes `tb status` (health is unauthenticated) but business commands (flow/run/…) return 401 — trust the business commands. When creating flows whose code nodes contain JS quotes **over SSH**, prefer `--file` with a transferred file — multiple shell layers mangle inline stdin escaping.

Note: `tb serve` does not exist in this client. The service always runs inside the TimingBomb Mac app (or from the Swift sources on that Mac).

## Command dictionary

Local mode uses these directly; remote mode uses the private environment configured above.

```bash
tb status                                     # daemon health / version
tb flow list [--json]                         # list flows
tb flow show <flowId> [--json]                # inspect a flow definition
tb flow create --file <flow.json>             # create/update a flow (stdin also works)
tb flow validate --file <flow.json>           # validate only, no save (must pass before every delivery)
tb flow pause <flowId>                        # pause: schedule/webhook/fileWatch triggers are skipped (tb run still works)
tb flow resume <flowId>                       # resume a paused flow (slots missed while paused are not caught up)
tb flow rm <flowId>                           # delete a flow
tb node list [--json]                         # list reusable favorite nodes
tb node show <favoriteId> [--json]            # inspect notes, script/config and source
tb node show <favoriteId> --node-only         # export the plain node JSON for a flow
tb node save --flow <flowId> --node <nodeId> [--name "..."] # favorite a node (including children)
tb node save --file <node.json> [--name "..."] # favorite a standalone node
tb node rm <favoriteId>                       # remove a user-created favorite; built-ins are protected
tb run <flowId> --input '<json>' --wait       # trigger a run and wait for the result
tb run <flowId> --dry-run --wait              # dry-run: tools/actions cause no real side effects
tb runs list [--flowId <id>] [--limit 20]     # run history
tb runs show <runId>                          # node timeline / logs / final context
tb runs cancel <runId>                        # cancel a run
tb runs rm <runId>                            # delete one run record
tb runs clear [--flowId <id>] --yes           # clear run records (all flows, or one flow)
tb approvals list [--all] [--json]            # pending approvals (--all includes decided history)
tb approvals approve <approvalId> [--comment "..."]  # approve: the suspended run resumes
tb approvals reject <approvalId> [--comment "..."]   # reject: the run fails and stops
tb approvals rm <approvalId>                  # delete one decided record (pending ones are protected)
tb approvals clear --yes                      # clear decided approval history (pending kept)
tb allow list|add "<pattern>"|rm "<pattern>"  # shell/appleScript allowlist
tb logging on|off|status                      # run-history logging toggle
```

## Standard agent workflow

0. At the start of a session, detect local/remote mode per "Prerequisites & environment detection" (for remote, configure `TIMING_BOMB_HOST` / `TIMING_BOMB_API_TOKEN` and verify with `tb status`);
1. Check `tb node list --json` and inspect relevant favorites with `tb node show <favoriteId>` before generating the flow. Reuse suitable configured nodes wherever possible, following "Favorite nodes" below;
2. `tb flow validate` must report zero errors;
3. Save the definition with `tb flow create`. Use a `manual` trigger during validation: saving a `schedule` or `fileWatch` flow activates that trigger and it may run automatically. If shell access is needed, prompt the user to run `tb allow add`;
4. Dry-run: `tb run <flowId> --input '<sample payload>' --dry-run --wait` (no side effects; unauthorized shell commands fail right here);
5. After inspecting the dry-run result, perform a real run only within the user's authorized scope and check its output. For a requested schedule or file watch, restore the intended trigger after validation, then validate and save the final definition again to activate it; report that activation. If the user requested only a dry-run, keep the trigger manual and do not perform a real run or activate an automatic trigger;
6. Report the result and which favorites were reused. If the flow contains useful general-purpose nodes that are not already favorites (for example a notification channel), briefly offer to save those nodes for future flows. This suggestion does not block completing the flow; save them when the user requests it.

## Credentials, history and verification

- Never embed real credentials in scripts, action params, favorite nodes,
  descriptions, example inputs or exported JSON. These definitions preserve
  their original content. Supply secrets at execution through the user's
  approved private credential mechanism and avoid printing them from code.
- Run history is enabled by default and retains completed runs for 30 days.
  API run views and stored terminal history redact common credential fields
  and recognizable token formats, but this cannot detect every sensitive
  value. Existing historical content is not retroactively scrubbed.
- Pending approvals retain the original context in the private database so
  execution can resume, even when history is off. Completion or rejection
  replaces it with redacted history, or removes it when history is off.
  File permissions protect this database; it is not encrypted. Deletion and
  redaction do not guarantee immediate erasure from journals or backups.
- For development or release smoke checks, use disposable `TIMINGBOMB_HOME`
  and an unused `TIMINGBOMB_PORT`. Never add test flows or synthetic records
  to the installed service. Distinguish a synthetic check from a real run
  requested by the user; report the actual verification performed.

## Favorite nodes

The app's **Favorite Nodes** page lists saved nodes; selecting one shows its input/output descriptions and script or action configuration. Favorites are persistent snapshots. A copy added to a flow is independent of the favorite and of its source flow; editing or deleting one does not update the others.

Every installation seeds the built-in `builtin-desktop-notification` favorite
(`桌面通知`). It is an action node with `notify`, using
`{{trigger.payload.title}}` for the notification title and
`{{trigger.payload.message}}` for the body. Its input description is title and
message strings; its output is `{notified: true}` for a submitted request in a
real run and `{dryRun: true}` during dry-run. TimingBomb.app sends the native
macOS notification with its app icon; it must be running with notifications
allowed. The output alone does not prove that macOS displayed the notification.
Reuse this favorite when a flow needs a desktop notice, or edit its templates in
the app's favorite detail page. This built-in favorite cannot be deleted through
the app, CLI or API. User-created favorites remain deletable, and copies in flows
can still be edited or removed independently.

When creating a flow:

- Inspect a candidate's `inputDescription`, `outputDescription`, script, params and execution policy. Reuse it when its behavior fits the user's request; do not force an incompatible favorite into the flow.
- Export with `tb node show <favoriteId> --node-only > node.json` and place that object in the target flow's `nodes`, `then`, `else` or `body`. This command only exports JSON; it does not modify a flow.
- Keep node IDs unique across the whole target flow, including nested children. If IDs change, update all internal references in code, conditions, templates and notes. Check external dependencies such as `nodes.prepare.output` and `loop.item`: copying a node does not copy its upstream nodes or supply their outputs. Adapt the references or include the required upstream nodes before validation.
- Prefer documented input via `trigger.payload` or explicit upstream references for a general-purpose node. Describe required fields, types, examples and the output shape in the two description fields. These are human-readable notes, not runtime type checks.
- The app adjusts conflicting IDs and recognized direct context references when inserting a favorite. Dynamic indexes, variable aliases and Python f-string expressions are not rewritten automatically; inspect these and the input/output notes after an ID changes. CLI export does not perform any rewriting.

To save an already configured node, use `tb node save --flow <flowId> --node <nodeId> --name "Notification channel"`. The lookup includes nested branches and loops; favoriting a parent keeps its children. `tb node save --file <node.json>` accepts a standalone node object and derives the name from its `name` or `id` when `--name` is omitted. Both save forms accept `--json` and create a new favorite; avoid saving an existing favorite again merely because it was reused. Removing a favorite uses its favorite ID, not the embedded node ID.

## Flow JSON structure

```jsonc
{
  "id": "kebab-or-dash-id",          // [A-Za-z0-9._-], globally unique
  "name": "Human-readable name",
  "version": 1,
  "description": "Optional notes",
  "trigger": {                        // optional; defaults to manual/webhook
    "type": "schedule",               // manual | schedule | webhook | fileWatch
    "cron": "0 9 * * 1-5",            // 5-field cron; schedule needs cron OR runAt
    // "runAt": "2026-12-01 09:30",   // one-shot: run once at this local time (instead of cron)
    "timezone": "Asia/Shanghai",
    "misfire": "skip"                 // skip | fireOnce
  },
  "nodes": [ /* node array, see below */ ]
}
```

Common node fields: `id` (unique across the flow, including nested nodes), `type`, `name`, `inputDescription`, `outputDescription`, `timeoutMs`, `onError` (`abort`|`continue`, default abort), `retries`, `skipIf` (condition expression, skip when false). The optional description fields are plain text saved with the node, its flow exports and its favorites. For example:

```json
{
  "id": "notify",
  "type": "action",
  "action": "notify",
  "name": "Desktop notification",
  "inputDescription": "trigger.payload.title and trigger.payload.message: notification title and message strings.",
  "outputDescription": "{notified: true} after submitting the notification.",
  "params": {
    "title": "{{trigger.payload.title}}",
    "body": "{{trigger.payload.message}}"
  }
}
```

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
  - `ctx.get("a.b.0.c")` — deep-path lookup (undefined when missing)
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

Execution **suspends** at this node (run status awaitingApproval) until handled in the app's Approvals page or with `tb approvals approve|reject <approvalId>` (find the id with `tb approvals list`):

- Approve → execution resumes after the node (context/timeline preserved, same runId)
- Reject (optional comment) → the run fails and stops
- `message` supports `{{ templates }}`; **not allowed inside loop bodies** (the validator rejects it); fine inside if-branches

Approving or rejecting is a user decision: only do it when the user explicitly asks; otherwise report the pending approval and let them handle it.

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
- `notify`: `{"title": "...", "body": "..."}` (native macOS notification from TimingBomb.app; requires the app running and notification permission)
- `openApp`: `{"name": "Safari"}`
- `clipboard`: `{"op": "read"}` or `{"op": "write", "text": "..."}`
- `fileRead` / `fileWrite`: `{"path": "out/a.txt"}` / `{"path": "out/a.txt", "content": "..."}` — paths are relative to the flow workspace (`~/Library/Application Support/TimingBomb/workspaces/<flowId>/`); `..` and absolute paths are rejected

Strings inside params support `{{ templates }}` referencing the context.

### Triggers (trigger.type)

- `manual`: by hand (default)
- `webhook`: external API (`POST /hooks/<flowId>` + Bearer token)
- `schedule`: `{"cron": "0 9 * * 1-5", "timezone": "Asia/Shanghai", "misfire": "skip|fireOnce"}` (late fire > 5 minutes is skipped by default); one-shot: `{"runAt": "2026-12-01 09:30", "timezone": "Asia/Shanghai"}` runs once at that time (`yyyy-MM-dd HH:mm`, mutually exclusive with `cron`)
- `fileWatch`: `{"path": "~/Downloads/inbox"}` — recursive directory watching (FSEvents), 2.5s debounce, payload injects `{events: [{path, event}]}`

## Template syntax

`{{ path.to.value }}` reads a dot-separated context path. A whole-template loop `over` preserves the referenced type (array/number); mixed text is interpolated as a string. Action `params` currently renders every templated string back to a string, including whole-template object/array/number references. When an action needs a structured object, construct its JSON fields explicitly or use a code node to build and send the value. Missing template paths resolve to null (the text `"null"` inside action string params).

## Validation rules (checked by validate)

- All node ids are unique across the flow and match `[A-Za-z0-9][A-Za-z0-9._-]*`
- JavaScript code nodes define `async function run(ctx)` and contain no import/require; Python and Shell use the stdin/stdout protocol above
- forEach `over` resolves to an array; while has a `condition`; actions are known types
- cron is a valid 5-field expression; `runAt` is `yyyy-MM-dd HH:mm` and not combined with `cron` (a past runAt is a warning)

## Reference files

- `schemas/flow.schema.json` — the full JSON Schema for flows
- `templates/code-node.js` — code node template
- `examples/hello-flow.json` — complete example (code + if + loop + action combined)
- `examples/claude-assist.json` — calling the local Claude Code CLI from a flow
