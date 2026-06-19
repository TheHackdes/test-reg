#!/usr/bin/env bash
# KasmVNC server. Oracle 8 RPM is RHEL8-compatible (works on Rocky 8).
# Requires KASMVNC_VERSION and KASMVNC_RPM in the environment.
set -euo pipefail

: "${KASMVNC_VERSION:?KASMVNC_VERSION required}"
: "${KASMVNC_RPM:?KASMVNC_RPM required}"

curl -fsSL -o /tmp/kasmvnc.rpm \
    "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/${KASMVNC_RPM}"
dnf -y install /tmp/kasmvnc.rpm
rm -f /tmp/kasmvnc.rpm
