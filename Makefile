# ==============================================================================
# Distraction-Free Linux (Study OS) - Automated Build & Test Makefile
# File: Makefile
# Targets: all, bootstrap, configure, desktop, tools, lockdown, squashfs, iso,
#          clean, test, verify, lint, docker-build, docker-run, help
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Build parameters & customizable overrides
WORKDIR        ?= /opt/dfl
ROOTFS         ?= $(WORKDIR)/chroot
ISO_STAGING    ?= $(WORKDIR)/iso
CASPER_DIR     ?= $(ISO_STAGING)/casper
OUTPUT_ISO     ?= $(WORKDIR)/distraction-free-linux.iso
VOLUME_ID      ?= DFL_STUDY_OS
PYTHON         ?= python3
DOCKER_IMAGE   ?= distraction-free-linux-builder:latest

# Color declarations for terminal output
CLR_CYN := \033[1;36m
CLR_GRN := \033[1;32m
CLR_YLW := \033[1;33m
CLR_RST := \033[0m

.PHONY: all bootstrap configure desktop tools lockdown squashfs iso clean test verify lint docker-build docker-run help

## all: Execute the end-to-end 10-stage automated ISO build pipeline
all:
	@echo -e "$(CLR_CYN)===> Executing Master 10-Stage ISO Build Pipeline...$(CLR_RST)"
	sudo ./build_iso.sh --workdir "$(WORKDIR)" --output "$(OUTPUT_ISO)" --volume-id "$(VOLUME_ID)"

## bootstrap: Execute Stage 3 - debootstrap minimal Ubuntu 24.04 noble rootfs
bootstrap:
	@echo -e "$(CLR_CYN)===> [Stage 3] Bootstrapping Base Ubuntu 24.04 noble Rootfs...$(CLR_RST)"
	sudo bash scripts/01_bootstrap.sh "$(ROOTFS)"

## configure: Execute Stage 4 - configure base system, kernel, casper, locales, timezone, network, and study user
configure:
	@echo -e "$(CLR_CYN)===> [Stage 4] Configuring Kernel, Casper, Locales, Network, and Study User...$(CLR_RST)"
	sudo bash scripts/02_configure_system.sh "$(ROOTFS)"

## desktop: Execute Stage 5 - install minimal XFCE desktop, LightDM autologin, and mute notifications
desktop:
	@echo -e "$(CLR_CYN)===> [Stage 5] Installing Minimal XFCE Desktop & Muting Notification Noise...$(CLR_RST)"
	sudo bash scripts/03_install_desktop.sh "$(ROOTFS)"

## tools: Execute Stage 6 - install study tooling suite (Anki, Evince, Zathura, FocusWriter, Markdown, Pomodoro)
tools:
	@echo -e "$(CLR_CYN)===> [Stage 6] Installing Dedicated Study Tooling Suite...$(CLR_RST)"
	sudo bash scripts/04_install_study_tools.sh "$(ROOTFS)"

## lockdown: Execute Stage 7 - apply /etc/hosts sinkhole, nftables firewall, sudoers, and Firefox policies
lockdown:
	@echo -e "$(CLR_CYN)===> [Stage 7] Applying Distraction Blocking & Browser Hardening Lockdown...$(CLR_RST)"
	sudo bash scripts/05_apply_lockdown.sh "$(ROOTFS)"

## squashfs: Execute Stage 9 - compress rootfs into high-density zstd filesystem.squashfs
squashfs:
	@echo -e "$(CLR_CYN)===> [Stage 9] Compressing Rootfs into High-Density zstd SquashFS...$(CLR_RST)"
	sudo bash scripts/06_build_squashfs.sh "$(ROOTFS)" "$(CASPER_DIR)"

## iso: Execute Stage 10 - assemble bootable hybrid UEFI/BIOS live ISO with xorriso
iso:
	@echo -e "$(CLR_CYN)===> [Stage 10] Assembling Bootable Hybrid Live ISO Image...$(CLR_RST)"
	sudo bash scripts/07_build_iso.sh "$(ISO_STAGING)" "$(OUTPUT_ISO)" "$(VOLUME_ID)"

## test: Run complete opaque-box E2E test suite (Tiers 1-4, 95 assertions)
test:
	@echo -e "$(CLR_CYN)===> Running Complete E2E Test Suite (Tiers 1-4)...$(CLR_RST)"
	$(PYTHON) tests/e2e/run_all_tests.py

## verify: Run automated network hardening & distraction-blocking verification
verify:
	@echo -e "$(CLR_CYN)===> Running Network Hardening & Distraction Verification Suite...$(CLR_RST)"
	$(PYTHON) scripts/verify_blocking.py

## lint: Validate bash script syntax across all build and configuration scripts
lint:
	@echo -e "$(CLR_CYN)===> Validating Bash Script Syntax with bash -n...$(CLR_RST)"
	@bash -n build_iso.sh && echo "  [OK] build_iso.sh syntax valid"
	@for script in scripts/*.sh; do \
		bash -n "$$script" && echo "  [OK] $$script syntax valid"; \
	done
	@echo -e "$(CLR_GRN)All shell scripts passed syntax validation!$(CLR_RST)"

## clean: Remove all compiled build artifacts, chroot rootfs, and temporary caches
clean:
	@echo -e "$(CLR_YLW)===> Cleaning workspace and temporary build artifacts...$(CLR_RST)"
	sudo rm -rf "$(WORKDIR)"
	sudo rm -f "$(OUTPUT_ISO)" "$(OUTPUT_ISO).sha256"
	@echo -e "$(CLR_GRN)Clean complete.$(CLR_RST)"

## docker-build: Build reproducible multi-stage Docker build environment
docker-build:
	@echo -e "$(CLR_CYN)===> Building Multi-Stage Docker Container ($(DOCKER_IMAGE))...$(CLR_RST)"
	docker build -t $(DOCKER_IMAGE) .

## docker-run: Compile ISO inside reproducible Docker container
docker-run:
	@echo -e "$(CLR_CYN)===> Running ISO Build inside Container ($(DOCKER_IMAGE))...$(CLR_RST)"
	docker run --rm --privileged \
		-v "$(PWD)/output:/opt/dfl" \
		$(DOCKER_IMAGE)

## help: Display this summary of available targets
help:
	@echo -e "$(CLR_CYN)Distraction-Free Linux (Study OS) - Build System$(CLR_RST)"
	@echo -e "Available Targets:"
	@sed -n 's/^## \([a-zA-Z0-9_-]*\): \(.*\)/  \o033[1;32m\1\o033[0m\t\2/p' $(MAKEFILE_LIST) | expand -t 16
