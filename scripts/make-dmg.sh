#!/bin/bash
# 打标准 DMG 安装包：TimingBomb.app + Applications 拖拽目录
# （Applications 链接目标可用 TB_APPLICATIONS_DIR 覆盖；默认 /Applications，CI 与标准用户通用）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${TB_VERSION:-0.1.0}"
ROOT="$(pwd)"
DMG="$ROOT/dist/TimingBomb-${VERSION}-arm64.dmg"
APPS_DIR="${TB_APPLICATIONS_DIR:-/Applications}"
DMG_VENV="$ROOT/.build/dmg-venv"
DMG_PYTHON="$DMG_VENV/bin/python"
REQUIREMENTS="$ROOT/scripts/dmg-requirements.txt"

# Write Finder metadata directly, so packaging also works without a logged-in
# Finder session or Apple Events permission. Keep Python dependencies local.
if [ ! -x "$DMG_PYTHON" ]; then
    python3 -m venv "$DMG_VENV"
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
