#!/usr/bin/with-contenv bash
. /usr/local/bin/variables

if [ $(findmnt ${rclone_mountpoint} | grep fuse | wc -l) -ne 1 ]; then
    exit 1
fi

if [ "$poolingfs" == "mergerfs" ]; then
    if [ $(findmnt /data | grep fuse.mergerfs | wc -l) -ne 1 ]; then
        exit 1
    fi
fi

if [ "$poolingfs" == "unionfs" ]; then
    if [ $(findmnt /data | grep fuse.unionfs | wc -l) -ne 1 ]; then
        exit 1
    fi
fi

exit 0
