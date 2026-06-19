# Rocky Linux 8 + KasmVNC + XFCE. Minimal image, default local user kasm-user.
# Thin orchestrator: build logic lives in scripts/build/*.sh, shared runtime
# config in env/global.env.
# Build from the repo root so scripts/ and env/ are reachable:
#   docker build -f rocky8-kasmvnc.Dockerfile -t rocky8-kasmvnc .
ARG BASE_IMAGE=rockylinux:8
FROM ${BASE_IMAGE}

# KasmVNC release: Oracle 8 RPM is RHEL8-compatible (works on Rocky 8)
ARG KASMVNC_VERSION=1.4.0
ARG KASMVNC_RPM=kasmvncserver_oracle_8_${KASMVNC_VERSION}_x86_64.rpm

LABEL maintainer="guillaume.denis1997@gmail.com"
LABEL org.opencontainers.image.title="rocky8-kasmvnc"
LABEL org.opencontainers.image.description="Rocky Linux 8 base image with KasmVNC + XFCE"

# --- Build-time environment ---
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC \
    HOME=/home/kasm-user \
    STARTUPDIR=/dockerstartup

# Expose build ARGs to the install scripts.
ENV KASMVNC_VERSION=${KASMVNC_VERSION} \
    KASMVNC_RPM=${KASMVNC_RPM}

# --- Build steps (one script per concern, ordered) ---
COPY scripts/build/ /tmp/build/
RUN chmod +x /tmp/build/*.sh \
    && /tmp/build/install-base.sh \
    && /tmp/build/install-desktop.sh \
    && /tmp/build/install-kasmvnc.sh \
    && /tmp/build/setup-user.sh \
    && /tmp/build/cleanup.sh \
    && rm -rf /tmp/build

# --- Runtime scripts ---
COPY scripts/startup/ ${STARTUPDIR}/
RUN chmod +x ${STARTUPDIR}/*.sh \
    && chown -R 1000:0 ${STARTUPDIR}

# --- Runtime environment ---
ENV VNC_PORT=5901 \
    NO_VNC_PORT=6901 \
    DISPLAY=:1 \
    VNC_RESOLUTION=1280x720 \
    VNC_COL_DEPTH=24 \
    VNC_PW=password \
    VNC_VIEW_ONLY_PW=vncviewonlypassword \
    KASM_VNC_PATH=/usr/share/kasmvnc \
    MAX_FRAME_RATE=24 \
    KASMVNC_AUTO_RECOVER=true \
    START_XFCE4=1 \
    VNCOPTIONS="-PreferBandwidth -DynamicQualityMin=4 -DynamicQualityMax=7 -publicIP 127.0.0.1"

EXPOSE 5901 6901

# Kasm Workspaces launches the container as the image user (uid 1000), not root.
# Running as root + runuser fails under Kasm ("may not be used by non-root users").
USER 1000
WORKDIR /home/kasm-user

# vnc_startup.sh starts KasmVNC + XFCE; "--wait" keeps the session alive.
ENTRYPOINT ["/dockerstartup/vnc_startup.sh"]
CMD ["--wait"]
