#!/usr/bin/env bash
# Root entrypoint. Runs as root ONLY long enough to:
#   1. load global defaults from env/global.env (real env still wins),
#   2. (optional) render /etc/sssd/sssd.conf from the LDAP vars and start sssd,
#   3. resolve the per-session user (KASM_USER, injected by Kasm Workspaces),
#   4. create that user's home dir on first login if it doesn't exist,
# then drops privileges and execs vnc_startup.sh AS that user. The KasmVNC
# server, XFCE and everything the user sees therefore run unprivileged.
set -e

APP_NAME=$(basename "$0")
log () { echo "$(date -u +%FT%TZ) ${2:-INFO} (${APP_NAME}): $1"; }

ENV_FILE="${ENV_FILE:-/dockerstartup/env/global.env}"

# --- Load global defaults (real env WINS) ---
# global.env holds DEFAULTS only: we adopt a value solely when the variable is
# currently unset, so anything injected by Kasm/Docker takes precedence.
if [[ -r "$ENV_FILE" ]]; then
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue   # comment
        [[ -z "${key// /}" ]] && continue            # blank
        key="${key// /}"
        val="${val%\"}"; val="${val#\"}"             # strip surrounding quotes
        [[ -z "${!key+x}" ]] && export "$key=$val"
    done < "$ENV_FILE"
fi

: "${LDAP_ENABLED:=false}"
: "${LDAP_HOME_DIR_TEMPLATE:=/home/%u}"
: "${LDAP_DEFAULT_SHELL:=/bin/bash}"

