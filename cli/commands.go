package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"strings"
)

// newFlagSet keeps flag errors out of stderr; we render them ourselves.
func newFlagSet(name string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	return fs
}

func parseOrDie(fs *flag.FlagSet, args []string) {
	if err := fs.Parse(reorder(args)); err != nil {
		fail(fmt.Sprintf("%s: %v (see `tb help`)", fs.Name(), err))
	}
}

// reorder moves leading positional arguments to the end. Go's flag package
// stops parsing at the first positional, so `tb run hello --wait` would
// otherwise treat "--wait" as positional too.
func reorder(args []string) []string {
	var positional, rest []string
	for i := 0; i < len(args); i++ {
		if strings.HasPrefix(args[i], "-") {
			rest = append(rest, args[i:]...)
			break
		}
		positional = append(positional, args[i])
	}
	return append(rest, positional...)
}

// --- tb status ------------------------------------------------------------

func cmdStatus(args []string) {
	fs := newFlagSet("tb status")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.get("healthz", nil)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	fmt.Printf("daemon: running (%s, v%s) — %s\n", str(body, "status"), str(body, "version"), c.baseURL)
}

// --- tb auth token ---------------------------------------------------------

func cmdAuth(args []string) {
	if len(args) == 0 || args[0] != "token" {
		fail("usage: tb auth token")
	}
	if env := os.Getenv("TIMINGBOMB_TOKEN"); env != "" {
		fmt.Println(env)
		return
	}
	data, err := os.ReadFile(tokenFilePath())
	if err != nil {
		fail(fmt.Sprintf("no local token found at %s", tokenFilePath()))
	}
	fmt.Println(strings.TrimSpace(string(data)))
}

// --- tb flow ---------------------------------------------------------------

func cmdFlow(args []string) {
	if len(args) == 0 {
		fail("usage: tb flow list|show|create|validate|rm")
	}
	sub, rest := args[0], args[1:]
	switch sub {
	case "list":
		flowList(rest)
	case "show":
		flowShow(rest)
	case "create":
		flowCreate(rest)
	case "validate":
		flowValidate(rest)
	case "rm", "remove":
		flowRemove(rest)
	default:
		fail("unknown subcommand: tb flow " + sub)
	}
}

func flowList(args []string) {
	fs := newFlagSet("tb flow list")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.get("flows", nil)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	flows := array(body, "flows")
	if len(flows) == 0 {
		fmt.Println("no flows yet. Create one with `tb flow create --file <flow.json>`.")
		return
	}
	fmt.Println(row("ID", 24, "NAME", 20, "NODES", 6, "TRIGGER", 14, "UPDATED", 12))
	for _, item := range flows {
		entry, _ := item.(map[string]any)
		if entry == nil {
			continue
		}
		flow := object(entry, "flow")
		nodes := array(flow, "nodes")
		trigger := "manual"
		if t := object(flow, "trigger"); t != nil {
			if cron := str(t, "cron"); cron != "" {
				trigger = cron
			} else if kind := str(t, "type"); kind != "" {
				trigger = kind
			}
		}
		fmt.Println(row(
			str(flow, "id"), 24, str(flow, "name"), 20,
			fmt.Sprintf("%d", len(nodes)), 6, trigger, 14,
			fmtTime(entry["updatedAt"]), 12))
	}
}

func flowShow(args []string) {
	fs := newFlagSet("tb flow show")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb flow show <flowId>")
	}
	flowID := fs.Arg(0)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.get("flows/"+url.PathEscape(flowID), nil)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	pretty, _ := json.MarshalIndent(object(body, "flow"), "", "  ")
	fmt.Println(string(pretty))
}

// readFlowSource loads the flow JSON from --file or stdin, validating shape.
func readFlowSource(file string) []byte {
	var data []byte
	if file != "" {
		raw, err := os.ReadFile(file)
		if err != nil {
			fail(fmt.Sprintf("failed to read file: %s", file))
		}
		data = raw
	} else {
		raw, err := io.ReadAll(os.Stdin)
		if err != nil {
			fail("failed to read stdin")
		}
		data = raw
	}
	var flow map[string]any
	if err := json.Unmarshal(data, &flow); err != nil {
		fail(fmt.Sprintf("flow JSON is invalid: %v", err))
	}
	if str(flow, "id") == "" || array(flow, "nodes") == nil {
		fail("flow JSON must contain at least \"id\" and \"nodes\"")
	}
	return data
}

