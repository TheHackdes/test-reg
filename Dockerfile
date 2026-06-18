# Simple Rocky Linux 8 image, inspired by kasmtech/workspaces-core-images
ARG BASE_IMAGE=rockylinux:8
FROM ${BASE_IMAGE}

LABEL maintainer="guillaume.denis1997@gmail.com"
LABEL org.opencontainers.image.title="rocky8-core"
LABEL org.opencontainers.image.description="Simple Rocky Linux 8 base image"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TZ=UTC

# Common tools
RUN dnf -y update \
    && dnf -y install \
        bash \
        ca-certificates \
        curl \
        glibc-langpack-en \
        procps-ng \
        sudo \
        tar \
        vim-minimal \
        which \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# Non-root user (kasm-user, uid 1000)
RUN useradd -m -u 1000 -s /bin/bash kasm-user

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER 1000
WORKDIR /home/kasm-user

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
