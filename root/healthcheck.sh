#!/usr/bin/with-contenv bash

rclone_mountpoint=$(if ! mountpoint -q /local; then echo /data; else echo /cloud; fi)

if [ $(findmnt ${rclone_mountpoint} | grep fuse | wc -l) != "1" ]; then
    exit 1
fi

if [ "$(printenv POOLING_FS | tr -d '"' | tr -d "'")" == "mergerfs" ] && mountpoint -q /local; then
    if [ $(findmnt /data | grep fuse.mergerfs | wc -l) != "1" ]; then
        exit 1
    fi
fi

if [ "$(printenv POOLING_FS | tr -d '"' | tr -d "'")" == "unionfs" ] && mountpoint -q /local; then
    if [ $(findmnt /data | grep fuse.unionfs | wc -l) != "1" ]; then
        exit 1
    fi
fi

exit 0
