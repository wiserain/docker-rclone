FROM golang:1.16-bullseye AS builder

ARG GO_CRON_VERSION=0.0.4
ARG GO_CRON_SHA256=6c8ac52637150e9c7ee88f43e29e158e96470a3aaa3fcf47fd33771a8a76d959

RUN mkdir -p /bar

ENV GOBIN=/bar/usr/local/bin

RUN \
  echo "**** build go-cron v${GO_CRON_VERSION} ****" && \
  curl -sL -o go-cron.tar.gz https://github.com/djmaze/go-cron/archive/v${GO_CRON_VERSION}.tar.gz && \
  echo "${GO_CRON_SHA256}  go-cron.tar.gz" | sha256sum -c - && \
  tar xzf go-cron.tar.gz && \
  cd go-cron-${GO_CRON_VERSION} && \
  go install

# add local files
COPY root/ /bar/

ADD https://raw.githubusercontent.com/by275/docker-scripts/master/root/etc/cont-init.d/20-install-pkg /bar/etc/cont-init.d/20-install-pkg
ADD https://raw.githubusercontent.com/by275/docker-scripts/master/root/etc/cont-init.d/30-wait-for-mnt /bar/etc/cont-init.d/30-wait-for-mnt


FROM ubuntu:20.04
LABEL maintainer="wiserain"
LABEL org.opencontainers.image.source https://github.com/wiserain/docker-rclone

ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

ARG RCLONE_TYPE="latest"
ARG TARGETARCH

# add build artifacts
COPY --from=builder /bar/ /

# install packages
RUN \
  echo "**** apt source change for local build ****" && \
  sed -i "s/archive.ubuntu.com/$APT_MIRROR/g" /etc/apt/sources.list && \
  echo "**** install runtime packages ****" && \
  apt-get update && \
  apt-get install -yq --no-install-recommends apt-utils && \
  apt-get install -yq --no-install-recommends \
    bc \
    ca-certificates \
    fuse \
    jq \
    lsof \
    openssl \
    tzdata \
    unionfs-fuse && \
  update-ca-certificates && \
  sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
  echo "**** install build packages ****" && \
  apt-get install -yq --no-install-recommends \
    curl \
    unzip && \
  echo "**** add s6 overlay ****" && \
  OVERLAY_VERSION=$(curl -sX GET "https://api.github.com/repos/just-containers/s6-overlay/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  OVERLAY_ARCH=$(if [ "$TARGETARCH" = "arm64" ]; then echo "aarch64"; elif [ "$TARGETARCH" = "arm" ]; then echo "armhf"; else echo "$TARGETARCH"; fi) && \
  curl -o /tmp/s6-overlay.tar.gz -L "https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" && \
  tar xzf /tmp/s6-overlay.tar.gz -C / --exclude='./bin' && tar xzf /tmp/s6-overlay.tar.gz -C /usr ./bin && \
  echo "**** add rclone ****" && \
  if [ "${RCLONE_TYPE}" = "latest" ]; then \
    rclone_install_script_url="https://rclone.org/install.sh"; \
  elif [ "${RCLONE_TYPE}" = "mod" ]; then \
    rclone_install_script_url="https://raw.githubusercontent.com/wiserain/rclone/mod/install.sh"; fi && \
  curl -fsSL $rclone_install_script_url | bash && \
  echo "**** add mergerfs ****" && \
  MFS_VERSION=$(curl -sX GET "https://api.github.com/repos/trapexit/mergerfs/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  MFS_DEB="mergerfs_${MFS_VERSION}.ubuntu-focal_$(dpkg --print-architecture).deb" && \
  cd $(mktemp -d) && curl -LJO "https://github.com/trapexit/mergerfs/releases/download/${MFS_VERSION}/${MFS_DEB}" && \
  dpkg -i ${MFS_DEB} && \
  echo "**** create abc user ****" && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  echo "**** permissions ****" && \
  chmod a+x /usr/local/bin/* && \
  echo "**** cleanup ****" && \
  apt-get purge -y \
    curl \
    unzip && \
  apt-get clean autoclean && \
  apt-get autoremove -y && \
  rm -rf /tmp/* /var/lib/{apt,dpkg,cache,log}/

# environment settings
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KILL_FINISH_MAXTIME=7000 \
    S6_SERVICES_GRACETIM=5000 \
    S6_KILL_GRACETIME=5000 \
    LANG=C.UTF-8 \
    PS1="\u@\h:\w\\$ " \
    RCLONE_CONFIG=/config/rclone.conf \
    RCLONE_REFRESH_METHOD=default \
    UFS_USER_OPTS="cow,direct_io,nonempty,auto_cache,sync_read" \
    MFS_USER_OPTS="rw,use_ino,func.getattr=newest,category.action=all,category.create=ff,cache.files=auto-full,dropcacheonclose=true" \
    DATE_FORMAT="+%4Y/%m/%d %H:%M:%S"

VOLUME /config /cache /log /cloud /data /local
WORKDIR /data

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD healthcheck.sh

ENTRYPOINT ["/init"]
