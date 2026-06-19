#!/usr/bin/env bash
# Drop package caches to shrink the image layer.
set -euo pipefail

dnf clean all
rm -rf /var/cache/dnf
