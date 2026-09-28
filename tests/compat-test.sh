#!/usr/bin/env bash
# shellcheck disable=SC2034  # C, rc and out are read inside check's eval strings
# Tests for the compatibility check (COMP-7 to COMP-9): clave-compat's three
# results, known breaks fixed in an older or newer release, a newer
# compat.json (-r), the pacman hook mode and its notice, and
# clave-doctor --fetch against a local "GitHub" with SSH-signed tags.
# Installed versions come from a fake pacman; vercmp is the real one.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
check() { if eval "$1"; then ok "$2"; else fail "$2"; fi; }
command -v vercmp >/dev/null || { echo "skip: vercmp (pacman) not installed"; exit 0; }

# Fake pacman -Q from $tmp/installed ("name version" lines).
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pacman" <<'EOF'
#!/bin/sh
[ "$1" = -Q ] || exit 1
awk -v p="$2" '$1 == p { print; f = 1 } END { exit !f }' "$FAKE_INSTALLED"
EOF
chmod +x "$tmp/bin/pacman"
export PATH="$tmp/bin:$PATH" FAKE_INSTALLED="$tmp/installed"
installed() { printf '%s\n' "$@" > "$tmp/installed"; }
compat() { "$repo/home/.local/bin/clave-compat" "$@"; }
result() { compat "${@:2}" | awk -F'\t' -v p="$1" '$2 == p { print $1 }'; }

cat > "$tmp/compat.json" <<'EOF'
{
  "clave": "1.1.1",
  "tested": {
    "1.1.0": { "hyprland": "0.55.0-1" },
    "1.1.1": { "hyprland": "0.56.2-3", "quickshell": "0.3.1-1", "gtk4": "1:4.22.5-1", "sddm": "0.21.0-7" }
  },
  "breaks": [
    { "package": "hyprland", "from": "0.57.0", "fixed_in_clave": "1.1.2", "issue": "https://example.com/issues/12" },
    { "package": "quickshell", "from": "0.4.0", "fixed_in_clave": null, "issue": "https://example.com/issues/13" },
    { "package": "gtk4", "from": "1:4.20.0", "fixed_in_clave": "1.1.0", "issue": "https://example.com/issues/5" }
  ]
}
EOF
C=(-f "$tmp/compat.json")

installed "hyprland 0.56.2-3" "quickshell 0.3.1-1" "gtk4 1:4.22.5-1"
check '[ "$(result hyprland "${C[@]}")" = OK ]' "tested version is OK"
check '[ "$(result gtk4 "${C[@]}")" = OK ]' "a break fixed in an older Clave (1.1.0) is ignored"
check '[ -z "$(result sddm "${C[@]}")" ]' "a package that is not installed is left out"
check '[ "$(compat "${C[@]}" | wc -l)" = 3 ]' "without names: every installed package tested with this release"

installed "hyprland 0.56.3-1" "quickshell 0.3.1-1"
check '[ "$(result hyprland "${C[@]}")" = Untested ]' "newer than tested, no known break: Untested"
installed "hyprland 0.57.1-1" "quickshell 0.4.0-2"
check '[ "$(result hyprland "${C[@]}")" = Update ]' "known break fixed in Clave 1.1.2: Update"
check 'compat "${C[@]}" hyprland | grep -q "Clave 1.1.2 works with it"' "Update names the release"
check '[ "$(result quickshell "${C[@]}")" = Broken ]' "known break without a fix: Broken"
check 'compat "${C[@]}" quickshell | grep -q "issues/13"' "Broken shows the issue"

# A newer compat.json (clave-doctor --fetch) adds its known breaks.
installed "sddm 0.22.0-1"
cat > "$tmp/newer.json" <<'EOF'
{ "clave": "1.1.3", "tested": {}, "breaks": [
  { "package": "sddm", "from": "0.22.0", "fixed_in_clave": "1.1.3", "issue": "https://example.com/issues/20" } ] }
EOF
check '[ "$(result sddm "${C[@]}" sddm)" = Untested ]' "without the newer list: Untested"
check '[ "$(result sddm "${C[@]}" -r "$tmp/newer.json" sddm)" = Update ]' "with the newer list: Update"
echo '{ not json' > "$tmp/bad.json"
if compat -f "$tmp/bad.json" >/dev/null 2>&1; then fail "broken compat.json refused"; else ok "broken compat.json refused"; fi

# --- pacman hook ------------------------------------------------------------
export CLAVE_SYSTEM_COMPAT="$tmp/compat.json" CLAVE_COMPAT_NOTICE="$tmp/state/compat-notice"
installed "hyprland 0.56.3-1" "quickshell 0.3.1-1"
out=$(printf 'hyprland\nquickshell\n' | compat --hook)
check 'grep -q "hyprland 0.56.3-1: Clave 1.1.1 was tested with 0.56.2-3" <<< "$out"' "hook warns about an untested version"
check '[ ! -e "$CLAVE_COMPAT_NOTICE" ]' "Untested alone leaves no login notice"
installed "hyprland 0.57.1-1" "quickshell 0.3.1-1"
out=$(printf 'hyprland\nquickshell\n' | compat --hook); rc=$?
check '[ "$rc" = 0 ]' "hook never fails the transaction"
check 'grep -q "^hyprland 0.57.1-1: Clave 1.1.2" "$CLAVE_COMPAT_NOTICE"' "Update leaves a login notice"
check '! grep -q quickshell "$CLAVE_COMPAT_NOTICE"' "notice lists only what needs doing"
installed "hyprland 0.56.2-3"
check '[ -z "$(printf "hyprland\n" | compat --hook)" ]' "all OK: the hook prints nothing"
check '[ "$(CLAVE_SYSTEM_COMPAT="$tmp/nothing.json" compat --hook < /dev/null 2>/dev/null; echo $?)" = 1 ]' \
    "no compat.json: reported (pacman shows it, the transaction goes on)"

