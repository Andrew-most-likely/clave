# Security

The hardening layer (installed by default, skipped with `install.sh --no-harden`) and the root helpers used by System
Settings (`/usr/local/bin/clave-admin`, `clave-lid`, `clave-usb`, run through polkit) run as root. Please report
problems in them privately through GitHub's "Report a vulnerability" button on the Security tab, not in a public
issue.

`clave-admin` runs without a password for the active local session. It only sets the battery charge limit and the
login screen pictures, accepts only the arguments listed in its header and checks each one. Root never opens a path
the user chose and never decodes a picture. Any way to make it do something else is a vulnerability.

<details>
<summary>Updates and signing</summary>

`setup.sh` and `clave-update` install only release tags (or, with `--main`, commits) signed by the project key. The
key ships in `~/.local/share/clave/allowed_signers`, so a signed release can bring a new key. Keys you add to
`~/.config/clave/allowed_signers` are trusted too. An update never moves to a release older than the installed one.

</details>

<details>
<summary>Known trade-offs</summary>

- The installer builds a few AUR packages (`packages/*-aur.txt`) with `--noconfirm`, so their build scripts are not
  shown for review. Install them yourself first if you want to read them.
- USBGuard lets your account list and watch USB devices. Allowing or blocking one goes through `clave-usb`, which
  asks for the password.

</details>
