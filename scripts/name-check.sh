#!/usr/bin/env bash
# Release check for PROJECT_PLAN.md section 5.1: no Apple names in the repo.
# Only these files may name them: the plan and the README (trademark
# disclaimer, note on the old name), the changelog, the code that moves an
# install from the old names, and the personal option.
set -euo pipefail
cd "$(dirname "$0")/.."
pattern='\b(Mac|MacBook|iMac|macOS|MacOS|macos|Apple|apple|Cupertino|Sonoma|Sequoia)\b|Mission Control|Spotlight|Launchpad|Night Shift|Finder|San Francisco|SF (Pro|Mono)'
allowed='^(docs/PROJECT_PLAN\.md|README\.md|CHANGELOG\.md|lib/migrate\.sh|lib/personal\.sh|packages/personal-aur\.txt|tests/migrate-test\.sh|scripts/name-check\.sh|Notes\.md):'
# xargs exits non-zero when a batch has no match, so the result is read from
# the output: with pipefail, an "if pipeline" test would never fire.
hits=$(git ls-files -co --exclude-standard -z | xargs -0 grep -nIE "$pattern" -- 2>/dev/null | grep -vE "$allowed" || true)
if [ -n "$hits" ]; then
    echo "$hits"
    echo "Apple names found outside the allowed files (see PROJECT_PLAN.md 5.1)." >&2
    exit 1
fi
echo "name check passed"
