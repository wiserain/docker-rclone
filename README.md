# docker-rclone

Docker image for [rclone](https://rclone.org/) mount, with

- Ubuntu 20.04
- pooling filesystem (a choice of mergerfs or unionfs)
- some useful scripts

## Usage

```yaml
version: '3'

services:
  rclone:
    container_name: rclone
    image: wiserain/rclone
    restart: always
    network_mode: "bridge"
    volumes:
      - ${DOCKER_ROOT}/rclone/config:/config
      - ${DOCKER_ROOT}/rclone/log:/log
      - ${DOCKER_ROOT}/rclone/cache:/cache
      - /your/mounting/point:/data:shared
      - /local/dir/to/be/merged/with:/local     # Optional: if you have a folder to be mergerfs/unionfs with
    privileged: true
    devices:
      - /dev/fuse
    cap_add:
      - MKNOD
      - SYS_ADMIN
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=Asia/Seoul
      - RCLONE_REMOTE_PATH=remote_name:path/to/mount
```

First, you need to prepare an rclone configuration file in ```/config/rclone.conf```. It can be done manually (copy yourself) or by running a built-in script below

```bash
docker-compose exec <service_name> rclone_setup
```

Then, up and run your container as in the usage above with a proper environment variable ```RCLONE_REMOTE_PATH``` which specifies an rclone remote path you want to mount. In the initialization process of every container start, it will check 1) existance of ```rclone.conf``` and 2) validation of ```RCLONE_REMOTE_PATH``` whether it really in ```rclone.conf```. If there is any problem, please check container log by

```bash
docker logs <container name or sha1, e.g. rclone>
```

### rclone mount

Here is the internal command for rclone mount.

```bash
rclone mount ${RCLONE_REMOTE_PATH} ${rclone_mountpoint} \
    --config=/config/rclone.conf \
    --uid=${PUID:-911} \
    --gid=${PGID:-911} \
    --cache-dir=/cache \
    --cache-db-path=/cache \
    --cache-chunk-path=/cache \
    --log-level=${RCLONE_MOUNT_LOG_LEVEL:-INFO} \
    --log-file=/log/rclone_mount.log \
    --allow-other \
    --umask=002 \
    ${RCLONE_MOUNT_USER_OPTS}
```

Variables only with capital letters are configurable by the container environment variable.

| ENV  | Description  | Default  |
|---|---|---|
| ```PUID``` / ```PGID```  | uid and gid for running an app  | ```911``` / ```911```  |
| ```TZ```  | timezone, required for correct timestamp in log  |   |
| ```RCLONE_REMOTE_PATH```  | this should be in ```rclone.conf```  |   |
| ```RCLONE_MOUNT_LOG_LEVEL```  | log level for rclone mount  | ```INFO```  |
| ```RCLONE_MOUNT_USER_OPTS```  | additioanl arguments will be appended to the basic options in the above command  |   |

## [mergerfs](https://github.com/trapexit/mergerfs) or unionfs (optional)

Along with the rclone folder, you can specify one local directory to be mergerfs with. Internally, it will execute a following command

```bash
mergerfs \
    -o uid=${PUID:-911},gid=${PGID:-911},umask=022,allow_other \
    -o ${MFS_USER_OPTS} \
    /local=RW:/cloud=NC /data
```
where a default value of ```MFS_USER_OPTS``` is

```bash
MFS_USER_OPTS="rw,async_read=false,use_ino,allow_other,func.getattr=newest,category.action=all,category.create=ff,cache.files=partial,dropcacheonclose=true"
```

If you want unionfs instead of mergerfs, set ```POOLING_FS=unionfs```, which will apply

```bash
unionfs \
    -o uid=${PUID:-911},gid=${PGID:-911},umask=022,allow_other \
    -o ${UFS_USER_OPTS} \
    /local=RW:/cloud=RO /data
```
where a default value of ```UFS_USER_OPTS``` is

```bash
UFS_USER_OPTS="cow,direct_io,nonempty,auto_cache,sync_read"
```

### Built-in scripts

Two scripts performing basic rclone operations such as copy and move between ```/local``` and ```/cloud``` are prepared for your conveinence. Since they are from local to cloud directories, it is meaningful only when you mount an additional ```/local``` directory. 

#### copy_local

You can make a copy of files in ```/local``` to ```/cloud``` by

```bash
docker exec -it <container name or sha1, e.g. rclone> copy_local
```

If you want to exclude a certain folder from copy, just put an empty ```.nocopy``` file on the folder root. Then, the script will ignore the sub-tree from the operation.

#### move_local

In contrast to ```copy_local```, ```move_local``` consists of three consecutive sub-operations. First, it will move old files. If ```MOVE_LOCAL_AFTER_DAYS``` is set, files older than that days will be moved. Then, it will move files exceed size of ```MOVE_LOCAL_EXCEEDS_GB``` by the amount of ```MOVE_LOCAL_FREEUP_GB```. Finally, it will move the rest of files in ```/local``` only if ```MOVE_LOCAL_ALL=true```. The command and the way to exclude subfolders are almost the same as for ```copy_local```.

#### cron - disabled by default

After making sure that a single execution of scripts is okay, you can add cron jobs of these operations by setting environment variables.

| ENV  | Description  | Default  |
|---|---|---|
| ```COPY_LOCAL_SCHEDULE```  | cron schedule for copy_local  | ```"0 0 31 2 0"``` meaning disabled by default  |
| ```MOVE_LOCAL_SCHEDULE```  | cron schedule for move_local  | ```"0 0 31 2 0"``` meaning disabled by default  |

## Credit

- [cloud-media-scripts](https://github.com/madslundt/docker-cloud-media-scripts)
