# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's **"Report a vulnerability"** (Security
Advisories) on this repository rather than opening a public issue. We aim to acknowledge reports
within 7 days.

## Supported versions

The latest released version on the `main` branch is supported. Pre-release `develop` builds are
not supported for production use.

## Threat model

This plugin automates recovery of a LUKS passphrase via clevis + a remote tang server (NBDE). The
design assumes:

- **Disk theft (offline attacker):** disks removed from the server remain encrypted; the key
  cannot be recovered without contacting the bound tang server. The key is never stored at rest on
  the server.
- **Network attacker / rogue tang:** the tang key thumbprint (`thp`) is pinned at bind time and
  verified at every unlock. A changed advertisement aborts the auto-unlock and raises an alert,
  mitigating MITM / tang-impersonation.
- **Running-system attacker (root):** out of scope — a compromised running root can already read
  mounted data. The plugin minimises exposure by keeping the recovered passphrase in RAM only and
  shredding it immediately after the array mounts.
- **Tang loss / DR:** a verified recovery passphrase is required before binding and is never
  removed, so the array can always be unlocked manually. See [`docs/recovery.md`](docs/recovery.md).

## Handling of secrets

- The recovered passphrase lives only in `/root/keyfile` (tmpfs / RAM), mode `0600`, and is
  `shred -u`'d at the `started`/`stopping` events. It is never written to `/boot` or any persistent
  store, and never logged.
- When binding from the webGUI, the user-supplied passphrase is passed to `clevis`/`cryptsetup`
  via **stdin only** — never as a process argument (so it never appears in `ps`/logs) and never in
  the audit log.
- Configuration stored at `/boot/config/plugins/clevis.auto.unlock/config.json` contains only the
  tang URL, pinned thumbprint, and non-secret options.

## Supply chain

- Bundled dependencies (clevis, jose, luksmeta) are built from pinned upstream sources whose
  SHA-256 hashes are recorded in [`deps.lock`](deps.lock) and verified at build time.
- Release artifacts are published with SHA-256 checksums, a Sigstore **cosign keyless** signature,
  and **SLSA build provenance** attestation. See [`docs/verifying-releases.md`](docs/verifying-releases.md).
- GitHub Actions are pinned to commit SHAs and run with least-privilege permissions.
