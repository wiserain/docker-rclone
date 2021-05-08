FROM ubuntu:20.04
LABEL maintainer="wiserain"
LABEL org.opencontainers.image.source https://github.com/wiserain/docker-rclone

ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

ARG RCLONE_VER="current"
ARG TARGETARCH

# environment settings - s6
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENV S6_KEEP_ENV=1

# environment settings - container-level
ENV LANG=C.UTF-8
ENV PS1="\u@\h:\w\\$ "

# install packages
RUN \
  echo "**** apt source change for local build ****" && \
  sed -i "s/archive.ubuntu.com/$APT_MIRROR/g" /etc/apt/sources.list && \
  echo "**** install runtime packages ****" && \
  apt-get update && \
  apt-get install -yq --no-install-recommends apt-utils && \
  apt-get install -yq --no-install-recommends \
    ca-certificates \
    cron \
    fuse \
    lsof \
    openssl \
    tzdata \
    unionfs-fuse \
    vim && \
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
  cd $(mktemp -d) && \
  if [ "${RCLONE_VER}" = "current" ]; then \
  curl -LJO https://downloads.rclone.org/rclone-current-linux-$TARGETARCH.zip; else \
  curl -LJO "https://github.com/ncw/rclone/releases/download/v${RCLONE_VER}/rclone-v${RCLONE_VER}-linux-$TARGETARCH.zip"; fi && \
  unzip "rclone-*-linux-$TARGETARCH.zip" && \
  mv rclone-*-linux-$TARGETARCH/rclone /usr/bin/ && \
  chmod 755 /usr/bin/rclone && \
  echo "**** add mergerfs ****" && \
  MFS_VERSION=$(curl -sX GET "https://api.github.com/repos/trapexit/mergerfs/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
  MFS_ARCH=$(if [ "$TARGETARCH" = "arm" ]; then echo "armhf"; else echo "$TARGETARCH"; fi) && \
  MFS_DEB="mergerfs_${MFS_VERSION}.ubuntu-focal_${MFS_ARCH}.deb" && \
  cd $(mktemp -d) && curl -LJO "https://github.com/trapexit/mergerfs/releases/download/${MFS_VERSION}/${MFS_DEB}" && \
  dpkg -i ${MFS_DEB} && \
  echo "**** create abc user ****" && \
  groupmod -g 1000 users && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  echo "**** cleanup ****" && \
  apt-get purge -y \
    curl \
    unzip && \
  apt-get clean autoclean && \
  apt-get autoremove -y && \
  rm -rf /tmp/* /var/lib/{apt,dpkg,cache,log}/

# add local files
COPY root/ /

RUN chmod a+x /healthcheck.sh

# environment settings - rclone
ENV RCLONE_CONFIG=/config/rclone.conf

# environment settings - pooling fs
ENV POOLING_FS "mergerfs"
ENV UFS_USER_OPTS "cow,direct_io,nonempty,auto_cache,sync_read"
ENV MFS_USER_OPTS "rw,async_read=false,use_ino,allow_other,func.getattr=newest,category.action=all,category.create=ff,cache.files=partial,dropcacheonclose=true"

# environment settings - scripts
ENV COPY_LOCAL_SCHEDULE "0 0 31 2 0"
ENV MOVE_LOCAL_SCHEDULE "0 0 31 2 0"

# environment settings - others
ENV DATE_FORMAT="+%4Y/%m/%d %H:%M:%S"

VOLUME /config /cache /log /cloud /data /local
WORKDIR /data

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 CMD /healthcheck.sh

ENTRYPOINT ["/init"]
CMD cron -f
