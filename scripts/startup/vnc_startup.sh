#!/usr/bin/env bash
# KasmVNC startup, modeled on kasmtech/workspaces-core-images vnc_startup.sh.
# Runs as kasm-user (uid 1000). Serves the KasmVNC web client on NO_VNC_PORT
# over SSL so the Kasm Workspaces agent can connect. "--wait" (the default CMD)
# keeps services alive; any other argument is exec'd as the container command.
set -e

APP_NAME=$(basename "$0")
log () { echo "$(date -u +%FT%TZ) ${2:-INFO} (${APP_NAME}): $1"; }

# --- Defaults (real env, e.g. injected by Kasm, WINS) ---
: "${HOME:=/home/kasm-user}"
: "${DISPLAY:=:1}"
: "${KASM_VNC_PATH:=/usr/share/kasmvnc}"
: "${VNC_COL_DEPTH:=24}"
: "${VNC_RESOLUTION:=1280x720}"
: "${NO_VNC_PORT:=6901}"
: "${MAX_FRAME_RATE:=24}"
: "${VNC_PW:=password}"
: "${VNC_VIEW_ONLY_PW:=${VNC_PW}}"
: "${KASMVNC_AUTO_RECOVER:=true}"
: "${START_XFCE4:=1}"
export HOME DISPLAY

declare -A KASM_PROCS
STARTUP_COMPLETE=0

# Session dbus bus for XFCE. MUST be unquoted: dbus-launch prints two
# assignments (ADDRESS + PID) that word-split into two exports. Quoting it
# collapses them into one malformed var -> "Could not connect" -> XFCE dies.
export $(dbus-launch)

# Kasm may inject an LC_ALL (e.g. fr_FR.UTF-8) the C library lacks; fall back to
# a guaranteed-present locale so XFCE/Gtk don't choke. (fr langpack is installed
# at build time, so fr_FR.UTF-8 normally passes this check.)
WANT_LOCALE="$(echo "${LC_ALL:-}" | sed 's/UTF-8/utf8/')"
if [[ -n "${LC_ALL:-}" ]] && ! locale -a 2>/dev/null | grep -qix "${WANT_LOCALE}"; then
    export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en_US:en
fi

cleanup () { kill -s SIGTERM "$!" 2>/dev/null || true; exit 0; }
trap cleanup SIGINT SIGTERM SIGQUIT SIGHUP

# Block until the X11 socket for $DISPLAY accepts connections (avoids the WM /
# xset racing the server with "unable to open display").
wait_for_x () {
    local dnum="${DISPLAY##*:}" i
    for i in $(seq 1 30); do
        [[ -S "/tmp/.X11-unix/X${dnum}" ]] && return 0
        sleep 0.5
    done
    log "X display ${DISPLAY} not ready after 15s" "WARNING"
}

start_kasmvnc () {
    log "Starting KasmVNC"
    if [[ $STARTUP_COMPLETE == 0 ]]; then
        vncserver -kill "$DISPLAY" &>/dev/null \
            || rm -rfv /tmp/.X*-lock /tmp/.X11-unix &>/dev/null \
            || echo "no locks present"
    fi
    rm -rf "$HOME"/.vnc/*.pid
    # KasmVNC drives the window manager itself (-select-de manual); a no-op
    # xstartup keeps vncserver from launching its own session.
    echo "exit 0" > "$HOME/.vnc/xstartup"
    chmod +x "$HOME/.vnc/xstartup"

    vncserver "$DISPLAY" \
        -depth "$VNC_COL_DEPTH" \
        -geometry "$VNC_RESOLUTION" \
        -websocketPort "$NO_VNC_PORT" \
        -httpd "${KASM_VNC_PATH}/www" \
        -sslOnly \
        -FrameRate="$MAX_FRAME_RATE" \
        -interface 0.0.0.0 \
        -BlacklistThreshold=0 \
        -FreeKeyMappings \
        -select-de manual \
        ${VNCOPTIONS:-}

    # Pin to this display's pid file (a bare *.pid glob can match stale files
    # and concatenate into a bogus multi-line pid -> false "crashed" restarts).
    local dnum="${DISPLAY##*:}"
    KASM_PROCS['kasmvnc']=$(cat "$HOME"/.vnc/*:"${dnum}".pid 2>/dev/null | head -n1)

    wait_for_x
    DISPLAY="$DISPLAY" xset -dpms || true
    DISPLAY="$DISPLAY" xset s off || true
}

start_window_manager () {
    if [[ "${START_XFCE4}" == "1" ]]; then
        log "Starting XFCE"
        DISPLAY="$DISPLAY" /usr/bin/startxfce4 --replace &
        KASM_PROCS['window_manager']=$!
    else
        log "Skipping XFCE startup"
    fi
}

# --- Self-signed cert for KasmVNC SSL ---
mkdir -p "$HOME/.vnc"
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$HOME/.vnc/self.pem" -out "$HOME/.vnc/self.pem" \
    -subj "/C=US/ST=VA/L=None/O=None/OU=DoFu/CN=kasm/emailAddress=none@none.none" 2>/dev/null

# --- Passwords: kasm_user = control, kasm_viewer = view-only ---
# Kasm Workspaces authenticates the session as kasm_user.
PASSWD_PATH="$HOME/.kasmpasswd"
rm -f "$PASSWD_PATH"
echo -e "${VNC_PW}\n${VNC_PW}\n" | kasmvncpasswd -u kasm_user -wo
echo -e "${VNC_VIEW_ONLY_PW}\n${VNC_VIEW_ONLY_PW}\n" | kasmvncpasswd -u kasm_viewer -r
chmod 600 "$PASSWD_PATH"

start_kasmvnc
start_window_manager
STARTUP_COMPLETE=1

log "KasmVNC environment started"
tail -f "$HOME"/.vnc/*"$DISPLAY".log &

# Unknown command (not --wait) => run it instead of the keep-alive loop.
if [[ -n "${1:-}" && "${1}" != "--wait" ]]; then
    log "Executing command: $*"
    exec "$@"
fi

# --- Monitor loop: restart crashed services, keep the container alive ---
sleep 3
while :; do
    for process in "${!KASM_PROCS[@]}"; do
        if ! kill -0 "${KASM_PROCS[$process]}" 2>/dev/null; then
            case $process in
                kasmvnc)
                    if [[ "$KASMVNC_AUTO_RECOVER" == true ]]; then
                        log "KasmVNC crashed, restarting" "WARNING"
                        start_kasmvnc
                    else
                        log "KasmVNC crashed, exiting container" "ERROR"
                        exit 1
                    fi
                    ;;
                window_manager)
                    log "Window manager crashed, restarting" "WARNING"
                    start_window_manager
                    ;;
            esac
        fi
    done
    sleep 3
done
