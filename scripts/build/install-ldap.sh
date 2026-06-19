#!/usr/bin/env bash
# LDAP identity layer: SSSD + NSS wiring so the runtime entrypoint can resolve
# LDAP users (getent passwd / id) and launch the desktop session as them.
#
# Only the *packages* and the static NSS map are baked here. The actual LDAP
# connection settings are runtime config (env/global.env) rendered into
# /etc/sssd/sssd.conf by scripts/startup/entrypoint.sh on every boot.
#
# We do NOT use authselect: it needs an initialized profile that a minimal
# container image doesn't have ("Unable to get profile information [2]"), and
# the entrypoint drops privileges with setpriv (no PAM), so only NSS lookups
# are required. We edit /etc/nsswitch.conf directly instead.
set -euo pipefail

dnf -y install \
    sssd sssd-ldap sssd-tools \
    openldap-clients \
    sudo

# Point NSS passwd/group/shadow at SSSD (append "sss" if not already present).
NSS=/etc/nsswitch.conf
[[ -f "$NSS" ]] || printf 'passwd: files\ngroup: files\nshadow: files\n' > "$NSS"
for db in passwd group shadow; do
    if grep -qE "^[[:space:]]*${db}:" "$NSS"; then
        grep -qE "^[[:space:]]*${db}:.*\bsss\b" "$NSS" \
            || sed -ri "s/^([[:space:]]*${db}:.*)$/\1 sss/" "$NSS"
    else
        printf '%s:     files sss\n' "$db" >> "$NSS"
    fi
done

# SSSD refuses to start if sssd.conf is group/world-readable. Ship a 0600
# placeholder owned by root so the very first render already has safe perms.
install -d -m 0711 /etc/sssd
: > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf

# Kasm Workspaces often launches the container as the non-root image user
# (kasm-user, uid 1000), overriding the image's USER root. sssd is a privileged
# daemon and cannot start in that case, so the entrypoint re-execs itself as root
# via passwordless sudo ("entrypoint.sh --sssd-only") to bring sssd up while the
# desktop keeps running unprivileged. Allow ONLY that exact command, no others.
cat > /etc/sudoers.d/sssd-bringup <<'EOF'
kasm-user ALL=(root) NOPASSWD:SETENV: /dockerstartup/entrypoint.sh --sssd-only
EOF
chmod 440 /etc/sudoers.d/sssd-bringup
visudo -cf /etc/sudoers.d/sssd-bringup
