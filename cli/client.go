package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// client resolves the service address + token and performs API calls.
//
// Remote mode: TIMING_BOMB_HOST + TIMING_BOMB_API_TOKEN (both required).
// Local mode (default): http://127.0.0.1:<TIMINGBOMB_PORT|47632> with the
// token from TIMINGBOMB_TOKEN or <TIMINGBOMB_HOME>/token (falling back to
// ~/Library/Application Support/TimingBomb/token, matching the Mac app).
type client struct {
	baseURL string
	token   string
}

func loadClient() (*client, error) {
	if host := strings.TrimSpace(os.Getenv("TIMING_BOMB_HOST")); host != "" {
		token := os.Getenv("TIMING_BOMB_API_TOKEN")
		if token == "" {
			return nil, fmt.Errorf(
				"TIMING_BOMB_API_TOKEN is required when TIMING_BOMB_HOST is set")
		}
		base, err := remoteBaseURL(strings.TrimRight(host, "/"))
		if err != nil {
			return nil, err
		}
		return &client{baseURL: base, token: token}, nil
	}

	token := os.Getenv("TIMINGBOMB_TOKEN")
	if token == "" {
		data, err := os.ReadFile(tokenFilePath())
		if err == nil {
			token = strings.TrimSpace(string(data))
		}
	}
	if token == "" {
		return nil, fmt.Errorf(
			"API token not found (expected at %s). Start the TimingBomb app / daemon first",
			tokenFilePath())
	}
	return &client{baseURL: fmt.Sprintf("http://127.0.0.1:%d", localPort()), token: token}, nil
}

// remoteBaseURL normalizes IP / host / host:port / http(s)://host[:port];
// a missing port gets the default TimingBomb port.
func remoteBaseURL(host string) (string, error) {
	text := host
	if !strings.Contains(text, "://") {
		text = "http://" + text
	}
	u, err := url.Parse(text)
	if err != nil || u.Host == "" ||
		(u.Scheme != "http" && u.Scheme != "https") ||
		u.Path != "" || u.RawQuery != "" || u.Fragment != "" {
		return "", fmt.Errorf("invalid TIMING_BOMB_HOST: %s", host)
	}
	if u.Port() == "" {
		return fmt.Sprintf("%s://%s:%d", u.Scheme, u.Hostname(), localPort()), nil
	}
	return strings.TrimRight(text, "/"), nil
}

func localPort() int {
	if p := os.Getenv("TIMINGBOMB_PORT"); p != "" {
		if n, err := strconv.Atoi(p); err == nil && n > 0 && n < 65536 {
			return n
		}
	}
	return 47632
}

func tokenFilePath() string {
	if home := os.Getenv("TIMINGBOMB_HOME"); home != "" {
		return filepath.Join(home, "token")
	}
	userConfig, err := os.UserConfigDir() // ~/Library/Application Support etc.
	if err != nil {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, ".timingbomb", "token")
	}
	return filepath.Join(userConfig, "TimingBomb", "token")
}

func (c *client) request(method, path string, query url.Values, body []byte) ([]byte, error) {
	endpoint := strings.TrimRight(c.baseURL, "/") + "/" + strings.TrimLeft(path, "/")
	if len(query) > 0 {
		endpoint += "?" + query.Encode()
	}
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, endpoint, reader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json; charset=utf-8")
	}
	resp, err := (&http.Client{Timeout: 10 * time.Minute}).Do(req)
	if err != nil {
		return nil, fmt.Errorf(
			"cannot connect to daemon (%s). Is the TimingBomb service running and reachable?", c.baseURL)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, renderAPIError(resp.StatusCode, data)
	}
	return data, nil
}

