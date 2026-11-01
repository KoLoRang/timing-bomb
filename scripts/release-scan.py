#!/usr/bin/env python3
"""Fail closed on unexpected release files or recognizable embedded credentials.

Prints file names and rule names only; matched credential contents are never logged.
This is a release hygiene check, not a claim to detect every possible secret.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    "private-key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "provider-key": rb"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{24,}\b",
    "github-token": rb"\b(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "aws-access-key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "slack-token": rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
    "npm-token": rb"\bnpm_[A-Za-z0-9]{30,}\b",
    "literal-bearer": rb"(?i)Bearer\s+[A-Za-z0-9._-]{32,}",
    "credential-assignment": rb"(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[=:]\s*[\"'][A-Za-z0-9+/=_-]{32,}[\"']",
}
BINARY_NAMES = {"TimingBombApp", "timingbombd", "jsrunner"}
PLATFORMS = {"tb-darwin-arm64", "tb-darwin-amd64", "tb-linux-arm64", "tb-linux-amd64",
             "tb-windows-arm64.exe", "tb-windows-amd64.exe"}
NPM_FILES = {"README.md", "SKILL.md", "package.json", "bin/tb.js", "bin/postinstall.js",
             "schemas/flow.schema.json", "templates/code-node.js",
             "examples/hello-flow.json", "examples/claude-assist.json"}
NPM_FILES |= {"assets/" + name for name in PLATFORMS}
APP_FILES = {"Contents/Info.plist", "Contents/_CodeSignature/CodeResources", "Contents/Resources/README.md",
             "Contents/Resources/AppIcon.icns", "Contents/Resources/MenuBarTemplate.png",
             "Contents/Resources/MenuBarTemplate@2x.png", "Contents/Resources/MenuBar16Template.png",
             "Contents/Resources/MenuBar16Template@2x.png"}
APP_FILES |= {"Contents/MacOS/" + name for name in BINARY_NAMES}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def scan_bytes(data, label, artifact=False):
    for name, pattern in PATTERNS.items():
        require(re.search(pattern, data) is None, f"{label}: {name}")
    if artifact:
        for value in {str(ROOT), str(Path.home())}:
            require(value.encode() not in data, f"{label}: local build path")
        require(re.search(rb"/" + rb"Users/[A-Za-z0-9._-]+/", data) is None,
                f"{label}: user home path")


def source_scan():
    files = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).split(b"\0")
    forbidden_parts = {"Tests", ".zcode", ".agents", ".codex", ".cursor", ".build", "dist"}
    forbidden_names = {"DESIGN.md", "AGENTS.md", "CLAUDE.md", "GEMINI.md", ".DS_Store", "token", ".env"}
    count = 0
    for raw in sorted(set(files)):
        if not raw:
            continue
        relative = Path(os.fsdecode(raw))
        path = ROOT / relative
        if not path.exists():  # an unstaged removal is not distributed
            continue
        require(not (set(relative.parts) & forbidden_parts), f"{relative}: internal directory")
        require(relative.name not in forbidden_names and not relative.name.startswith(".env."),
                f"{relative}: local-only file")
        require(not re.search(r"\.(?:sqlite(?:-\w+)?|db(?:-\w+)?|log|pem|key|p12|pfx|tgz|dmg)$", relative.name),
                f"{relative}: local data or credential file")
        require(not str(relative).startswith("automation/"), f"{relative}: internal automation")
        require(not path.is_symlink(), f"{relative}: source symlink")
        if path.is_file():
            scan_bytes(path.read_bytes(), str(relative))
            count += 1
    package = json.loads((ROOT / "Skills/timingbomb/package.json").read_text())
    cli = (ROOT / "cli/main.go").read_text()
    version = re.search(r'const version = "([^"]+)"', cli)
    require(version and version.group(1) == package["version"], "CLI/package version mismatch")
    require(re.fullmatch(r"\d+\.\d+\.\d+", package["version"]), "release version must be x.y.z")
    print(f"PASS source scan: {count} files; version {package['version']}")


def app_scan(path):
    require(path.is_dir() and not path.is_symlink(), "App directory is missing or linked")
    actual = set()
    for item in path.rglob("*"):
        require(not item.is_symlink(), "App contains a symlink")
        if item.is_file():
            relative = item.relative_to(path).as_posix()
            actual.add(relative)
            require(relative in APP_FILES, f"App unexpected file: {relative}")
            scan_bytes(item.read_bytes(), "App/" + relative, artifact=True)
    require(actual == APP_FILES, "App contents do not match release allowlist")
    info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
    expected = json.loads((ROOT / "Skills/timingbomb/package.json").read_text())["version"]
    require(info["CFBundleIdentifier"] == "com.timingbomb.app", "App bundle identity mismatch")
    require(info["CFBundleShortVersionString"] == expected, "App/package version mismatch")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(path)], check=True)
    print(f"PASS App scan: {len(actual)} allowlisted files; version {expected}")


def npm_scan(path):
    actual = set()
    package_bytes = None
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            parsed = PurePosixPath(member.name)
            require(not parsed.is_absolute() and ".." not in parsed.parts, "npm unsafe member path")
            require(parsed.parts and parsed.parts[0] == "package", "npm member outside package")
            relative = PurePosixPath(*parsed.parts[1:]).as_posix()
            if member.isdir():
                continue
            require(member.isfile(), "npm links and special files are forbidden")
            require(relative in NPM_FILES, f"npm unexpected file: {relative}")
            require(relative not in actual, "npm duplicate member")
            actual.add(relative)
            data = archive.extractfile(member).read()
            scan_bytes(data, "npm/" + relative, artifact=True)
            if relative == "package.json":
                package_bytes = data
    require(actual == NPM_FILES, "npm package must contain all six CLI platforms and only allowlisted files")
    expected = json.loads((ROOT / "Skills/timingbomb/package.json").read_text())
    require(json.loads(package_bytes)["version"] == expected["version"], "npm package version mismatch")
    print(f"PASS npm scan: {len(actual)} allowlisted files; sha256 {hashlib.sha256(path.read_bytes()).hexdigest()}")


def dmg_scan(path):
    subprocess.run(["hdiutil", "verify", str(path), "-quiet"], check=True)
    with tempfile.TemporaryDirectory(prefix="tb-dmg-scan-") as directory:
        mount = Path(directory) / "volume"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", str(path), "-readonly", "-nobrowse", "-mountpoint", str(mount), "-quiet"], check=True)
        try:
            allowed = {"TimingBomb.app", "Applications", ".DS_Store", ".background.tiff", ".VolumeIcon.icns", ".fseventsd"}
            require({p.name for p in mount.iterdir()} <= allowed, "DMG unexpected top-level contents")
            require((mount / "Applications").is_symlink(), "DMG Applications link is missing")
            require(os.readlink(mount / "Applications") == "/Applications", "DMG has a machine-specific Applications link")
            require((mount / ".DS_Store").is_file() and (mount / ".background.tiff").is_file(),
                    "DMG Finder layout or background is missing")
            app_scan(mount / "TimingBomb.app")
            for item in mount.rglob("*"):
                relative = item.relative_to(mount)
                if "TimingBomb.app" in relative.parts:
                    continue
                require(not item.is_symlink() or relative.as_posix() == "Applications", "DMG contains an unexpected link")
                if item.is_file() and not item.is_symlink():
                    require(relative.as_posix() in {".DS_Store", ".background.tiff", ".VolumeIcon.icns"}
                            or (len(relative.parts) == 2 and relative.parts[0] == ".fseventsd"
                                and re.fullmatch(r"(?:[0-9a-fA-F]{16}|fseventsd-uuid|no_log)", relative.name)),
                            f"DMG unexpected file: {relative.as_posix()}")
                    scan_bytes(item.read_bytes(), "DMG/" + relative.as_posix(), artifact=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount), "-quiet"], check=True)
    print(f"PASS DMG scan: sha256 {hashlib.sha256(path.read_bytes()).hexdigest()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--npm", type=Path)
    parser.add_argument("--dmg", type=Path)
    args = parser.parse_args()
    require(args.source or args.app or args.npm or args.dmg, "Choose at least one scan target")
    if args.source:
        source_scan()
    if args.app:
        app_scan(args.app.resolve())
    if args.npm:
        npm_scan(args.npm.resolve())
    if args.dmg:
        dmg_scan(args.dmg.resolve())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError, tarfile.TarError) as error:
        # Diagnostics contain a rule/path only, never matching file contents.
        print(f"FAIL release scan: {error}", file=sys.stderr)
        sys.exit(1)