func flowCreate(args []string) {
	fs := newFlagSet("tb flow create")
	file := fs.String("file", "", "path to the flow JSON file (stdin when omitted)")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)

	source := readFlowSource(*file)
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.post("flows", nil, source)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	flow := object(body, "flow")
	fmt.Printf("✓ saved flow %s (%s, %d node(s))\n",
		str(flow, "id"), str(flow, "name"), len(array(flow, "nodes")))
}

func flowValidate(args []string) {
	fs := newFlagSet("tb flow validate")
	file := fs.String("file", "", "path to the flow JSON file (stdin when omitted)")
	parseOrDie(fs, args)

	source := readFlowSource(*file)
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.post("validate", nil, source)
	if err != nil {
		fail(err.Error())
	}
	var body struct {
		Valid  bool             `json:"valid"`
		Issues []map[string]any `json:"issues"`
	}
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	if body.Valid {
		fmt.Println("✓ validation passed")
		return
	}
	fmt.Println("✗ validation failed:")
	for _, issue := range body.Issues {
		mark := "warn "
		if str(issue, "level") == "error" {
			mark = "error"
		}
		fmt.Printf("  [%s] %s: %s\n", mark, str(issue, "path"), issueMessage(issue))
	}
	os.Exit(1)
}

func issueMessage(issue map[string]any) string {
	// Prefer the structured English template over the server-rendered
	// message, which follows the daemon's locale (may be Chinese).
	if template := str(issue, "template"); template != "" {
		params := map[string]string{}
		for k, v := range object(issue, "params") {
			if s, ok := v.(string); ok {
				params[k] = s
			}
		}
		return substitute(template, params)
	}
	if msg := str(issue, "message"); msg != "" {
		return msg
	}
	return "(no message)"
}

func flowRemove(args []string) {
	fs := newFlagSet("tb flow rm")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb flow rm <flowId>")
	}
	flowID := fs.Arg(0)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	if _, err := c.delete("flows/"+url.PathEscape(flowID), nil); err != nil {
		fail(err.Error())
	}
	fmt.Printf("✓ deleted flow %s\n", flowID)
}

// --- tb run ----------------------------------------------------------------

func cmdRun(args []string) {
	fs := newFlagSet("tb run")
	input := fs.String("input", "", "input payload (JSON string); injected as ctx.trigger.payload")
	wait := fs.Bool("wait", false, "wait for the run to finish and print the result")
	dryRun := fs.Bool("dry-run", false, "no real side effects (http/commands/file writes are skipped)")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb run <flowId> [--input '<json>'] [--wait] [--dry-run]")
	}
	flowID := fs.Arg(0)

	var payload any = nil
	if *input != "" {
		if err := json.Unmarshal([]byte(*input), &payload); err != nil {
			fail(fmt.Sprintf("--input is not valid JSON: %.100s", *input))
		}
	}
	body, _ := json.Marshal(map[string]any{"payload": payload})

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	query := url.Values{}
	if *wait {
		query.Set("wait", "1")
	}
	if *dryRun {
		query.Set("dryRun", "1")
	}
	data, err := c.post("flows/"+url.PathEscape(flowID)+"/run", query, body)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	if *wait {
		var envelope map[string]any
		if err := decode(data, &envelope); err != nil {
			fail(err.Error())
		}
		printRunSummary(object(envelope, "run"))
		return
	}
	var started struct {
		RunID  string `json:"runId"`
		Status string `json:"status"`
	}
	if err := decode(data, &started); err != nil {
		fail(err.Error())
	}
	if *dryRun {
		fmt.Printf("dry-run started: runId=%s (no side effects; check `tb runs show %s`)\n",
			started.RunID, started.RunID)
	} else {
		fmt.Printf("started: runId=%s (check `tb runs show %s` for progress)\n",
			started.RunID, started.RunID)
	}
}

// --- tb runs ---------------------------------------------------------------

func cmdRuns(args []string) {
	if len(args) == 0 {
		fail("usage: tb runs list|show|cancel|rm|clear")
	}
	sub, rest := args[0], args[1:]
	switch sub {
	case "list":
		runsList(rest)
	case "show":
		runsShow(rest)
	case "cancel":
		runsCancel(rest)
	case "rm", "remove":
		runsRemove(rest)
	case "clear":
		runsClear(rest)
	default:
		fail("unknown subcommand: tb runs " + sub)
	}
}