// renderAPIError re-renders the daemon's structured error envelope
// ({error, code, template, params}) client-side, matching the wire contract.
func renderAPIError(status int, data []byte) error {
	var body struct {
		Error    string            `json:"error"`
		Code     string            `json:"code"`
		Template string            `json:"template"`
		Params   map[string]string `json:"params"`
	}
	if err := json.Unmarshal(data, &body); err == nil {
		if body.Template != "" {
			return fmt.Errorf("%s", substitute(body.Template, body.Params))
		}
		if body.Error != "" {
			return fmt.Errorf("%s", body.Error)
		}
	}
	return fmt.Errorf("HTTP %d", status)
}

// substitute fills {name} placeholders, the same syntax the daemon uses.
func substitute(template string, params map[string]string) string {
	if len(params) == 0 {
		return template
	}
	out := template
	for name, value := range params {
		out = strings.ReplaceAll(out, "{"+name+"}", value)
	}
	return out
}

func (c *client) get(path string, query url.Values) ([]byte, error) {
	return c.request("GET", path, query, nil)
}

func (c *client) post(path string, query url.Values, body []byte) ([]byte, error) {
	return c.request("POST", path, query, body)
}

func (c *client) delete(path string, query url.Values) ([]byte, error) {
	return c.request("DELETE", path, query, nil)
}

func (c *client) put(path string, body []byte) ([]byte, error) {
	return c.request("PUT", path, nil, body)
}

// --- shared helpers -------------------------------------------------------

// decode generic JSON; m must be a pointer to a map/slice/struct.
func decode(data []byte, v any) error {
	if err := json.Unmarshal(data, v); err != nil {
		return fmt.Errorf("failed to decode response: %v", err)
	}
	return nil
}

// printJSON pretty-prints with sorted keys (Go maps marshal sorted).
func printJSON(data []byte) {
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		fmt.Println(string(data))
		return
	}
	pretty, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		fmt.Println(string(data))
		return
	}
	fmt.Println(string(pretty))
}

func str(m map[string]any, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func num(m map[string]any, key string) float64 {
	if v, ok := m[key].(float64); ok {
		return v
	}
	return 0
}

func boolean(m map[string]any, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}

func array(m map[string]any, key string) []any {
	if v, ok := m[key].([]any); ok {
		return v
	}
	return nil
}

func object(m map[string]any, key string) map[string]any {
	if v, ok := m[key].(map[string]any); ok {
		return v
	}
	return nil
}

// parseTimeValue accepts the daemon's wire timestamps: Unix seconds as a JSON
// number (the default encoder) or an RFC3339 string.
func parseTimeValue(v any) (time.Time, bool) {
	switch value := v.(type) {
	case float64:
		seconds := int64(value)
		nanos := int64((value - float64(seconds)) * 1e9)
		return time.Unix(seconds, nanos), true
	case string:
		if value == "" {
			return time.Time{}, false
		}
		for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
			if t, err := time.Parse(layout, value); err == nil {
				return t, true
			}
		}
	}
	return time.Time{}, false
}

func fmtTime(value any) string {
	if t, ok := parseTimeValue(value); ok {
		return t.Local().Format("01-02 15:04:05")
	}
	return "-"
}

// durationMs between two timestamps, in milliseconds.
func durationMs(started, ended any) (float64, bool) {
	s, ok1 := parseTimeValue(started)
	e, ok2 := parseTimeValue(ended)
	if !ok1 || !ok2 {
		return 0, false
	}
	return e.Sub(s).Seconds() * 1000, true
}

func fmtDuration(ms float64, ok bool) string {
	if !ok {
		return "-"
	}
	if ms < 1000 {
		return fmt.Sprintf("%.0fms", ms)
	}
	return fmt.Sprintf("%.1fs", ms/1000)
}

// row joins columns with fixed widths (two-space gutters), like the Swift CLI.
func row(cols ...any) string {
	parts := make([]string, 0, len(cols)/2)
	for i := 0; i+1 < len(cols); i += 2 {
		text := cols[i].(string)
		width := cols[i+1].(int)
		if len(text) >= width {
			parts = append(parts, text)
		} else {
			parts = append(parts, text+strings.Repeat(" ", width-len(text)))
		}
	}
	return strings.Join(parts, "  ")
}
