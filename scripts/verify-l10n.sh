#!/bin/bash
# Check localized templates and the current API/CLI contract in disposable data.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-l10n.sh
env -u TIMINGBOMB_INCLUDE_TESTS swift build -c release
AUDIT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tb-wire-check.XXXXXX")"
trap 'rm -rf "$AUDIT_DIR"' EXIT
(cd cli && go build -trimpath -o "$AUDIT_DIR/tb" .)
python3 scripts/release-smoke.py --daemon .build/release/timingbombd --cli "$AUDIT_DIR/tb"