# The hook file written by system.sh lists the watched packages.
check 'grep -q "clave-compat --hook" "$repo/scripts/system.sh"' "system.sh installs the hook"
check '[ "$(awk "\$1 == \"repo\" || \$1 == \"aur\"" "$repo/ci/watched.txt" | wc -l)" -ge 10 ]' "watched list has the packages"
check 'jq -e ".clave and .tested[.clave] and (.breaks | type == \"array\")" "$repo/compat.json" >/dev/null' "repo compat.json has the format"
check '[ -z "$(awk "\$1 == \"repo\" || \$1 == \"aur\" { print \$2 }" "$repo/ci/watched.txt" | while read -r p; do jq -e --arg p "$p" ".tested[.clave][\$p]" "$repo/compat.json" >/dev/null || echo "$p"; done)" ]' \
    "compat.json has a tested version for every watched package"

# --- upstream watch: comparing two version lists (COMP-5) -------------------
printf 'repo hyprland 0.56.2-3\nrepo kitty 0.48.0-1\nrepo gone 1-1\n' > "$tmp/old.txt"
printf 'repo hyprland 0.57.0-1\nrepo kitty 0.48.0-1\nrepo zoxide 0.10-1\n' > "$tmp/new.txt"
: > "$tmp/gh-out"
out=$(GITHUB_OUTPUT="$tmp/gh-out" "$repo/ci/upstream.sh" diff "$tmp/old.txt" "$tmp/new.txt")
check 'grep -q "hyprland. (repo): 0.56.2-3 → 0.57.0-1 \*\*watched\*\*" <<< "$out"' "upstream diff: watched change marked"
check 'grep -q "gone. (repo): 1-1 → gone" <<< "$out" && grep -q "zoxide. (repo): new → 0.10-1" <<< "$out"' "upstream diff: removed and new packages"
check '! grep -q kitty <<< "$out"' "upstream diff: unchanged package left out"
check 'grep -qx watched=true "$tmp/gh-out" && grep -qx changed=true "$tmp/gh-out"' "upstream diff: outputs for the workflow"
printf 'repo zoxide 0.10-1\n' > "$tmp/new2.txt"; printf 'repo zoxide 0.9-1\n' > "$tmp/old2.txt"; : > "$tmp/gh-out"
GITHUB_OUTPUT="$tmp/gh-out" "$repo/ci/upstream.sh" diff "$tmp/old2.txt" "$tmp/new2.txt" >/dev/null
check 'grep -qx watched=false "$tmp/gh-out"' "upstream diff: other package changes do not run the tests"

# --- clave-doctor --fetch ---------------------------------------------------
if ! command -v ssh-keygen >/dev/null; then
    echo "skip: ssh-keygen not installed (clave-doctor --fetch)"
else
    export HOME="$tmp/home" GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
    mkdir -p "$HOME/.config/clave"
    ssh-keygen -q -t ed25519 -N "" -C test -f "$tmp/key"
    echo "test@example.com $(cat "$tmp/key.pub")" > "$HOME/.config/clave/allowed_signers"
    git config --global user.name Test
    git config --global user.email test@example.com
    git config --global gpg.format ssh
    git config --global user.signingkey "$tmp/key"
    git config --global init.defaultBranch main
    up="$tmp/upstream"
    git init -q "$up"
    cp "$tmp/compat.json" "$up/compat.json"
    git -C "$up" add compat.json && git -C "$up" commit -qm one && git -C "$up" tag -s -m v1.1.1 v1.1.1
    git clone -q "$up" "$tmp/checkout" && git -C "$tmp/checkout" checkout -q v1.1.1
    jq '.clave = "1.1.2" | .tested["1.1.2"] = .tested["1.1.1"] | .breaks += [{"package":"sddm","from":"0.22.0","fixed_in_clave":"1.1.2","issue":"x"}]' \
        "$tmp/compat.json" > "$up/compat.json"
    git -C "$up" commit -qam two && git -C "$up" tag -s -m v1.1.2 v1.1.2
    installed "sddm 0.22.0-1" "hyprland 0.56.2-3"
    doc() { CLAVE_REPO="$tmp/checkout" "$repo/home/.local/bin/clave-doctor" "$@" 2>&1 || true; }
    out=$(doc)
    check 'grep -q "Untested.*sddm 0.22.0-1" <<< "$out"' "doctor without --fetch: sddm Untested"
    out=$(doc --fetch)
    check 'grep -q "Clave 1.1.2 is available" <<< "$out"' "doctor --fetch: newer signed release found"
    check 'grep -q "Update.*sddm 0.22.0-1: Clave 1.1.2" <<< "$out"' "doctor --fetch: its known break means Update"
    check '[ "$(git -C "$tmp/checkout" describe --tags)" = v1.1.1 ]' "doctor --fetch does not move the checkout"
    # An unsigned newer release is not trusted. It gets its own commit: two
    # tags on one commit made in the same second leave git describe free to
    # pick either, which made this check fail at random.
    git -C "$up" commit -q --allow-empty -m three --no-gpg-sign && git -C "$up" tag -m v1.1.3 v1.1.3
    out=$(doc --fetch)
    check 'grep -q "No signed compatibility list" <<< "$out" && ! grep -q "1.1.3 is available" <<< "$out"' \
        "doctor --fetch: unsigned release ignored"
fi

echo
if [ "$fails" -eq 0 ]; then echo "All compatibility tests passed."; else echo "$fails failed."; exit 1; fi
