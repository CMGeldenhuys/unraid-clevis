# Contributing

## Branching (git-flow)

- `main` — released code only; tags `vX.Y.Z` trigger the release workflow.
- `develop` — integration branch; base your work here.
- `feature/*`, `release/*`, `hotfix/*` — short-lived branches merged back via PR.

## Building locally

Requires Docker (or Podman) — the dependency packages are built inside pinned
Slackware containers.

```sh
make sources   # download + verify pinned sources (deps.lock)
make deps      # build jose/luksmeta/clevis for Unraid v6 + v7
make plugin    # package the plugin .txz and render the .plg  (-> ./release)
make lint      # shellcheck + xmllint
```

## Conventions

- Shell scripts must pass `shellcheck -x -S warning`.
- All plugin logic lives in `scripts/*.sh`; the PHP layer only validates input,
  enforces CSRF, and shells out (argv array; passphrase on stdin).
- Never log, echo, or pass a passphrase as a process argument.
- Bump `deps.lock` only with verified upstream SHA-256 hashes.
- Pin every GitHub Action to a commit SHA.

## Security

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).
