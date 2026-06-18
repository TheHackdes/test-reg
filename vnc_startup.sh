#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${HOME}/.vnc"

# Ensure Xauthority exists (silences xauth warning)
touch "${HOME}/.Xauthority"

# KasmVNC user/password (from VNC_USER / VNC_PW)
echo -e "${VNC_PW}\n${VNC_PW}" | kasmvncpasswd -u "${VNC_USER}" -w -r "${HOME}/.kasmpasswd"

# Start KasmVNC server. -select-de xfce picks the desktop non-interactively
# (otherwise select-de.sh prompts and fails in a container).
vncserver "${DISPLAY}" \
    -select-de xfce \
    -depth "${VNC_COL_DEPTH}" \
    -geometry "${VNC_RESOLUTION}" \
    -websocketPort "${NO_VNC_PORT}" \
    -rfbport "${VNC_PORT}" \
    ${VNCOPTIONS}

# Keep container alive, stream the VNC log
exec tail -f "${HOME}"/.vnc/*.log
