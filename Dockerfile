# Simple Rocky Linux 8 + KasmVNC image
# Inspired by kasmtech/workspaces-core-images (dockerfile-kasm-core-fedora)
ARG BASE_IMAGE=rockylinux:8
FROM ${BASE_IMAGE}

ARG DISTRO=rocky8
# KasmVNC release: Oracle 8 RPM is RHEL8-compatible (works on Rocky 8)
ARG KASMVNC_VERSION=1.4.0
ARG KASMVNC_RPM=kasmvncserver_oracle_8_${KASMVNC_VERSION}_x86_64.rpm

LABEL maintainer="guillaume.denis1997@gmail.com"
LABEL org.opencontainers.image.title="rocky8-kasmvnc"
LABEL org.opencontainers.image.description="Rocky Linux 8 base image with KasmVNC + XFCE"

# --- Build-time environment (matches kasm core) ---
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    HOME=/home/kasm-user \
    STARTUPDIR=/dockerstartup \
    KASM_VNC_PATH=/usr/share/kasmvnc \
    DISTRO=${DISTRO}

# --- Packages: locale, XFCE desktop, KasmVNC, common tools ---
RUN dnf -y update \
    && dnf -y install epel-release dnf-plugins-core \
    && dnf config-manager --set-enabled powertools 2>/dev/null || true \
    && dnf -y install \
        bash ca-certificates curl tar which sudo vim-minimal procps-ng \
        glibc-langpack-en \
        dbus-x11 xterm \
        xfce4-session xfwm4 xfdesktop xfce4-panel xfce4-terminal \
    && curl -fsSL -o /tmp/kasmvnc.rpm \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/${KASMVNC_RPM}" \
    && dnf -y install /tmp/kasmvnc.rpm \
    && rm -f /tmp/kasmvnc.rpm \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# --- User (kasm-user, uid 1000) ---
# kasmvnc-cert group grants read access to the self-signed TLS cert
# (/etc/pki/tls/private/kasmvnc.pem) created by the KasmVNC RPM.
RUN useradd -m -u 1000 -s /bin/bash kasm-user \
    && usermod -a -G kasmvnc-cert kasm-user \
    && mkdir -p ${STARTUPDIR} \
    && chown -R 1000:0 ${STARTUPDIR} /home/kasm-user

COPY entrypoint.sh ${STARTUPDIR}/entrypoint.sh
COPY vnc_startup.sh ${STARTUPDIR}/vnc_startup.sh
RUN chmod +x ${STARTUPDIR}/entrypoint.sh ${STARTUPDIR}/vnc_startup.sh

# --- Runtime environment (matches kasm core) ---
ENV VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    AUDIO_PORT=4901 \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x720 \
    VNC_COL_DEPTH=24 \
    VNC_USER=kasm_user \
    VNC_PW=password \
    VNCOPTIONS="-PreferBandwidth -DynamicQualityMin=4 -DynamicQualityMax=7 -DLP_ClipDelay=0" \
    LD_LIBRARY_PATH=/usr/local/lib/

EXPOSE 5901 6901 4901

USER 1000
WORKDIR /home/kasm-user

ENTRYPOINT ["/dockerstartup/entrypoint.sh"]
CMD ["/dockerstartup/vnc_startup.sh"]
