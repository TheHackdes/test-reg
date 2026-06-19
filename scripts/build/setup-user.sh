#!/usr/bin/env bash
# Local fallback user (kasm-user, uid 1000) + startup dir.
# kasmvnc-cert group (created by the KasmVNC RPM) grants read access to the
# self-signed TLS cert at /etc/pki/tls/private/kasmvnc.pem.
# Run AFTER install-kasmvnc.sh (group must exist).
set -euo pipefail

: "${STARTUPDIR:?STARTUPDIR required}"

useradd -m -u 1000 -s /bin/bash kasm-user
usermod -a -G kasmvnc-cert kasm-user
mkdir -p "${STARTUPDIR}"
chown -R 1000:0 "${STARTUPDIR}" /home/kasm-user