# --- SSSD / LDAP ---
start_sssd () {
    : "${LDAP_URI:?LDAP_URI required when LDAP_ENABLED=true}"
    : "${LDAP_SEARCH_BASE:?LDAP_SEARCH_BASE required when LDAP_ENABLED=true}"
    : "${LDAP_SCHEMA:=rfc2307}"
    : "${LDAP_TLS_REQCERT:=demand}"
    : "${LDAP_ID_USE_START_TLS:=false}"
    log "Configuring SSSD for LDAP (${LDAP_URI})"

    umask 077
    {
        echo "[sssd]"
        echo "config_file_version = 2"
        echo "services = nss, pam"
        echo "domains = LDAP"
        echo
        echo "[domain/LDAP]"
        echo "id_provider = ldap"
        echo "auth_provider = ldap"
        echo "ldap_uri = ${LDAP_URI}"
        echo "ldap_search_base = ${LDAP_SEARCH_BASE}"
        echo "ldap_schema = ${LDAP_SCHEMA}"
        echo "ldap_id_use_start_tls = ${LDAP_ID_USE_START_TLS}"
        echo "ldap_tls_reqcert = ${LDAP_TLS_REQCERT}"
        [[ -n "${LDAP_TLS_CACERT:-}" ]]      && echo "ldap_tls_cacert = ${LDAP_TLS_CACERT}"
        # Unencrypted connection (plain ldap:// and no StartTLS): sssd otherwise
        # refuses to send the user password during a bind. Allow it explicitly.
        if [[ "${LDAP_URI}" != ldaps://* && "${LDAP_ID_USE_START_TLS,,}" != "true" ]]; then
            echo "ldap_auth_disable_tls_never_use_in_production = true"
        fi
        [[ -n "${LDAP_DEFAULT_BIND_DN:-}" ]] && echo "ldap_default_bind_dn = ${LDAP_DEFAULT_BIND_DN}"
        [[ -n "${LDAP_DEFAULT_AUTHTOK:-}" ]] && echo "ldap_default_authtok = ${LDAP_DEFAULT_AUTHTOK}"
        [[ -n "${LDAP_USER_SEARCH_BASE:-}" ]]  && echo "ldap_user_search_base = ${LDAP_USER_SEARCH_BASE}"
        [[ -n "${LDAP_GROUP_SEARCH_BASE:-}" ]] && echo "ldap_group_search_base = ${LDAP_GROUP_SEARCH_BASE}"
        if [[ -n "${LDAP_ACCESS_FILTER:-}" ]]; then
            echo "access_provider = ldap"
            echo "ldap_access_filter = ${LDAP_ACCESS_FILTER}"
        fi
        echo "override_homedir = ${LDAP_HOME_DIR_TEMPLATE}"
        echo "default_shell = ${LDAP_DEFAULT_SHELL}"
        echo "cache_credentials = true"
        echo "enumerate = false"
        echo
        echo "[nss]"
        echo "[pam]"
    } > /etc/sssd/sssd.conf
    chmod 600 /etc/sssd/sssd.conf
    chown root:root /etc/sssd/sssd.conf

    # No systemd in the container: start sssd as a plain daemon.
    rm -f /var/lib/sss/pipes/* 2>/dev/null || true
    /usr/sbin/sssd -D --logger=files || { log "sssd failed to start" ERROR; exit 1; }

    # Wait for the NSS responder to come up before we look users up.
    local i
    for i in $(seq 1 30); do
        getent passwd >/dev/null 2>&1 && break
        sleep 0.5
    done
}

# --- --sssd-only re-entry (privileged helper) ---
# When Kasm launches the container as a non-root uid we cannot start sssd
# directly, so the unprivileged entrypoint re-execs itself as root via
# passwordless sudo with this flag: bring sssd up, then exit so the parent
# continues as the desktop user. (sudoers drop-in shipped by install-ldap.sh.)
if [[ "${1:-}" == "--sssd-only" ]]; then
    [[ "$(id -u)" -eq 0 ]] || { log "--sssd-only requires root" ERROR; exit 1; }
    [[ "${LDAP_ENABLED,,}" == "true" ]] || { log "--sssd-only but LDAP_ENABLED!=true" ERROR; exit 1; }
    start_sssd
    exit 0
fi

# --- Privilege handling ---
# sssd + per-user home provisioning + setpriv need root. Two supported setups:
#   * container runs as root  -> start sssd here, then drop to the session user.
#   * container runs non-root -> elevate ONLY the sssd bring-up via sudo, then
#     run the desktop as the current (unprivileged) user. LDAP users still
#     resolve (sssd is up); we just cannot switch into them or provision homes.
if [[ "$(id -u)" -ne 0 ]]; then
    if [[ "${LDAP_ENABLED,,}" == "true" ]]; then
        if command -v sudo >/dev/null 2>&1; then
            log "uid $(id -u) (non-root): bringing sssd up via sudo"
            sudo -nE /dockerstartup/entrypoint.sh --sssd-only \
                || log "sudo sssd bring-up failed; LDAP users will NOT resolve (need NOPASSWD sudoers or run as root)" ERROR
        else
            log "LDAP_ENABLED=true but uid $(id -u) and sudo missing: sssd cannot start, LDAP users will NOT resolve." ERROR
        fi
    else
        log "Not running as root (uid $(id -u)); skipping LDAP." WARNING
    fi
    exec /dockerstartup/vnc_startup.sh "$@"
fi

# --- root path: start sssd, then drop privileges below ---
if [[ "${LDAP_ENABLED,,}" == "true" ]]; then
    start_sssd
else
    log "LDAP_ENABLED!=true; using local accounts only"
fi

# --- Resolve the session user ---
# Kasm Workspaces injects the authenticated username per session (KASM_USER,
# typically set to the {username} template in the workspace Docker Run Config
# Override). Fall back to the local kasm-user so the image still boots without
# LDAP.
SESSION_USER="${KASM_USER:-${VNC_USER:-kasm-user}}"

# Kasm's {username} can carry a realm/domain suffix (e.g. "jdoe@example.com")
# while the LDAP account is just "jdoe". If the full name doesn't resolve, retry
# with the bare local-part before giving up.
if ! id "$SESSION_USER" >/dev/null 2>&1; then
    if [[ "$SESSION_USER" == *@* ]] && id "${SESSION_USER%%@*}" >/dev/null 2>&1; then
        log "Session user '${SESSION_USER}' not found; using bare username '${SESSION_USER%%@*}'" WARNING
        SESSION_USER="${SESSION_USER%%@*}"
    else
        log "Session user '${SESSION_USER}' not found (LDAP unreachable? bad username?)" ERROR
        exit 1
    fi
fi

SESSION_UID=$(id -u "$SESSION_USER")
SESSION_GID=$(id -g "$SESSION_USER")
SESSION_HOME=$(getent passwd "$SESSION_USER" | cut -d: -f6)
[[ -z "$SESSION_HOME" ]] && SESSION_HOME="/home/${SESSION_USER}"

# --- Provision the home directory on first login ---
if [[ ! -d "$SESSION_HOME" ]]; then
    log "Creating home directory ${SESSION_HOME} for ${SESSION_USER}"
    mkdir -p "$SESSION_HOME"
    cp -aT /etc/skel "$SESSION_HOME" 2>/dev/null || true
    chown -R "${SESSION_UID}:${SESSION_GID}" "$SESSION_HOME"
else
    chown "${SESSION_UID}:${SESSION_GID}" "$SESSION_HOME"
fi

# --- Drop privileges and hand off to the VNC startup as the session user ---
# KasmVNC reads the system TLS cert (/etc/pki/tls/private/kasmvnc.pem), readable
# only by the "kasmvnc-cert" group. The static kasm-user is in that group, but a
# dynamic LDAP user is not, so KasmVNC bails with "certificate isn't readable".
# Fold the cert group into the session user's supplementary groups at drop time
# (equivalent to `usermod -aG kasmvnc-cert`, but works for non-local users).
SUP_GROUPS=$(id -G "$SESSION_USER" 2>/dev/null | tr ' ' ',')
CERT_GID=$(getent group kasmvnc-cert | cut -d: -f3)
[[ -n "$CERT_GID" ]] && SUP_GROUPS="${SUP_GROUPS:+${SUP_GROUPS},}${CERT_GID}"

log "Starting session as ${SESSION_USER} (uid ${SESSION_UID}, groups ${SUP_GROUPS})"
cd "$SESSION_HOME"
exec setpriv --reuid "$SESSION_UID" --regid "$SESSION_GID" \
    ${SUP_GROUPS:+--groups "$SUP_GROUPS"} \
    env HOME="$SESSION_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
    /dockerstartup/vnc_startup.sh "$@"
