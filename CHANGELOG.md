# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `<CHANGES>` block of the plugin `.plg` mirrors the released entries below.

## [Unreleased]

### Added
- Auto-unlock the encrypted Unraid array/pools at boot via clevis + a remote tang server,
  using the supported `event/starting` hook (no cryptsetup shim).
- Seal the array passphrase as a tang-encrypted JWE (no LUKS header is modified); recover it
  at boot into a RAM-only `/root/keyfile` that is shredded once the array mounts.
- webGUI (Settings → Clevis Auto-Unlock): seal / forget, pre-reboot dry-run test, tang health
  monitor, and key rotation — all server-side, no terminal needed.
- Tang signing-key thumbprint pinning with change/MITM detection; safe fallback to the manual
  passphrase prompt if tang is unreachable.
- Bundled jose 15, luksmeta 10, clevis 23 built from SHA-256-pinned sources in digest-pinned
  Slackware containers (Unraid v6 + v7 ABIs).
- CI/CD: SHA-pinned GitHub Actions, SHA-256 + cosign keyless signatures + SLSA build provenance,
  and a scheduled supply-chain drift check.
