# shellcheck shell=bash disable=SC2154  # repo: set by the caller
# Signed releases, shared by clave-update and clave-doctor --fetch. Sourced;
# needs $repo (the checkout).
#
# Updates run code on this machine, so only releases signed by a trusted key
# are installed or trusted. The keys are the project's, shipped next to this
# file (updates may add a new key, but only in a release the old key signed),
# plus any the user adds to ~/.config/clave/allowed_signers.
CLAVE_SIGNERS=("${BASH_SOURCE[0]%/*}/allowed_signers" "${XDG_CONFIG_HOME:-$HOME/.config}/clave/allowed_signers")

verify() {  # verify tag|commit REF
    local all rc
    all=$(mktemp) || return 1
    cat "${CLAVE_SIGNERS[@]}" > "$all" 2>/dev/null
    git -C "$repo" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$all" \
        "verify-$1" "$2" >/dev/null 2>&1
    rc=$?
    rm -f "$all"
    return "$rc"
}

# newest_ref: after a fetch, print the ref an update would move to: the
# upstream branch when the checkout follows one, else the newest release
# tag. Prints nothing and returns 1 when that ref is not signed, or when it
# is older than what is installed (a release is never rolled back).
newest_ref() {
    local ref kind
    if git -C "$repo" symbolic-ref -q HEAD >/dev/null; then
        ref=$(git -C "$repo" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo origin/main)
        kind=commit
    else
        ref=$(git -C "$repo" describe --tags --abbrev=0 origin/main 2>/dev/null || true)
        kind=tag
    fi
    [ -n "$ref" ] || return 1
    verify "$kind" "$ref" || { echo "Not trusted: $ref is not signed by a trusted key (${CLAVE_SIGNERS[*]})." >&2; return 1; }
    git -C "$repo" merge-base --is-ancestor HEAD "$ref" 2>/dev/null \
        || { echo "Not updating: $ref is older than the installed release." >&2; return 1; }
    echo "$ref"
}
