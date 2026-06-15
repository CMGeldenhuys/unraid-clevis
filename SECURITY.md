# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub's **"Report a vulnerability"** (Security
Advisories) on this repository rather than opening a public issue. We aim to acknowledge reports
within 7 days.

## Supported versions

The latest released version on the `main` branch is supported. Pre-release `develop` builds are
not supported for production use.

## Where the sealed secret lives (important tradeoff)

The sealed passphrase (`secret.jwe`) is stored on the Unraid **boot flash** (`/boot`),
not inside a LUKS header. It is a tang-encrypted JWE, so it is **not** a plaintext
secret — recovering the passphrase from it requires contacting the tang server.

The practical consequence: the auto-unlock secret is protected by **"possession of the
boot flash" AND "network access to tang"** — *not* by possession of a data disk. So:

- **Stolen data disk(s) only:** stay encrypted (the JWE is not on them; an attacker
  needs your passphrase). Same as without this plugin.
- **Stolen/cloned boot flash + reachable tang:** the passphrase can be recovered.
  Keep the boot flash physically secure, keep tang on an isolated network the
  attacker cannot reach, and prefer running tang somewhere that is *not* co-located
  with (or stolen alongside) the server.
- **Whole server stolen with tang reachable:** compromised — as with any unattended
  network-unlock scheme. Mitigate by ensuring tang is not reachable from where the
  hardware would end up (e.g. tang on a separate site/VLAN).

If you need the secret to travel with the encrypted disk instead of the flash, do not
use auto-unlock (enter the passphrase manually). Storing the JWE in a LUKS2 token is a
planned future option.

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
- **Tang loss / DR:** the plugin never modifies a LUKS header — it seals a copy of your
  passphrase as a tang-encrypted JWE. Your passphrase is verified to open every device
  before sealing and always remains your manual recovery key. See [`docs/recovery.md`](docs/recovery.md).

## Handling of secrets

- The recovered passphrase lives only in `/root/keyfile` (tmpfs / RAM), mode `0600`, and is
  `shred -u`'d at the `started`/`stopping` events. It is never written to `/boot` or any persistent
  store, and never logged.
- When sealing from the webGUI, the user-supplied passphrase is passed to `clevis`/`cryptsetup`
  via **stdin only** — never as a process argument (so it never appears in `ps`/logs) and never logged.
- `/boot/config/plugins/clevis.auto.unlock/config.json` holds only the tang URL, pinned thumbprint,
  and non-secret options. `secret.jwe` is the passphrase encrypted to tang — not a plaintext secret;
  it is recoverable only by contacting the tang server.

## Supply chain

- Bundled dependencies (clevis, jose, luksmeta) are built from pinned upstream sources whose
  SHA-256 hashes are recorded in [`deps.lock`](deps.lock) and verified at build time.
- Release artifacts are published with SHA-256 checksums, a Sigstore **cosign keyless** signature,
  and **SLSA build provenance** attestation. See [`docs/verifying-releases.md`](docs/verifying-releases.md).
- GitHub Actions are pinned to commit SHAs and run with least-privilege permissions.
