#!/usr/bin/env python3
"""Exercise release binaries with disposable data, synthetic payloads and a loopback port.

The user's running daemon and data directory are never queried or modified.
No notification or external service action is executed.
"""
import argparse
import json
import os
from pathlib import Path
import socket
import sqlite3
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--daemon", type=Path, required=True)
    parser.add_argument("--cli", type=Path, required=True)
    args = parser.parse_args()
    daemon, cli = args.daemon.resolve(), args.cli.resolve()
    require(daemon.is_file() and cli.is_file(), "Build daemon and CLI first")
    with tempfile.TemporaryDirectory(prefix="tb-release-smoke-") as temporary:
        private = Path(temporary)
        data_dir = private / "data"
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        environment = {key: os.environ[key] for key in ("PATH", "TMPDIR", "LANG") if key in os.environ}
        environment.update(HOME=str(private), TIMINGBOMB_HOME=str(data_dir), TIMINGBOMB_PORT=str(port), TB_LANG="en")
        base = f"http://127.0.0.1:{port}"
        token = ""
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def request(method, path, body=None, authorized=True, raw=None):
            headers = {"Content-Type": "application/json"}
            if authorized:
                headers["Authorization"] = "Bearer " + token
            payload = raw if raw is not None else (None if body is None else json.dumps(body).encode())
            req = urllib.request.Request(base + path, data=payload, method=method, headers=headers)
            try:
                response = opener.open(req, timeout=15)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.code, json.load(response)

        log_path = private / "daemon.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen([str(daemon)], env=environment, cwd=private, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    require(process.poll() is None, "Isolated daemon exited before readiness")
                    if (data_dir / "token").exists():
                        token = (data_dir / "token").read_text().strip()
                        try:
                            if request("GET", "/healthz", authorized=False)[0] == 200:
                                break
                        except (OSError, ValueError):
                            pass
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Isolated daemon did not become ready")

                require(request("GET", "/favorites", authorized=False)[0] == 401, "API authentication missing")
                status, settings = request("GET", "/settings")
                require(status == 200 and settings["lanAccess"] is False, "Fresh service enables LAN access")
                for path, mode in [(data_dir, 0o700), (data_dir / "token", 0o600), (data_dir / "timingbomb.sqlite", 0o600)]:
                    require(stat.S_IMODE(path.stat().st_mode) == mode, "Private data permission mismatch")

                status, favorites = request("GET", "/favorites")
                require(status == 200 and len(favorites["favorites"]) == 1, "Fresh data contains unexpected favorites")
                builtin = favorites["favorites"][0]
                require(builtin["id"] == "builtin-desktop-notification", "Built-in notification missing")
                status, denied = request("DELETE", "/favorites/" + builtin["id"])
                require(status == 403 and denied["code"] == "builtin_favorite", "Built-in favorite can be deleted")

                marker = "audit-secret-" + uuid.uuid4().hex
                status, invalid = request("POST", "/flows", raw=('{"password":"' + marker + '",').encode())
                require(status == 400 and marker not in json.dumps(invalid), "Invalid body is echoed in errors")
                custom = {"id": "release-smoke-favorite", "name": "Smoke delay", "node": {"id": "wait", "type": "action", "action": "delay", "params": {"ms": 1}}}
                require(request("POST", "/favorites", custom)[0] == 200, "Saving user favorite failed")
                require(request("DELETE", "/favorites/" + custom["id"])[0] == 200, "Deleting user favorite failed")

                flow = {"id": "release-smoke", "name": "Isolated release smoke", "trigger": {"type": "manual"}, "notifyOnFailure": False,
                        "nodes": [{"id": "calculate", "type": "code", "code": "async function run(ctx) { ctx.tools.log('token=' + ctx.trigger.payload.apiKey); return {value: ctx.trigger.payload.number * 2, apiKey: ctx.trigger.payload.apiKey}; }"},
                                  {"id": "verify", "type": "code", "code": "async function run(ctx) { return {value: ctx.nodes.calculate.output.value, secretPreservedDuringExecution: ctx.nodes.calculate.output.apiKey === ctx.trigger.payload.apiKey}; }"}]}
                require(request("POST", "/validate", flow)[1]["valid"], "Valid flow rejected")
                require(request("POST", "/flows", flow)[0] == 200, "Saving flow failed")
                status, paused = request("POST", "/flows/release-smoke/pause")
                require(status == 200 and paused["paused"] is True, "Pausing flow failed")
                require(request("POST", "/hooks/release-smoke", {})[0] == 409, "Paused flow accepts webhook trigger")
                require(request("POST", "/flows", flow)[1]["paused"] is True, "Saving flow resets paused state")
                status, resumed = request("POST", "/flows/release-smoke/resume")
                require(status == 200 and resumed["paused"] is False, "Resuming flow failed")
                status, result = request("POST", "/flows/release-smoke/run?wait=1", {"payload": {"number": 21, "apiKey": marker}})
                require(status == 200 and result["run"]["status"] == "success", "Code flow failed")
                output = result["run"]["context"]["nodes"]["verify"]["output"]
                require(output == {"value": 42, "secretPreservedDuringExecution": True}, "Execution context was damaged by redaction")
                require(marker not in json.dumps(result), "Run result exposes synthetic credential")
                run_id = result["run"]["id"]
                require(marker not in json.dumps(request("GET", "/runs")[1]), "Run list exposes synthetic credential")
                require(marker not in json.dumps(request("GET", "/runs/" + run_id)[1]), "Run detail exposes synthetic credential")
                with sqlite3.connect(data_dir / "timingbomb.sqlite") as database:
                    history = database.execute("select triggerJson, contextJson, error from runs").fetchall()
                    nodes = database.execute("select inputJson, outputJson, logsJson, error from nodeRuns").fetchall()
                    require(marker not in repr(history + nodes), "Stored terminal history contains synthetic credential")

                for command in (["status", "--json"], ["node", "list", "--json"], ["flow", "list", "--json"],
                                ["flow", "pause", "release-smoke"], ["flow", "resume", "release-smoke"]):
                    completed = subprocess.run([str(cli), *command], env=environment, capture_output=True, timeout=15)
                    require(completed.returncode == 0, "CLI isolated API check failed")
                denied_cli = subprocess.run([str(cli), "node", "rm", builtin["id"]], env=environment, capture_output=True, timeout=15)
                require(denied_cli.returncode != 0, "CLI allows deleting built-in favorite")
                require(token.encode() not in denied_cli.stderr + denied_cli.stdout, "CLI error exposes API credential")
                require(request("DELETE", "/runs/" + run_id)[0] == 200, "Run cleanup failed")
                require(request("DELETE", "/flows/release-smoke")[0] == 200, "Flow cleanup failed")
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
        require(not token or token.encode() not in log_path.read_bytes(), "Daemon log exposes API credential")
        print("PASS isolated release smoke: auth, defaults, permissions, favorite protection, flow execution, privacy, CLI, cleanup")


if __name__ == "__main__":
    main()
