FROM rockylinux:8

LABEL maintainer="gdenis"

# ---- Variables LDAP a personnaliser ----
# Surchargeables au "docker run -e VAR=valeur" ou dans le Docker Run Config de Kasm
ENV LDAP_URI="ldap://your-ldap-server:389" \
    LDAP_BASE_DN="dc=example,dc=com" \
    LDAP_BIND_DN="cn=readonly,dc=example,dc=com" \
    LDAP_BIND_PASSWORD="changeme" \
    LDAP_SCHEMA="rfc2307"

RUN dnf install -y \
        sssd \
        sssd-ldap \
        authselect \
        gettext \
        openssh-clients \
        sudo \
    && authselect select sssd --force \
    && dnf clean all

COPY sssd.conf.template /etc/sssd/sssd.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
