# Clevis Auto-Unlock — build orchestration.
#
#   make all                 fetch sources, build deps (v6+v7), package the plugin
#   make sources             download + verify pinned sources (deps.lock)
#   make verify              re-verify pinned source hashes
#   make deps                build jose/luksmeta/clevis for both Unraid ABIs
#   make plugin              assemble + makepkg the plugin .txz and render the .plg
#   make lint                shellcheck + xmllint (uses docker)
#   make clean               remove build outputs
#
# Base images are pinned by digest in deps.lock (single source of truth).

SHELL := /usr/bin/env bash
DOCKER ?= docker
PLATFORM ?= linux/amd64

V6_BASE := $(shell awk '$$1=="IMAGE" && $$2 ~ /:15\.0/    {print $$2"@"$$3}' deps.lock)
V7_BASE := $(shell awk '$$1=="IMAGE" && $$2 ~ /:current/  {print $$2"@"$$3}' deps.lock)

# Plugin version: a git tag (vX.Y.Z) when present, else 0.0.0 for dev builds.
PLUGIN_VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)
BUILD ?= 1
GITHUB_REPOSITORY ?= CMGeldenhuys/unraid-clevis
RELEASE_TAG ?=

PKGS_DIR := pkgs
RELEASE_DIR := release

.PHONY: all sources verify deps deps-v6 deps-v7 plugin lint clean

all: sources deps plugin

sources:
	bash build/fetch-sources.sh

verify:
	bash build/verify-deps.sh

deps: deps-v6 deps-v7

deps-v6: sources
	@echo ">> building dependencies for Unraid v6 (OpenSSL 1.1) using $(V6_BASE)"
	$(DOCKER) build --platform $(PLATFORM) \
	  --build-arg BASE="$(V6_BASE)" --build-arg VARIANT=unraid-v6 \
	  --target export --output type=local,dest=$(PKGS_DIR) -f Dockerfile .

deps-v7: sources
	@echo ">> building dependencies for Unraid v7 (OpenSSL 3) using $(V7_BASE)"
	$(DOCKER) build --platform $(PLATFORM) \
	  --build-arg BASE="$(V7_BASE)" --build-arg VARIANT=unraid-v7 \
	  --target export --output type=local,dest=$(PKGS_DIR) -f Dockerfile .

# Package the plugin (bundles the built deps) and render the .plg.
plugin:
	@test -n "$$(ls $(PKGS_DIR)/*_unraid-v6.txz 2>/dev/null)" || { echo "missing v6 deps; run 'make deps'"; exit 1; }
	@test -n "$$(ls $(PKGS_DIR)/*_unraid-v7.txz 2>/dev/null)" || { echo "missing v7 deps; run 'make deps'"; exit 1; }
	@echo ">> packaging plugin $(PLUGIN_VERSION) (repo $(GITHUB_REPOSITORY))"
	$(DOCKER) build --platform $(PLATFORM) \
	  --build-arg BASE="$(V7_BASE)" \
	  --build-arg PLUGIN_VERSION="$(PLUGIN_VERSION)" \
	  --build-arg BUILD="$(BUILD)" \
	  --build-arg GITHUB_REPOSITORY="$(GITHUB_REPOSITORY)" \
	  --build-arg RELEASE_TAG="$(RELEASE_TAG)" \
	  --target plugin-export --output type=local,dest=$(RELEASE_DIR) -f Dockerfile .
	@echo ">> release artifacts:" && ls -l $(RELEASE_DIR)

lint:
	$(DOCKER) run --rm -v "$$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:stable -x -S warning \
	  src/clevis.auto.unlock/usr/local/emhttp/plugins/clevis.auto.unlock/scripts/*.sh \
	  src/clevis.auto.unlock/usr/local/emhttp/plugins/clevis.auto.unlock/event/*/* \
	  src/clevis.auto.unlock/install/*.sh build/*.sh build/slackbuilds/*/*.SlackBuild
	$(DOCKER) run --rm -v "$$PWD:/mnt:ro" -w /mnt nixery.dev/libxml2 \
	  xmllint --noout src/clevis.auto.unlock.plg.tmpl || true

clean:
	rm -rf $(PKGS_DIR) $(RELEASE_DIR) build/sources
