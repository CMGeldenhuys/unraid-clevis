# Boot unlock flow & event timing

## The model

Unraid uses a **single shared key** for every encrypted device. `clevis luks bind`
cannot help here: it stores a *random per-device* key, not the user's passphrase. So
this plugin instead **seals the user's actual passphrase** as a clevis+tang JWE
(`/boot/config/plugins/clevis.auto.unlock/secret.jwe`) and recovers *that* at boot.
No LUKS header is ever modified.

## The flow (default: event-hook mode)

```
power on
  emhttpd starts → fires events: startup, driver_loaded
  (array set to auto-start) → fires: starting
     └─ event/starting/10-derive-key  →  scripts/derive-key.sh
          • wait (bounded, with per-request curl timeouts) for tang to respond
          • clevis decrypt < secret.jwe > /root/keyfile     (the shared passphrase)
          • if disks.ini is available: confirm the key opens EVERY encrypted device
  emhttpd reads /root/keyfile and luksOpen's every device with that one key
  array mounts → fires: array_started, disks_mounted, started
     └─ event/started/90-wipe-key  →  shred -u /root/keyfile
```

`clevis decrypt` verifies the tang advertisement signature against the thumbprint
sealed into the JWE, so a rogue or MITM'd tang fails closed. On *any* failure the
hook writes no keyfile, so Unraid falls back to the manual passphrase prompt.

## Event timing — validate on real hardware

The default mode relies on the `starting` event running **before** emhttpd reads
`/root/keyfile` during unattended auto-start. This is the supported plugin mechanism
and matches established community auto-unlock setups, but confirm it on your build:

1. Seal the passphrase, enable auto-unlock, set the array to start automatically.
2. Reboot — the array should unlock with no input.
3. Check `/var/log/syslog` for `clevis.auto.unlock` lines around array start and
   confirm `/root/keyfile` is gone after the array mounts.

If it does **not** auto-unlock unattended, switch **Unlock mode** to *Early boot (go
script)*. That stages the key from `/boot/config/go` **before** emhttpd launches
(provably early). In go mode `disks.ini` does not exist yet, so derive-key skips the
per-device validation and trusts the clevis decrypt; Unraid still does the opening.

## Why not replace cryptsetup?

The prior art replaced `/usr/sbin/cryptsetup` with a shim to intercept `luksOpen`
(needed because it used per-device clevis keys). That hooks a security-critical
binary and breaks silently across Unraid upgrades. Sealing the shared passphrase
lets us use only supported integration points and touch no system binaries.
