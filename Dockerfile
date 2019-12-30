FROM ubuntu:18.04
LABEL maintainer="wiserain"

ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

ARG RCLONE_VER="current"

# s6 environment settings
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENV S6_KEEP_ENV=1

ENV LANG=C.UTF-8

# install packages
RUN \
 echo "**** apt source change for local build ****" && \
 sed -i "s/archive.ubuntu.com/\"$APT_MIRROR\"/g" /etc/apt/sources.list && \
 echo "**** install runtime packages ****" && \
 apt-get update && \
 apt-get install -y \
 	ca-certificates \
	cron \
 	fuse \
	lsof \
	tzdata \
 	unionfs-fuse \
	vim && \
 update-ca-certificates && \
 apt-get install -y openssl && \
 sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
 echo "**** install build packages ****" && \
 apt-get install -y \
 	curl \
 	unzip \
 	wget && \
 echo "**** add s6 overlay ****" && \
 OVERLAY_VERSION=$(curl -sX GET "https://api.github.com/repos/just-containers/s6-overlay/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
 curl -o /tmp/s6-overlay.tar.gz -L "https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-amd64.tar.gz" && \
 tar xfz  /tmp/s6-overlay.tar.gz -C / && \
 echo "**** add rclone ****" && \
 cd $(mktemp -d) && \
 if [ "${RCLONE_VER}" = "current" ]; then \
 wget https://downloads.rclone.org/rclone-current-linux-amd64.zip; else \
 wget "https://github.com/ncw/rclone/releases/download/${RCLONE_VER}/rclone-${RCLONE_VER}-linux-amd64.zip"; fi && \
 unzip "rclone-*-linux-amd64.zip" && \
 mv rclone-*-linux-amd64/rclone /usr/bin/ && \
 chmod a+x /usr/bin/rclone && \
 echo "**** add mergerfs ****" && \
 MFS_VERSION=$(curl -sX GET "https://api.github.com/repos/trapexit/mergerfs/releases/latest" | awk '/tag_name/{print $4;exit}' FS='[""]') && \
 cd $(mktemp -d) && wget "https://github.com/trapexit/mergerfs/releases/download/${MFS_VERSION}/mergerfs_${MFS_VERSION}.ubuntu-bionic_amd64.deb" && \
 dpkg -i mergerfs_${MFS_VERSION}.ubuntu-bionic_amd64.deb && \
 echo "**** create abc user ****" && \
 groupmod -g 1000 users && \
 useradd -u 911 -U -d /config -s /bin/false abc && \
 usermod -G users abc && \
 echo "**** cleanup ****" && \
 apt-get purge -y \
 	curl \
 	unzip \
 	wget && \
 apt-get clean autoclean && \
 apt-get autoremove -y && \
 rm -rf /tmp/* /var/lib/{apt,dpkg,cache,log}/

# add local files
COPY root/ /

# cron - disabled by default
ENV COPY_LOCAL_SCHEDULE "0 0 31 2 0"
ENV MOVE_LOCAL_SCHEDULE "0 0 31 2 0"

# default mount options
ENV POOLING_FS "mergerfs"
ENV UFS_USER_OPTS "cow,direct_io,nonempty,auto_cache,sync_read"
ENV MFS_USER_OPTS "rw,async_read=false,use_ino,allow_other,func.getattr=newest,category.action=all,category.create=ff,cache.files=partial,dropcacheonclose=true"

# others
# ENV DATE_FORMAT "+%F@%T"
ENV DATE_FORMAT="+%4Y/%m/%d %H:%M:%S"
ENV RCLONE_CONFIG=/config/rclone.conf
ENV PS1="\u@\h:\w\\$ "

VOLUME /config /cache /log /cloud /data
WORKDIR /data

ENTRYPOINT ["/init"]
CMD cron -f
