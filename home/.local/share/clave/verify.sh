# Signed releases, shared by clave-update and clave-doctor --fetch. Sourced;
# needs $repo (the checkout) and $signers (allowed_signers).

# Updates run code on this machine, so only releases signed by a key in
# $signers are installed or trusted.
verify() {  # verify tag|commit REF
    git -C "$repo" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$signers" \
        "verify-$1" "$2" >/dev/null 2>&1
}

# newest_ref: after a fetch, print the ref an update would move to: the
# upstream branch when the checkout follows one, else the newest release
# tag. Prints nothing and returns 1 when that ref is not signed.
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
    verify "$kind" "$ref" || { echo "Not trusted: $ref is not signed by a key in $signers." >&2; return 1; }
    echo "$ref"
}
