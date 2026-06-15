# Architecture

## Components

```
src/clevis.auto.unlock/
  install/                 doinst.sh / douninst.sh / slack-desc   (Slackware package hooks)
  usr/local/emhttp/plugins/clevis.auto.unlock/
    ClevisAutoUnlock.page  webGUI settings + dashboard (Settings menu)
    include/*.php          backend endpoints (POST-guarded; CSRF enforced by Unraid's gate; run scripts as root)
    scripts/*.sh           all logic (also unit-testable off-Unraid)
    event/{starting,started,stopping}/   Unraid array-lifecycle hooks
    pkgs/                  bundled jose/luksmeta/clevis .txz (added at package time)
    default.cfg            initial config.json
```

Configuration lives at `/boot/config/plugins/clevis.auto.unlock/config.json`
(tang URL, pinned thumbprint, enabled flag, unlock mode, network timeout — no secrets).
The sealed passphrase is a tang-encrypted JWE at `.../secret.jwe`.

## Responsibilities

| Unit | Does | Depends on |
|---|---|---|
| `lib-common.sh` | constants, config read, device discovery, tang/thp helpers, notify, keyfile wipe | jq, jose, curl, cryptsetup |
| `derive-key.sh` | boot: `clevis decrypt` the sealed passphrase → stage `/root/keyfile` | lib-common, clevis |
| `seal.sh` / `forget.sh` | seal/remove the passphrase JWE (verifies it opens every device first) | lib-common, clevis, cryptsetup |
| `test-unlock.sh` | dry-run: decrypt + confirm it opens every device, no activation | lib-common, clevis, cryptsetup |
| `health-check.sh` | tang reachable + pinned thumbprint still advertised; notify on change (cron) | lib-common |
| `rotate.sh` | re-seal the passphrase to the current tang key | lib-common, clevis |
| `go-hook.sh` | manage the optional early-boot snippet in `/boot/config/go` | lib-common |
| `include/*.php` | thin, POST-guarded HTTP layer that calls the scripts | helpers.php |

The PHP layer never contains unlock logic — it validates input, requires POST (so Unraid's
global CSRF gate has run), and shells out to the scripts with an argv array (no shell) and the
passphrase on stdin. CSRF itself is enforced once, globally, by Unraid's auto_prepend.

## Boot unlock flow

See [boot-flow.md](boot-flow.md). In short: at the `starting` event the plugin
`clevis decrypt`s the sealed passphrase to `/root/keyfile` (tmpfs); Unraid's native
start unlocks all devices with that one shared key; the `started` hook shreds the
keyfile. No LUKS header is modified, so the user's passphrase always remains as recovery.

## Dependency build

`jose`, `luksmeta` and `clevis` are built from sources pinned in `deps.lock` inside
digest-pinned `vbatts/slackware` containers — `15.0` (OpenSSL 1.1 → Unraid v6) and
`current` (OpenSSL 3 → Unraid v7). `jansson` is statically linked into `libjose` so
the shipped jose has no external libjansson dependency. `doinst.sh` selects the
correct ABI set at install time by detecting `/lib64/libcrypto.so.*`.
