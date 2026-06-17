#!/bin/bash
set -e

# Génère /etc/sssd/sssd.conf à partir des variables d'environnement LDAP
envsubst < /etc/sssd/sssd.conf.template > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf

# Démarre sssd en arrière-plan
sssd -i &

exec "$@"
