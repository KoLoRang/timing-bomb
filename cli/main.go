// tb — cross-platform CLI client for the TimingBomb automation service.
// Stdlib only: builds for macOS / Linux / Windows without CGO.
package main

import (
	"fmt"
	"os"
)

const version = "0.1.4"

const usage = `tb — TimingBomb CLI client (v%s)

Usage: tb <command> [subcommand] [flags] [args]

Commands:
  status                       Daemon health / version (accepts --json)
  auth token                   Print the local API token
  flow list [--json]           List flows
  flow show <id> [--json]      Show a flow definition
  flow create --file <f>       Create/update a flow (also reads stdin)
  flow validate --file <f>     Validate a flow without saving
  flow rm <id>                 Delete a flow
  run <id> [--input <json>]    Trigger a run (--wait, --dry-run, --json)
  runs list [--flowId <id>]    Run history (--limit N, --json)
  runs show <runId> [--json]   Run timeline / logs / final context
  runs cancel <runId>          Cancel a running run
  runs rm <runId>              Delete one run record
  runs clear [--flowId <id>]   Clear run records (--yes to confirm)
  allow list                   List shell/appleScript allowlist rules
  allow add "<pattern>"        Add a rule (e.g. "git *")
  allow rm "<pattern>"         Remove a rule (exact text)
  logging status|on|off        Run-history logging toggle

Environment:
  TIMING_BOMB_HOST             Remote TimingBomb address (IP / host / host:port / http(s)://…).
                               Port defaults to 47632 when omitted.
  TIMING_BOMB_API_TOKEN        API token; required together with TIMING_BOMB_HOST.
  TIMINGBOMB_TOKEN             Local token override (otherwise read from the token file).
  TIMINGBOMB_HOME              Local data dir override (token file location).
  TIMINGBOMB_PORT              Local daemon port override (default 47632).

The daemon itself runs inside the TimingBomb Mac app (or from the Swift
sources). This CLI is a pure API client and works from any machine.
`

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		fmt.Printf(usage, version)
		return
	}
	switch args[0] {
	case "version", "--version", "-v":
		fmt.Printf("tb %s\n", version)
	case "help", "--help", "-h":
		fmt.Printf(usage, version)
	case "status":
		cmdStatus(args[1:])
	case "auth":
		cmdAuth(args[1:])
	case "flow":
		cmdFlow(args[1:])
	case "run":
		cmdRun(args[1:])
	case "runs":
		cmdRuns(args[1:])
	case "allow":
		cmdAllow(args[1:])
	case "logging":
		cmdLogging(args[1:])
	case "serve":
		fail("`tb serve` is not part of the Go client. Start the TimingBomb Mac app, or run the Swift daemon (timingbombd) from the repository.")
	default:
		fail(fmt.Sprintf("unknown command %q — run `tb help`", args[0]))
	}
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, "Error: "+message)
	os.Exit(1)
}
