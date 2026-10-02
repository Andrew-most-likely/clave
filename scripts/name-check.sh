#!/usr/bin/env bash
# Release check for PROJECT_PLAN.md section 5.1: no Apple names in the repo.
# Only these files may name them: the plan and the README (trademark
# disclaimer, note on the old name), the changelog, the code that moves an
# install from the old names, the personal option, and Network Identity's
# profile data (SEC-7).
set -euo pipefail
cd "$(dirname "$0")/.."
pattern='\b(Mac|MacBook|iMac|macOS|MacOS|macos|Apple|apple|Cupertino|Sonoma|Sequoia)\b|Mission Control|Spotlight|Launchpad|Night Shift|Finder|App Store|San Francisco|SF (Pro|Mono)'
allowed='^(docs/PROJECT_PLAN\.md|README\.md|docs/CHANGELOG\.md|lib/migrate\.sh|lib/personal\.sh|packages/personal-aur\.txt|tests/migrate-test\.sh|scripts/name-check\.sh|docs/NOTES\.md):'
# SEC-7 exception (5.1): Network Identity names the systems it imitates, only in
# its profile data, its helper and their test. The shell reads the labels from the helper.
allowed_netid='^(system/harden/usr/share/clave/netid/[a-z]+\.conf|system/harden/usr/local/bin/clave-netid|tests/netid-unit\.sh):|^scripts/manifest-system\.txt:[0-9]+:harden +/usr/share/clave/netid/'
# xargs exits non-zero when a batch has no match, so the result is read from
# the output: with pipefail, an "if pipeline" test would never fire.
hits=$(git ls-files -co --exclude-standard -z | xargs -0 grep -nIE "$pattern" -- 2>/dev/null | grep -vE "$allowed" | grep -vE "$allowed_netid" || true)
if [ -n "$hits" ]; then
    echo "$hits"
    echo "Apple names found outside the allowed files (see PROJECT_PLAN.md 5.1)." >&2
    exit 1
fi
echo "name check passed"