func runsList(args []string) {
	fs := newFlagSet("tb runs list")
	flowID := fs.String("flowId", "", "filter by flow id")
	limit := fs.Int("limit", 20, "number of records to return")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	query := url.Values{"limit": []string{fmt.Sprintf("%d", *limit)}}
	if *flowID != "" {
		query.Set("flowId", *flowID)
	}
	data, err := c.get("runs", query)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	runs := array(body, "runs")
	if len(runs) == 0 {
		fmt.Println("no run records yet")
		return
	}
	fmt.Println(row("RUN ID", 38, "FLOW", 18, "STATUS", 9, "DURATION", 10, "STARTED", 12))
	for _, item := range runs {
		record, _ := item.(map[string]any)
		if record == nil {
			continue
		}
		duration, ok := durationMs(record["startedAt"], record["endedAt"])
		fmt.Println(row(
			str(record, "id"), 38, str(record, "flowId"), 18, str(record, "status"), 9,
			fmtDuration(duration, ok), 10, fmtTime(record["startedAt"]), 12))
	}
}

func runsShow(args []string) {
	fs := newFlagSet("tb runs show")
	asJSON := fs.Bool("json", false, "output as JSON")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb runs show <runId>")
	}
	runID := fs.Arg(0)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	data, err := c.get("runs/"+url.PathEscape(runID), nil)
	if err != nil {
		fail(err.Error())
	}
	if *asJSON {
		printJSON(data)
		return
	}
	var envelope map[string]any
	if err := decode(data, &envelope); err != nil {
		fail(err.Error())
	}
	printRunDetail(object(envelope, "run"))
}

func runsCancel(args []string) {
	fs := newFlagSet("tb runs cancel")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb runs cancel <runId>")
	}
	runID := fs.Arg(0)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	if _, err := c.post("runs/"+url.PathEscape(runID)+"/cancel", nil, nil); err != nil {
		fail(err.Error())
	}
	fmt.Printf("✓ cancel request sent (runId=%s)\n", runID)
}

func runsRemove(args []string) {
	fs := newFlagSet("tb runs rm")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb runs rm <runId>")
	}
	runID := fs.Arg(0)

	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	if _, err := c.delete("runs/"+url.PathEscape(runID), nil); err != nil {
		fail(err.Error())
	}
	fmt.Printf("✓ deleted run record %s\n", runID)
}

func runsClear(args []string) {
	fs := newFlagSet("tb runs clear")
	flowID := fs.String("flowId", "", "only clear the given flow (default: all flows)")
	yes := fs.Bool("yes", false, "skip confirmation")
	parseOrDie(fs, args)

	scope := "all flows"
	if *flowID != "" {
		scope = fmt.Sprintf("flow %s", *flowID)
	}
	if !*yes {
		fmt.Printf("This will delete all run records for %s; it cannot be undone. Re-run with --yes to confirm.\n", scope)
		os.Exit(1)
	}
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	query := url.Values{}
	if *flowID != "" {
		query.Set("flowId", *flowID)
	}
	data, err := c.delete("runs", query)
	if err != nil {
		fail(err.Error())
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	fmt.Printf("✓ deleted %d run record(s) for %s\n", int(num(body, "deleted")), scope)
}

// --- tb allow --------------------------------------------------------------

func cmdAllow(args []string) {
	if len(args) == 0 {
		fail("usage: tb allow list|add|rm")
	}
	sub, rest := args[0], args[1:]
	switch sub {
	case "list":
		allowList(rest)
	case "add":
		allowAdd(rest)
	case "rm", "remove":
		allowRemove(rest)
	default:
		fail("unknown subcommand: tb allow " + sub)
	}
}

func allowPatterns(c *client) []string {
	data, err := c.get("allows", nil)
	if err != nil {
		fail(err.Error())
	}
	var body map[string]any
	if err := decode(data, &body); err != nil {
		fail(err.Error())
	}
	items := array(body, "patterns")
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func savePatterns(c *client, patterns []string) {
	body, _ := json.Marshal(patterns)
	if _, err := c.put("allows", body); err != nil {
		fail(err.Error())
	}
}

func allowList(args []string) {
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	patterns := allowPatterns(c)
	if len(patterns) == 0 {
		fmt.Println("(no rules)")
		return
	}
	for _, pattern := range patterns {
		fmt.Println(pattern)
	}
}

func allowAdd(args []string) {
	fs := newFlagSet("tb allow add")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb allow add \"<pattern>\"")
	}
	rule := strings.TrimSpace(fs.Arg(0))
	if rule == "" {
		fail("rule cannot be empty")
	}
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	current := allowPatterns(c)
	for _, existing := range current {
		if existing == rule {
			fmt.Printf("already exists: %s\n", rule)
			return
		}
	}
	savePatterns(c, append(current, rule))
	fmt.Printf("✓ added: %s\n", rule)
}

