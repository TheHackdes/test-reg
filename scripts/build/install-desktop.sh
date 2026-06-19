#!/usr/bin/env bash
# XFCE desktop + X server runtime deps.
# KasmVNC's Xvnc needs XKB data (xkeyboard-config) + xkbcomp (xorg-x11-xkb-utils)
# + base fonts, else it fails keyboard init and exits -> "xrdb: Connection
# refused" / "Cannot open display". mesa-dri-drivers gives software GL.
set -euo pipefail

dnf -y install \
    xfce4-session xfwm4 xfdesktop xfce4-panel xfce4-terminal \
    xkeyboard-config xorg-x11-xkb-utils \
    xorg-x11-fonts-base xorg-x11-fonts-misc \
    mesa-dri-drivers
