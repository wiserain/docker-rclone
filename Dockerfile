# 
# RELEASE
# 
FROM wiserain/rclone

COPY root/ /

LABEL maintainer="slink42"
LABEL org.opencontainers.image.source https://github.com/slink42/docker-mergerfs

# environment settings
ENV \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
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

VOLUME /config /cache /log /mnt
WORKDIR /mnt

HEALTHCHECK --interval=30s --timeout=30s --start-period=10s --retries=3 \
    CMD /usr/local/bin/healthcheck

ENTRYPOINT ["/init"]
