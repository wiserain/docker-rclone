ARG UBUNTU_VER=20.04

FROM ghcr.io/by275/base:ubuntu AS prebuilt
FROM ghcr.io/by275/base:ubuntu${UBUNTU_VER} AS base

# 
# BUILD
# 
FROM base AS rclone

ARG RCLONE_TYPE="latest"
ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

RUN \
    echo "**** apt source change for local build ****" && \
    sed -i "s/archive.ubuntu.com/$APT_MIRROR/g" /etc/apt/sources.list && \
    echo "**** add rclone ****" && \
    apt-get update -qq && \
    apt-get install -yq --no-install-recommends \
        unzip && \
    if [ "${RCLONE_TYPE}" = "latest" ]; then \
        rclone_install_script_url="https://rclone.org/install.sh"; \
    elif [ "${RCLONE_TYPE}" = "mod" ]; then \
        rclone_install_script_url="https://raw.githubusercontent.com/wiserain/rclone/mod/install.sh"; fi && \
    curl -fsSL $rclone_install_script_url | bash

# 
# COLLECT
# 
FROM base AS collector

# add s6 overlay
COPY --from=prebuilt /s6/ /bar/
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/adduser /bar/etc/cont-init.d/10-adduser
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/install-pkg /bar/etc/cont-init.d/20-install-pkg
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/wait-for-mnt /bar/etc/cont-init.d/30-wait-for-mnt

# add go-cron
COPY --from=prebuilt /go/bin/go-cron /bar/usr/local/bin/

# add rclone
COPY --from=rclone /usr/bin/rclone /bar/usr/bin/

# add local files
COPY root/ /bar/

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/cache \
        /bar/log \
        /bar/cloud \
        /bar/data \
        /bar/local \
        && \
    echo "**** permissions ****" && \
    chmod a+x \
        /bar/usr/local/bin/* \
        /bar/etc/cont-init.d/* \
        /bar/etc/cont-finish.d/* \
        /bar/etc/s6-overlay/s6-rc.d/*/run \
        /bar/etc/s6-overlay/s6-rc.d/*/data/*

RUN \
    echo "**** s6: resolve dependencies ****" && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do mkdir -p "$dir/dependencies.d"; done && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "$dir/dependencies.d/legacy-cont-init"; done && \
    echo "**** s6: create a new bundled service ****" && \
    mkdir -p /tmp/app/contents.d && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "/tmp/app/contents.d/$(basename "$dir")"; done && \
    echo "bundle" > /tmp/app/type && \
    mv /tmp/app /bar/etc/s6-overlay/s6-rc.d/app && \
    echo "**** s6: deploy services ****" && \
    rm /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services && \
    touch /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/app

# 
# RELEASE
# 
FROM base
LABEL maintainer="wiserain"
LABEL org.opencontainers.image.source https://github.com/wiserain/docker-rclone

ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

# install packages
RUN \
    echo "**** apt source change for local build ****" && \
    sed -i "s/archive.ubuntu.com/$APT_MIRROR/g" /etc/apt/sources.list && \
    echo "**** install runtime packages ****" && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        bc \
        fuse \
        jq \
        lsof \
        openssl \
        unionfs-fuse \
        && \
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
    echo "**** add mergerfs ****" && \
    MFS_VERSION=$(curl -fsL "https://api.github.com/repos/trapexit/mergerfs/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
    MFS_DEB="mergerfs_${MFS_VERSION}.ubuntu-focal_$(dpkg --print-architecture).deb" && \
    cd $(mktemp -d) && curl -LJO "https://github.com/trapexit/mergerfs/releases/download/${MFS_VERSION}/${MFS_DEB}" && \
    dpkg -i ${MFS_DEB} && \
    echo "**** cleanup ****" && \
    rm -rf \
        /tmp/* \
        /var/tmp/* \
        /var/cache/* \
        /var/lib/apt/lists/*

# add build artifacts
COPY --from=collector /bar/ /

# environment settings
ENV \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KILL_FINISH_MAXTIME=7000 \
    S6_SERVICES_GRACETIM=5000 \
    S6_KILL_GRACETIME=5000 \
    RCLONE_CONFIG=/config/rclone.conf \
    RCLONE_REFRESH_METHOD=default \
    UFS_USER_OPTS="cow,direct_io,nonempty,auto_cache,sync_read" \
    MFS_USER_OPTS="rw,use_ino,func.getattr=newest,category.action=all,category.create=ff,cache.files=auto-full,dropcacheonclose=true" \
    DATE_FORMAT="+%4Y/%m/%d %H:%M:%S"

VOLUME /config /cache /log /cloud /data /local

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck

ENTRYPOINT ["/init"]
