# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `<CHANGES>` block of the plugin `.plg` mirrors the released entries below.

## [Unreleased]

### Added
- Boot-time syslog now records the unlock plainly: an "auto-unlock starting (mode=event, …)" line
  at the array-start hook and a definitive "array unlocked via clevis+tang; staged key wiped"
  confirmation once the array is mounted — previously the only lines were logged before Unraid
  actually opened the devices, so a successful unlock left no clear record. An optional "Verbose
  boot logging" toggle (Settings → config `debug`) adds opt-in per-step/per-device detail for
  troubleshooting; the default stays quiet (net +2 concise lines per unlock).
- Failed Seal / Rotate / Forget operations now leave a `[warning]` line in syslog (the error was
  previously only returned to the webGUI), giving an audit trail for posture-changing actions.

### Changed
- The pinned tang thumbprint in the webGUI is relabelled "tang key fingerprint" and shown truncated
  with an eye toggle to reveal the full value, with a tooltip clarifying it is a public fingerprint
  (not a secret) — avoids the false impression that a secret key is exposed.

### Fixed
- Tang health check no longer falsely flips to "key changed — re-pin" right after sealing/rotating:
  `jose jwk thp` emits no trailing newline, so the `while read` membership loop in
  `cau_thp_advertised` skipped the final (often only) thumbprint and reported `thp-changed`. The
  loop now compares that unterminated last line, so a healthy pinned key reads as `ok`.
- webGUI POSTs (Save/Seal/Test/Rotate/Forget) no longer hang ~60s then 504: the JS now sends
  `application/x-www-form-urlencoded` (URLSearchParams) instead of `multipart/form-data`, which
  deadlocked Unraid's nginx `auth_request` gate — the auth subrequest blocked reading a body it
  never received, timing out before our endpoint ran.
- webGUI POSTs no longer fail with a false "Invalid or missing CSRF token": Unraid's global
  auto_prepend already validates the token on every POST and strips it before plugin code runs,
  so the redundant per-endpoint check could never pass. Endpoints now rely on that gate and only
  enforce POST (so the global CSRF check is guaranteed to have run).
- webGUI backend can no longer hang a php-fpm worker: every script run via `cau_run` is wrapped in a
  hard `timeout` and its output captured via temp files, so a stuck child returns a clean error
  instead of pinning a worker (which previously exhausted the pool and 504'd the whole webGUI).
- webGUI actions (Seal/Test/Save/Rotate/Forget) appeared inert: endpoints now emit strictly clean
  JSON (notices suppressed + output buffer cleaned) and the JS never fails silently (defensive parse
  + `.catch`), with a non-blocking busy state and a result dialog for every action.
- Bundled tools could be "not found" in the webGUI/boot/cron contexts: a complete `PATH` is now
  exported in `lib-common.sh` (and passed to `proc_open`), and the array-start hook sets `PATH` for
  its `jq` call.
- Health-check cron never ran: it's now registered the Unraid way
  (`/boot/config/plugins/<name>/*.cron` + `update_cron`, no username field) instead of `/etc/cron.d`.

### Added
- Live tang server status in the webGUI (not configured / reachable / key-pinned / key-changed /
  unreachable) with a Check button; reachability is shown before sealing.
- Per-field inline help (Unraid Help-button toggle) and hover tooltips on every setting/action.

### Added (initial)
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
