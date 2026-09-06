# docker-ripper

This container will detect CDs and rip them automatically as FLAC.

### Prerequisites

#### (1) Create the required directories, for example, in /home/yourusername. Do _not_ use sudo mkdir to achieve this.

```
mkdir config rips
```

#### (2) Find out the name (s) of the optical drive

```
lsscsi -g
```

In this example, /dev/sr0 and /dev/sg0 are the two files that refer to a single optical drive. These names will be
needed for the docker run command.  
![lsscsi -g](https://raw.githubusercontent.com/rix1337/docker-ripper/main/.github/screenshots/lsscsi.png)

Screenshot of Docker run command with the example provided  
![docker run](https://raw.githubusercontent.com/rix1337/docker-ripper/main/.github/screenshots/dockerrun.png)

## Docker run

In the command below, the paths refer to the output from your lsscsi-g command, along with your config and rips
directories. If you created /home/yourusername/config and /home/yourusername/rips then those are your paths.

```
docker run -d \
  --name="Ripper" \
  -v /path/to/config/:/config:rw \
  -v /path/to/rips/:/out:rw \
  --device=/dev/sr0:/dev/sr0 \
  --device=/dev/sg0:/dev/sg0 \
  ghcr.io/gerardgascon/docker-ripper:latest
  ```

Some systems are not able to pass through optical drives without this flag

```
--privileged
```

## Docker Compose

Check the device mount points and optional settings before you run the container.

`docker-compose up -d`

### Environment Variables

- `EJECTENABLED`: Optional - If set to `true`, the disc is ejected after ripping is completed. Default is `true`.
- `STORAGE_CD`: Optional - The path for storing ripped CD content. Default is `/out/Ripper/CD`.
- `DRIVE`: Optional - The device file for the optical drive (e.g., `/dev/sr0`). Default is `/dev/sr0`.
- `BAD_THRESHOLD`: Optional - The number of allowed consecutive bad read attempts before failing. Default is `5`.

## FAQ

### How do I set ripper to do something else?

_Ripper will place a bash-file ([ripper.sh](https://github.com/rix1337/docker-ripper/blob/main/root/ripper/ripper.sh))
automatically at /config that is responsible for detecting and ripping disks. You are completely free to modify it on
your local docker host. No modifications to this main image are required for minor edits to that file._

_Additionally, you have the option of creating medium-specific override scripts in that same directory location:_

| Medium    | Script Name    | Purpose                                                                   |
|-----------|----------------|---------------------------------------------------------------------------|
| BluRay    | `BLURAYrip.sh` | Overrides BluRay ripping commands in `ripper.sh` with script operation    |
| DVD       | `DVDrip.sh`    | Overrides DVD ripping commands in `ripper.sh` with script operation       |
| Audio CD  | `CDrip.sh`     | Overrides audio CD ripping commands in `ripper.sh` with script operation  |
| Data-Disk | `DATArip.sh`   | Overrides data disk ripping commands in `ripper.sh` with script operation |

_Note that these optional scripts must be of the specified name, have executable permissions set, and be in the same
directory as `ripper.sh` to be executed._

# Credits

- [Idea based on Discbox by kingeek](http://kinggeek.co.uk/projects/item/61-discbox-linux-bash-script-to-automatically-rip-cds-dvds-and-blue-ray-with-multiple-optical-drives-and-no-user-intervention)

  Kingeek uses proper tools (like udev) to detect disk types. This is impossible in docker right now. Hence, most of the
  work is done by MakeMKV (see above).

- [MakeMKV Setup for manual-build by tianon](https://github.com/tianon/dockerfiles/blob/master/makemkv/Dockerfile)

- [MakeMKV key/version fetcher by metalight](http://blog.metalight.dk/2016/03/makemkv-wrapper-with-auto-updater.html)

- [General cleanup and exposing customization options to the user by jeeshofone](https://123cloud.st)