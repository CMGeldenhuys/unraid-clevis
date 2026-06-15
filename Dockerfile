# syntax=docker/dockerfile:1
#
# Builds the bundled dependency packages (jose, luksmeta, clevis) for one Unraid
# ABI variant, from the pinned sources in deps.lock. The toolchain comes from the
# official Slackware mirror (build-only); shipped artifacts are built from
# hash-verified upstream source.
#
#   --build-arg BASE=docker.io/vbatts/slackware:current@sha256:...   (v7 / OpenSSL 3)
#   --build-arg BASE=docker.io/vbatts/slackware:15.0@sha256:...      (v6 / OpenSSL 1.1)
#   --build-arg VARIANT=unraid-v7|unraid-v6
#   --target export --output type=local,dest=./pkgs   (jose/luksmeta/clevis, per variant)
ARG BASE=docker.io/vbatts/slackware:current

FROM ${BASE} AS toolchain
# Slackware has no automatic dependency resolution, so the toolchain set is explicit.
# Tolerate name differences across releases (pkgconf vs pkg-config) then assert the
# critical tools are present.
RUN set -e; \
    slackpkg -batch=on -default_answer=y update; \
    slackpkg -batch=on -default_answer=y upgrade slackpkg || true; \
    slackpkg -batch=on -default_answer=y upgrade-all || true; \
    slackpkg -batch=on -default_answer=y install \
      gcc gcc-g++ binutils make glibc kernel-headers flex bison gettext \
      gmp mpfr mpc isl zstd gc lzlib guile libunistring libffi readline ncurses gdbm \
      python3 meson ninja pkgconf pkg-config \
      zlib openssl cryptsetup lvm2 popt json-c argon2 libgpg-error libgcrypt util-linux eudev curl \
      autoconf automake libtool m4 || true; \
    for t in gcc make meson ninja pkg-config strip file ar; do \
        command -v "$t" >/dev/null || { echo "missing build tool: $t" >&2; exit 1; }; \
    done; \
    rm -rf /var/cache/packages/* 2>/dev/null || true

FROM toolchain AS builder
ARG VARIANT=unraid-v7
COPY deps.lock /deps.lock
COPY build /build
RUN VARIANT="${VARIANT}" OUTPUT=/out SRCDIR=/build/sources \
    bash /build/build-packages.sh

# Clean stage that contains only the built dependency packages.
FROM scratch AS export
COPY --from=builder /out/ /

# ---------------------------------------------------------------------------
# Plugin packaging stage. Bundles the pre-built dependency packages (from ./pkgs,
# produced by earlier `--target export` runs of this Dockerfile) into the plugin
# payload, makepkg's the plugin .txz, and renders the .plg. Uses only pkgtools
# from the base image (no toolchain needed), so it is fast.
FROM ${BASE} AS plugin
ARG PLUGIN_VERSION=0.0.0
ARG BUILD=1
ARG GITHUB_REPOSITORY=CMGeldenhuys/unraid-clevis
ARG RELEASE_TAG=
COPY src /src
COPY pkgs /deps
# Slackware package versions may not contain '-' (the field separator), so a semver
# pre-release like v0.1.0-alpha.1 becomes package version 0.1.0_alpha.1.
RUN set -e; \
    ver="${PLUGIN_VERSION#v}"; ver="${ver//-/_}"; \
    payload=/src/clevis.auto.unlock; \
    pkgsdir="$payload/usr/local/emhttp/plugins/clevis.auto.unlock/pkgs"; \
    install -d "$pkgsdir"; \
    cp /deps/jose-*.txz /deps/luksmeta-*.txz /deps/clevis-*.txz "$pkgsdir/"; \
    chmod +x "$payload"/usr/local/emhttp/plugins/clevis.auto.unlock/scripts/*.sh; \
    find "$payload"/usr/local/emhttp/plugins/clevis.auto.unlock/event -type f -exec chmod +x {} +; \
    chmod +x "$payload"/install/*.sh; \
    mkdir -p /out; \
    ( cd "$payload" && /sbin/makepkg -l y -c n \
        "/out/clevis.auto.unlock-${ver}-x86_64-${BUILD}.txz" ); \
    PKG_DIR=/out GITHUB_REPOSITORY="${GITHUB_REPOSITORY}" RELEASE_TAG="${RELEASE_TAG}" \
        bash /src/clevis.auto.unlock.plg.tmpl-update.sh; \
    ( cd /out && for f in *.txz; do sha256sum "$f" > "$f.sha256"; done ); \
    ls -l /out

FROM scratch AS plugin-export
COPY --from=plugin /out/ /