func allowRemove(args []string) {
	fs := newFlagSet("tb allow rm")
	parseOrDie(fs, args)
	if fs.NArg() != 1 {
		fail("usage: tb allow rm \"<pattern>\"")
	}
	pattern := fs.Arg(0)
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	current := allowPatterns(c)
	found := false
	next := current[:0:0]
	for _, existing := range current {
		if existing == pattern {
			found = true
			continue
		}
		next = append(next, existing)
	}
	if !found {
		fail(fmt.Sprintf("rule not found: %s", pattern))
	}
	savePatterns(c, next)
	fmt.Printf("✓ removed: %s\n", pattern)
}

// --- tb logging ------------------------------------------------------------

func cmdLogging(args []string) {
	if len(args) == 0 {
		fail("usage: tb logging status|on|off")
	}
	c, err := loadClient()
	if err != nil {
		fail(err.Error())
	}
	switch args[0] {
	case "status":
		data, err := c.get("settings", nil)
		if err != nil {
			fail(err.Error())
		}
		var body map[string]any
		if err := decode(data, &body); err != nil {
			fail(err.Error())
		}
		if boolean(body, "loggingEnabled") {
			fmt.Println("run logging: on")
		} else {
			fmt.Println("run logging: off (new runs are not written to the log)")
		}
	case "on", "off":
		enabled := args[0] == "on"
		body, _ := json.Marshal(map[string]any{"loggingEnabled": enabled})
		if _, err := c.put("settings", body); err != nil {
			fail(err.Error())
		}
		if enabled {
			fmt.Println("✓ run logging enabled")
		} else {
			fmt.Println("✓ run logging disabled (new runs are not written to the log)")
		}
	default:
		fail("unknown subcommand: tb logging " + args[0])
	}
}

// --- run rendering ---------------------------------------------------------

var statusMarks = map[string]string{
	"success": "✓", "failed": "✗", "timeout": "⏱", "cancelled": "⊘",
	"running": "…", "pending": "…", "awaitingApproval": "⏸",
}

func statusMark(status string) string {
	if mark, ok := statusMarks[status]; ok {
		return mark
	}
	return "?"
}

func printRunSummary(record map[string]any) {
	if record == nil {
		fail("run record missing in response")
	}
	duration, ok := durationMs(record["startedAt"], record["endedAt"])
	fmt.Printf("%s run %s — %s (%s)\n",
		statusMark(str(record, "status")), str(record, "id"),
		str(record, "status"), fmtDuration(duration, ok))
	if errText := str(record, "error"); errText != "" && str(record, "status") != "success" {
		fmt.Printf("  Error: %s\n", errText)
	}
}

func printRunDetail(record map[string]any) {
	printRunSummary(record)
	if trigger := object(record, "trigger"); trigger != nil {
		fmt.Printf("  Trigger: %s\n", str(trigger, "type"))
	}
	fmt.Println("  Node timeline:")
	for _, item := range array(record, "nodeRuns") {
		nodeRun, _ := item.(map[string]any)
		if nodeRun == nil {
			continue
		}
		duration, ok := durationMs(nodeRun["startedAt"], nodeRun["endedAt"])
		iteration := ""
		if it := num(nodeRun, "iteration"); it > 0 {
			iteration = fmt.Sprintf("#%d ", int(it))
		}
		fmt.Printf("    %s %s%s (%s, %s)\n",
			statusMark(nodeRunStatus(str(nodeRun, "status"))),
			iteration, str(nodeRun, "nodeId"), str(nodeRun, "nodeType"),
			fmtDuration(duration, ok))
		if errText := str(nodeRun, "error"); errText != "" {
			fmt.Printf("        Error: %s\n", errText)
		}
		for _, log := range array(nodeRun, "logs") {
			if s, ok := log.(string); ok {
				fmt.Printf("        Log: %s\n", s)
			}
		}
	}
	if context := object(record, "context"); context != nil {
		pretty, _ := json.MarshalIndent(map[string]any{"context": context}, "", "  ")
		fmt.Println("  Final context:")
		for _, line := range strings.Split(string(pretty), "\n") {
			fmt.Printf("    %s\n", line)
		}
	}
}

// nodeRunStatus maps node-level statuses onto the run status mark set.
func nodeRunStatus(status string) string {
	switch status {
	case "skipped":
		return "pending"
	default:
		return status
	}
}
