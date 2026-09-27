# Security

The optional hardening layer (`install.sh --harden`) and the root helpers used by System Settings
(`/usr/local/bin/clave-admin`, `clave-lid`, `clave-usb`, run through polkit) run as root. Please report problems in
them privately through GitHub's "Report a vulnerability" button on the Security tab, not in a public issue.

`clave-admin` runs without a password for the active local session. It only accepts the arguments listed in its
header and checks each one. Any way to make it do something else is a vulnerability.
