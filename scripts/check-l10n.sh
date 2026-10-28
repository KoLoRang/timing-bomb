#!/bin/bash
# L10n completeness check: every user-facing English template in Sources must
# have a zh-Hans entry in ZhHans.swift. Prints missing keys; exit 1 if any.
set -euo pipefail
cd "$(dirname "$0")/.."

# All L10n.t("...") templates (multi-line aware), decoded escapes.
used=$(
    perl -0777 -ne '
        while (/L10n\.t\(\s*"((?:[^"\\]|\\.)*)"/g) {
            my $s = $1; $s =~ s/\\n/\n/g; $s =~ s/\\"/"/g; print "$s\n";
        }' $(find Sources -name "*.swift" -not -path "*TimingBombL10n*")
    perl -0777 -ne '
        while (/template:\s*"((?:[^"\\]|\\.)*)"/g) {
            my $s = $1; $s =~ s/\\n/\n/g; $s =~ s/\\"/"/g; print "$s\n";
        }' $(find Sources -name "*.swift" -not -path "*TimingBombL10n*")
    perl -0777 -ne '
        while (/(?:IssueText\(|message:)\s*"((?:[^"\\]|\\.)*)"/g) {
            my $s = $1; $s =~ s/\\n/\n/g; $s =~ s/\\"/"/g; print "$s\n";
        }' Sources/TimingBombCore/Validation.swift
)

# Table keys.
defined=$(
    perl -0777 -ne '
        while (/^\s{8}"((?:[^"\\]|\\.)*)":/mg) {
            my $s = $1; $s =~ s/\\n/\n/g; $s =~ s/\\"/"/g; print "$s\n";
        }' Sources/TimingBombL10n/ZhHans.swift
)

missing=$(comm -23 <(printf '%s\n' "$used" | sort -u) <(printf '%s\n' "$defined" | sort -u))
unused=$(comm -13 <(printf '%s\n' "$used" | sort -u) <(printf '%s\n' "$defined" | sort -u))

if [ -n "$missing" ]; then
    echo "MISSING zh-Hans translations:"; printf '%s\n' "$missing" | sed 's/^/  /'
fi
if [ -n "$unused" ]; then
    echo "Unused table entries:"; printf '%s\n' "$unused" | sed 's/^/  /'
fi
if [ -z "$missing" ]; then echo "l10n check: all keys translated ($(printf '%s' "$used" | sort -u | wc -l | tr -d ' ') templates)"; fi
[ -z "$missing" ]
