# Recovery — unlocking when tang is unavailable

**Your existing LUKS passphrase always works.** Clevis Auto-Unlock never modifies a
LUKS header — it only stores your passphrase, encrypted, as a tang-bound JWE. If the
tang server is down, destroyed, or its key changed, you can always unlock manually
with the same passphrase you set when you encrypted the array.

## If the array does not auto-unlock at boot

1. Open the Unraid webGUI. The array will be stopped, asking for the encryption key.
2. Enter your **original LUKS passphrase** and start the array as normal.
3. Investigate why tang did not respond (see below). Until fixed, the array will
   need the passphrase entered manually at each boot.

This is the deliberate, safe fallback: if the plugin cannot recover the key from
tang, it writes **no** keyfile and lets Unraid prompt you — it never weakens
security silently.

## Common causes

| Symptom | Likely cause | Fix |
|---|---|---|
| "Tang server unreachable" notification | tang host down / network not up in time | start tang; increase **Network wait** in settings; ensure tang is not on this box |
| "Tang key changed!" notification | tang keys were rotated, or a different server answered | if you rotated: **Rotate / re-pin key** in the UI; if not, investigate a possible MITM |
| Auto-unlock never triggers | array not set to start automatically | Settings → Disk Settings → *Enable auto start* = Yes |
| Works manually, not at boot | `starting` event timing on this build | switch **Unlock mode** to *Early boot (go script)* in settings |

## Recover the passphrase from tang manually (CLI)

If the webGUI is unavailable but tang is up, from the Unraid console:

```sh
# decrypt the sealed passphrase straight from tang
clevis decrypt < /boot/config/plugins/clevis.auto.unlock/secret.jwe
```

## Removing the seal

"Forget" in the UI (or simply deleting `secret.jwe`) disables auto-unlock. Because
no LUKS header was ever touched, there is nothing to unbind and your disk encryption
is unchanged — you just enter the passphrase manually at the next boot. Uninstalling
the plugin leaves your encryption entirely intact.

## Back up your LUKS headers

Independent of this plugin, keep an offline backup of each device's LUKS header so
you can recover from header corruption:

```sh
cryptsetup luksHeaderBackup /dev/mdXp1 --header-backup-file mdXp1-luks-header.img
```

Store these backups securely offline — anyone with the header **and** your
passphrase can decrypt the disk.
