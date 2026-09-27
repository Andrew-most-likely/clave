# Upstream compatibility

Arch is a rolling release, so Clave cannot pin the versions of the software it depends on. This page is for the
maintainer: how Clave notices that an update broke it, and how users learn whether they need a newer Clave.
Requirements: PROJECT_PLAN.md COMP-5 to COMP-9.

## The daily watch (GitHub)

`.github/workflows/upstream.yml` runs once a day (and by hand from the Actions tab). It runs only on the default
branch.

1. `ci/upstream.sh versions` lists the current version of every package in `packages/*.txt`, the AUR packages, and
   the git repositories in `ci/watched.txt`: `pacman -Sy` and `pacman -Si` in an `archlinux` container (never `-Syu`),
   the AUR RPC, and `git ls-remote`.
2. `ci/upstream.sh diff` compares that list with the last known good one, `manifest.txt` on the orphan branch
   `ci-state`. Users never follow that branch, so its commits are not signed.
3. When a package in `ci/watched.txt` changed, the lint and install jobs of `ci.yml` run.
4. A pass, or a change to other packages only, makes the new list the last known good one. A failure opens one
   issue labelled `upstream-break`, or updates the open one, with the version changes and the failed steps. The
   issue is the signal that Clave needs an update.

About 2 minutes a day, plus about 10 minutes when a watched package changes: well under the 3,000 Actions minutes
of GitHub Pro.

## compat.json

In the repo root, changed only in signed commits. It reaches users inside the checkout that `clave-update` already
verifies, and the installer copies it to `/usr/share/clave/compat.json` for the pacman hook.

```json
{
  "clave": "1.1.1",
  "tested": { "1.1.1": { "hyprland": "0.56.2-3", "quickshell": "0.3.1-1" } },
  "breaks": [
    { "package": "hyprland", "from": "0.57.0", "fixed_in_clave": "1.1.2",
      "issue": "https://github.com/Andrew-most-likely/clave/issues/12" }
  ]
}
```

- `clave`: the release this checkout is. Bump it with every release.
- `tested`: per release, the version of each package in `ci/watched.txt` that the release was checked with
  (`pacman -Q` on the test machine). `tests/compat-test.sh` fails when a watched package has no entry.
- `breaks`: a package version from which Clave misbehaves. `fixed_in_clave` is the first release that works with
  it, or `null` while there is no fix; `issue` links the `upstream-break` issue.

Results, from `clave-compat` (used by `clave-doctor` and the hook):

| Result | When |
|---|---|
| OK | Not newer than the tested version, and no known break applies |
| Untested | Newer than tested, no known break |
| Update Clave | A known break that a later release fixes: run `clave-update` |
| Broken | A known break with no fix yet: the issue link |

## At each release

1. Set `clave` to the new version and add a `tested` entry from `pacman -Q` on the machine the release was
   checked on.
2. For each `upstream-break` issue fixed in this release, add or update its `breaks` entry with `fixed_in_clave`.
3. Sign the commit and the tag. `clave-doctor --fetch` on older installs now reads the new known breaks.

## On the user's machine

- `clave-doctor`: local checks and the packages against the local `compat.json`, no network. `--fetch` fetches the
  repo, checks the newest release's signature with the same `verify()` as `clave-update` (`verify.sh`), and adds
  that release's known breaks.
- `/etc/pacman.d/hooks/clave-doctor.hook`: after a transaction that changes a watched package, runs the root-owned
  copy `/usr/local/lib/clave/clave-compat --hook`. It prints warnings and never stops the transaction. For Update
  and Broken it writes `/var/lib/clave/compat-notice`; the shell shows it once at the next login.
- `install.sh --update` refreshes the root-owned copies when a release changed them (`sudo scripts/system.sh
  compat`, from a terminal only).

## Not done: a screenshot check on GitHub

Phase 8 step 6 tried starting Hyprland with the headless backend and software rendering, as on a runner without a
GPU. On the test VM, a second Hyprland started that way from SSH exited without writing a log, so it is not reliable
yet. Until it is, check the look in the desktop VM before each release: `tests/vm-desktop.py start`, then
`tests/vm-desktop.py shot NAME` for each window.
