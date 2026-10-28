#!/bin/bash
# Builds the Go tb CLI into Skills/timingbomb/assets/.
#
#   ./scripts/build-cli.sh          → current platform only (dev default)
#   ./scripts/build-cli.sh --all    → all six targets (npm tarball / releases)
#
# The assets folder is gitignored: binaries are build artifacts, published to
# npm from CI — the repository never carries them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/cli"

if [ "${1:-}" = "--all" ]; then
    TARGETS=(
        "darwin/arm64"
        "darwin/amd64"
        "linux/amd64"
        "linux/arm64"
        "windows/amd64"
        "windows/arm64"
    )
else
    TARGETS=("$(go env GOOS)/$(go env GOARCH)")
fi

mkdir -p "$ROOT/Skills/timingbomb/assets"
rm -rf "${ROOT:?}/Skills/timingbomb/assets/"*

for target in "${TARGETS[@]}"; do
    GOOS="${target%/*}"
    GOARCH="${target#*/}"
    suffix="tb-${GOOS}-${GOARCH}"
    [ "$GOOS" = "windows" ] && suffix="${suffix}.exe"
    echo "==> $suffix"
    CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
        go build -trimpath -ldflags "-s -w" -o "$ROOT/Skills/timingbomb/assets/$suffix" .
done

echo "==> done:"
ls -lh "$ROOT/Skills/timingbomb/assets/"
