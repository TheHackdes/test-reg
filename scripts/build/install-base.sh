#!/usr/bin/env bash
# Base OS layer: enable repos, locale, common CLI tools.
set -euo pipefail

dnf -y update
dnf -y install epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools 2>/dev/null || true
dnf -y install \
    bash ca-certificates curl tar which sudo vim-minimal procps-ng \
    glibc-langpack-en glibc-langpack-fr openssl hostname \
    dbus-x11 xterm xorg-x11-server-utils
