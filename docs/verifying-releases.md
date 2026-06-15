# Verifying releases

Every release is published with three independent integrity controls so you do not
have to trust the author personally. The shipped dependencies are built from sources
pinned by SHA-256 in `deps.lock`, inside Slackware base images pinned by digest. (The
build *toolchain* is installed from the official Slackware mirror at build time, so
the build is reproducible given those pinned base images and sources rather than
bit-for-bit hermetic.)

Release assets:

- `clevis.auto.unlock.plg` — the plugin manifest
- `clevis.auto.unlock-<version>-x86_64-<build>.txz` — the plugin package
- `SHA256SUMS` — SHA-256 of the `.txz` and `.plg`
- `*.cosign.bundle` — Sigstore cosign **keyless** signatures
- SLSA build provenance attestation (attached to the repo, verified with `gh`)

## 1. SHA-256 checksums

```sh
sha256sum -c SHA256SUMS
```

## 2. Cosign keyless signature

Confirms the artifact was signed by this repository's GitHub Actions workflow via
Sigstore (recorded in the public Rekor transparency log — no long-lived keys).

```sh
cosign verify-blob clevis.auto.unlock.plg \
  --bundle clevis.auto.unlock.plg.cosign.bundle \
  --certificate-identity-regexp "^https://github.com/CMGeldenhuys/unraid-clevis/.github/workflows/release.yml@refs/tags/v.*" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

(Repeat for the `.txz`, adjusting the filename.)

## 3. SLSA build provenance

Confirms exactly which workflow, commit and runner produced the artifact.

```sh
gh attestation verify clevis.auto.unlock-<version>-x86_64-<build>.txz \
  --repo CMGeldenhuys/unraid-clevis
```

## Reproducing the build

```sh
git checkout v<version>
make sources   # downloads + verifies pinned sources against deps.lock
make deps      # builds jose/luksmeta/clevis in pinned Slackware containers
make plugin    # repackages the plugin
sha256sum release/clevis.auto.unlock-*.txz
```

The dependency sources are pinned by SHA-256 in `deps.lock`; the Slackware base
images are pinned by digest. The scheduled `verify-deps` workflow re-checks the
upstream sources weekly and alerts on any drift.
