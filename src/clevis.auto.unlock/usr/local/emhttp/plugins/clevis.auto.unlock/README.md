# Clevis Auto-Unlock (plugin payload)

Installed at `/usr/local/emhttp/plugins/clevis.auto.unlock/`.

- `ClevisAutoUnlock.page` — Settings → Clevis Auto-Unlock (config + device dashboard)
- `include/*.php` — CSRF-checked backend endpoints (run the scripts as root)
- `scripts/*.sh` — all logic; `lib-common.sh` is the shared library
- `event/*` — Unraid array-lifecycle hooks (stage key at `starting`, wipe at `started`)
- `pkgs/` — bundled jose/luksmeta/clevis packages (installed by `install/doinst.sh`)

Configuration is stored at `/boot/config/plugins/clevis.auto.unlock/config.json`.

Full documentation: https://github.com/CMGeldenhuys/unraid-clevis
