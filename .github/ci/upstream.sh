#!/usr/bin/env bash
# Upstream versions for the daily watch (PROJECT_PLAN.md COMP-5).
#
#   .github/ci/upstream.sh versions        print "SOURCE NAME VERSION" for everything
#                                  Clave installs or talks to, sorted
#   .github/ci/upstream.sh diff OLD NEW    print what changed between two such lists
#                                  as a Markdown list. With GITHUB_OUTPUT set,
#                                  also writes changed=true|false and
#                                  watched=true|false (a package in
#                                  .github/ci/watched.txt changed) there.
#
# Repository packages come from pacman -Si after pacman -Sy, never -Syu. On a
# machine without pacman (the GitHub runner) that runs in an archlinux
# container. AUR packages come from the AUR RPC, git repositories from
# git ls-remote. A package that is gone prints the version "missing": a
# removed package breaks the install as surely as a changed one.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
watched="$repo/.github/ci/watched.txt"

names() {  # names FILE...: package names from package lists
    sed 's/#.*//' "$@" | tr -s '[:blank:]' '\n' | sed '/^$/d'
}
watched_of() { awk -v s="$1" '$1 == s { print $2 }' "$watched"; }

repo_si() {
    if command -v pacman >/dev/null && [ -z "${UPSTREAM_DOCKER:-}" ]; then
        pacman -Si "$@" 2>/dev/null || true
    else
        docker run --rm archlinux:latest sh -c 'pacman -Sy >/dev/null && pacman -Si "$@" 2>/dev/null; true' sh "$@"
    fi
}

versions() {
    local repo_pkgs aur_pkgs p q
    mapfile -t repo_pkgs < <({ names "$repo"/packages/{core,look,desktop,apps,extras,harden}.txt; watched_of repo; } | sort -u)
    mapfile -t aur_pkgs < <({ names "$repo"/packages/{look,harden}-aur.txt; watched_of aur; } | sort -u)
    {
        found=$(repo_si "${repo_pkgs[@]}" | awk '/^Name/ { n = $3 } /^Version/ { print "repo", n, $3 }' | sort -u -k2,2)
        echo "$found"
        for p in "${repo_pkgs[@]}"; do
            echo "$found" | awk -v p="$p" '$2 == p { f = 1 } END { exit !f }' || echo "repo $p missing"
        done
        q=$(printf '&arg[]=%s' "${aur_pkgs[@]}")
        found=$(curl -fsSg "https://aur.archlinux.org/rpc/v5/info?${q#&}" | jq -r '.results[] | "aur \(.Name) \(.Version)"')
        echo "$found"
        for p in "${aur_pkgs[@]}"; do
            echo "$found" | awk -v p="$p" '$2 == p { f = 1 } END { exit !f }' || echo "aur $p missing"
        done
        awk '$1 == "git" { print $2, $3 }' "$watched" | while read -r name url; do
            echo "git $name $(git ls-remote "$url" HEAD 2>/dev/null | cut -c1-12 | grep . || echo missing)"
        done
    } | sed '/^$/d' | sort -k2,2 -k1,1
}

diff_lists() {
    local out
    out=$(awk -v W="$(awk '!/^#/ && NF { print $2 }' "$watched" | tr '\n' ' ')" '
        BEGIN { n = split(W, w, " "); for (i = 1; i <= n; i++) watched[w[i]] = 1 }
        FNR == NR { old[$1 " " $2] = $3; next }
        { key = $1 " " $2; seen[key] = 1
          if (!(key in old)) line(key, "new", $3)
          else if (old[key] != $3) line(key, old[key], $3) }
        END { for (k in old) if (!(k in seen)) line(k, old[k], "gone") }
        function line(k, a, b,   f) {
            split(k, f, " ")
            printf "- `%s` (%s): %s → %s%s\n", f[2], f[1], a, b, (f[2] in watched) ? " **watched**" : ""
        }' "$1" "$2" | sort)
    [ -z "$out" ] || echo "$out"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        { [ -n "$out" ] && echo changed=true || echo changed=false
          grep -q '\*\*watched\*\*' <<< "$out" && echo watched=true || echo watched=false
        } >> "$GITHUB_OUTPUT"
    fi
}

case "${1:-}" in
    versions) versions ;;
    diff) [ $# -eq 3 ] || { sed -n '3,10p' "$0"; exit 2; }; diff_lists "$2" "$3" ;;
    *) sed -n '3,10p' "$0"; exit 2 ;;
esac
