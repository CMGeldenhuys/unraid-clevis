# Clevis Auto-Unlock for Unraid

Automatically unlock your encrypted Unraid array and pools at boot using
[clevis](https://github.com/latchset/clevis) bound to a remote
[tang](https://github.com/latchset/tang) server — no passphrase typed at the console, and **no
encryption key stored on the server**.

> **Status: in development.** Not yet released. See
> [`docs/`](docs/) and the [CHANGELOG](CHANGELOG.md).

## Why

Unraid's LUKS encryption normally needs a human to type the passphrase (or a plaintext keyfile
left on the USB stick) at every boot. Network-Bound Disk Encryption (NBDE) with clevis + tang
solves this: the disk key is sealed so it can only be recovered by talking to a tang server on
your network. Steal the disks alone and they stay encrypted; the tang server never sees the key.

This plugin does that the **supported** way — via Unraid's array-start event hooks — and rolls the
one-time setup into the webGUI so you never have to drop to a root shell.

## How it differs from prior art

This project is a from-scratch reimplementation inspired by
[`unraid-network-disk-unlock`](https://github.com/greycubesgav/unraid-network-disk-unlock), with a
deliberately different, hardened design:

| Concern | Prior tool | This plugin |
|---|---|---|
| Unlock mechanism | Replaces `/usr/sbin/cryptsetup` with a shim | Unraid `event/starting` hook → native unlock (no binary replacement) |
| Setup | Manual `sudo setup.sh` in a terminal | Server-side from the webGUI |
| Artifact integrity | MD5 | SHA-256 + cosign keyless signature + SLSA provenance |
| Base image | Community/stale | `vbatts/slackware` (pinned by digest) |
| Recovery | Manual | Passphrase verified to open every device before sealing; never removed |
| Key thumbprint | Trust-on-first-use | Pinned `thp`, alerted on change |

## Security model (short version)

- The recovered passphrase exists only in RAM (`/root` is tmpfs), mode `0600`, and is `shred`'d
  immediately after the array starts. It is **never** written to `/boot`.
- The tang key thumbprint is pinned at bind time; a changed advertisement raises an alert.
- If tang is unreachable at boot, the plugin does nothing and Unraid falls back to its normal
  manual passphrase prompt — it never weakens security silently.
- Your existing LUKS passphrase is kept as a recovery key and is never removed.
- **Tradeoff:** the sealed passphrase lives (tang-encrypted) on the boot flash, so the
  auto-unlock secret is protected by *possession of the boot flash* **and** *network
  access to tang* — keep tang on an isolated network and the flash physically secure.
  See [SECURITY.md](SECURITY.md#where-the-sealed-secret-lives-important-tradeoff).

See [SECURITY.md](SECURITY.md) and [`docs/recovery.md`](docs/recovery.md).

## Requirements

- Unraid 6.12.0 or newer.
- An encrypted array/pool.
- A reachable tang server **not** hosted on the Unraid box itself.

## License

[GPL-3.0-or-later](LICENSE) — matching clevis, jose, and tang upstream.
