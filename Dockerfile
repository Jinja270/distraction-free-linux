# ==============================================================================
# Distraction-Free Linux (Study OS) - Multi-Stage Containerized Build Engine
# File: Dockerfile
# Base OS: Ubuntu 24.04 LTS (Noble Numbat)
# Purpose: Reproducible containerized build environment for compiling bootable
#          hybrid UEFI/BIOS Distraction-Free Linux live ISO images.
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Toolchain & Build Dependencies Base
# ------------------------------------------------------------------------------
FROM ubuntu:24.04 AS base

LABEL maintainer="Distraction-Free Linux Team"
LABEL description="Containerized Build Environment for Distraction-Free Linux ISO"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install core build dependencies, kernel & bootloader assemblers, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    dosfstools \
    isolinux \
    syslinux-common \
    python3 \
    python3-pip \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gtk-3.0 \
    zstd \
    curl \
    wget \
    tar \
    sudo \
    make \
    git \
    rsync \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set up staging directories
RUN mkdir -p /build /opt/dfl

WORKDIR /build

# ------------------------------------------------------------------------------
# Stage 2: Automated Verification & E2E Test Suite
# ------------------------------------------------------------------------------
FROM base AS test

# Copy repository sources into test stage
COPY . /build

# Validate bash script syntax across all build scripts
RUN bash -n build_iso.sh && \
    for script in scripts/*.sh; do \
        bash -n "$script" || exit 1; \
    done

# Run complete 95-test E2E verification suite
RUN python3 tests/e2e/run_all_tests.py

# Run network hardening verification suite
RUN python3 scripts/verify_blocking.py

# ------------------------------------------------------------------------------
# Stage 3: Master ISO Release Builder
# ------------------------------------------------------------------------------
FROM base AS builder

WORKDIR /build

# Copy repository sources
COPY . /build

# Ensure execution bits on all build scripts
RUN chmod +x build_iso.sh scripts/*.sh

# Staging volume for output ISO and logs
VOLUME ["/opt/dfl"]

# Default entrypoint executes master 10-stage ISO build pipeline
ENTRYPOINT ["/bin/bash", "/build/build_iso.sh"]
CMD ["--workdir", "/opt/dfl", "--output", "/opt/dfl/distraction-free-linux.iso"]
