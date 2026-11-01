#!/bin/bash
# 打标准 DMG 安装包：TimingBomb.app + Applications 拖拽目录
# （Applications 链接目标可用 TB_APPLICATIONS_DIR 覆盖；默认 /Applications，CI 与标准用户通用）
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
PYTHON_BIN="${TB_PYTHON:-}"
PYTHON_CHECK='import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'
if [ -n "$PYTHON_BIN" ]; then
    if ! "$PYTHON_BIN" -I -c "$PYTHON_CHECK" >/dev/null 2>&1; then
        echo 'TB_PYTHON must point to a working Python 3.10 or newer interpreter' >&2
        exit 1
    fi
else
    for candidate in python3 python3.15 python3.14 python3.13 python3.12 python3.11 python3.10; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -I -c "$PYTHON_CHECK" >/dev/null 2>&1; then
            PYTHON_BIN="$(command -v "$candidate")"
            break
        fi
    done
    if [ -z "$PYTHON_BIN" ]; then
        echo 'Building the DMG requires Python 3.10 or newer. Install it and set TB_PYTHON to its executable path.' >&2
        exit 1
    fi
fi

PACKAGE_VERSION="$("$PYTHON_BIN" -I -c 'import json; print(json.load(open("Skills/timingbomb/package.json"))["version"])')"
VERSION="${TB_VERSION:-$PACKAGE_VERSION}"
if [ "$VERSION" != "$PACKAGE_VERSION" ]; then
    echo "DMG and npm package versions must match" >&2
    exit 1
fi
DMG="$ROOT/dist/TimingBomb-${VERSION}-arm64.dmg"
APPS_DIR="${TB_APPLICATIONS_DIR:-/Applications}"
DMG_VENV="$ROOT/.build/dmg-venv"
DMG_PYTHON="$DMG_VENV/bin/python"
REQUIREMENTS="$ROOT/scripts/dmg-requirements.txt"

# Write Finder metadata directly, so packaging also works without a logged-in
# Finder session or Apple Events permission. Keep Python dependencies local.
if ! "$DMG_PYTHON" -I -c "$PYTHON_CHECK" >/dev/null 2>&1; then
    # A venv created by Apple's older system Python cannot install these pins.
    # Recreate only this generated tool environment, never the caller's Python.
    rm -rf "$DMG_VENV"
    "$PYTHON_BIN" -I -m venv "$DMG_VENV"
fi
if ! "$DMG_PYTHON" -I - "$REQUIREMENTS" <<'PY'
import importlib.metadata
import pathlib
import sys

try:
    for requirement in pathlib.Path(sys.argv[1]).read_text().splitlines():
        name, version = requirement.split("==")
        if importlib.metadata.version(name) != version:
            sys.exit(1)
except importlib.metadata.PackageNotFoundError:
    sys.exit(1)
PY
then
    echo "==> install local DMG build tools"
    env -u PIP_TARGET -u PIP_PREFIX -u PIP_USER PIP_CONFIG_FILE=/dev/null \
        "$DMG_PYTHON" -I -m pip install --disable-pip-version-check \
        --index-url https://pypi.org/simple -r "$REQUIREMENTS"
fi

./scripts/make-app.sh

# Preserve the previous installer until its replacement has passed verification.
DMG_WORK=$(mktemp -d "$ROOT/dist/.dmg-build.XXXXXX")
trap 'rm -rf "$DMG_WORK"' EXIT
DMG_CANDIDATE="$DMG_WORK/TimingBomb.dmg"

echo "==> create dmg with drag-to-install layout"
"$DMG_PYTHON" -I -m dmgbuild \
    -s "$ROOT/scripts/dmg-settings.py" \
    -D "app=$ROOT/dist/app-staging/TimingBomb.app" \
    -D "applications=$APPS_DIR" \
    -D "background=$ROOT/scripts/dmg-assets/background.png" \
    TimingBomb "$DMG_CANDIDATE"
hdiutil verify "$DMG_CANDIDATE" -quiet
mv -f "$DMG_CANDIDATE" "$DMG"

echo "==> done: $DMG"
