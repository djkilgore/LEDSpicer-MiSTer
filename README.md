# LEDSpicer MiSTer Build Environment

Docker-based build environment for cross-compiling [LEDSpicer](https://github.com/meduzapat/LEDSpicer) for ARM (MiSTer platform) on Ubuntu 20.04.

## Overview

This project provides a Docker container that builds LEDSpicer for the MiSTer FPGA's ARM core (armhf) and packages it as a self-contained tarball that lives entirely on the MiSTer SD card.

The MiSTer root filesystem (`linux.img`) is mounted **read-only** and is replaced wholesale by MiSTer updates, so nothing placed in `/etc` or `/usr` survives. This build therefore compiles all paths (config file, data directory, device plugins, shared libraries) to point at `/media/fat/linux/LEDSpicer`.

Pinned upstream: **LEDSpicer 0.7.7** (`LEDSPICER_REF` in the Dockerfile).

## Prerequisites

- Docker installed on your system
- Docker Compose (optional, for easier management)

## Project Structure

- `Dockerfile` - Container definition with build environment
- `docker-compose.yml` - Docker Compose configuration
- `toolchain-armv7.cmake` - CMake toolchain file for ARM cross-compilation
- `mister/` - Starter configuration and helper scripts shipped inside the tarball (see Installing on MiSTer)
- `patches/` - Source patches applied to upstream before building (see Patches)
- `.github/workflows/build.yml` - CI: builds the image and publishes `LEDSpicer.tar.gz` as an artifact (and as a release on `v*` tags)

## Building the Image

### Using Docker Compose

```bash
docker-compose build
```

### Using Docker directly

```bash
docker build -t ledspicer-mister .
```

On an Apple Silicon host the build runs under amd64 emulation (Rosetta or QEMU); it works but takes a few minutes longer.

## What Gets Built

The Dockerfile:

1. Sets up an Ubuntu 20.04 (amd64) base image. Its glibc 2.31 matches the MiSTer Linux image, so the binaries run there unmodified.
2. Adds ARM hard-float (armhf) architecture support (packages come from ports.ubuntu.com)
3. Installs build tools, the `arm-linux-gnueabihf` cross toolchain and the armhf development libraries (libusb, libtinyxml2, libasound2)
4. Clones LEDSpicer and checks out the pinned `LEDSPICER_REF`, then applies `patches/*.patch` (see Patches)
5. Patches the LED-Wiz inter-packet wait from 1 ms to 10 ms (`LEDWIZ_WAIT_US`, see "LED-Wiz timing")
6. Builds with CMake using the ARM toolchain and these options:
   - `-DCMAKE_INSTALL_PREFIX=/media/fat/linux/LEDSpicer` (also sets the data and devices dirs)
   - `-DCMAKE_INSTALL_SYSCONFDIR=/media/fat/linux/LEDSpicer/etc` (config file location)
   - `-DCMAKE_INSTALL_RPATH=/media/fat/linux/LEDSpicer/lib` (no `LD_LIBRARY_PATH` needed)
   - `-DENABLE_LEDWIZ32=ON`
   - `-DENABLE_MISTER=ON`
   - `-DENABLE_ALSAAUDIO=ON` (upstream defaults this to OFF since 0.7.7)
   - `-DENABLE_PULSEAUDIO=OFF` (not available on MiSTer)
7. Installs into a staging root and bundles `libtinyxml2.so.6` and `libasound.so.2`, which the MiSTer image does not ship
8. Adds the `mister/` starter configuration and helper scripts under `share/doc/ledspicer/examples/mister/`
9. Packages everything as `/root/LEDSpicer.tar.gz` inside the container

## Build Output

`/root/LEDSpicer.tar.gz` contains a single `LEDSpicer/` directory with `bin/`, `lib/` and `share/`. It is meant to be extracted in `/media/fat/linux/` on the MiSTer SD card.

**To get the tarball out of the image:**

```bash
container=$(docker create ledspicer-mister)
docker cp "$container":/root/LEDSpicer.tar.gz ./LEDSpicer.tar.gz
docker rm "$container"
```

Or download the `LEDSpicer-MiSTer` artifact from the GitHub Actions run.

## Installing on MiSTer

1. Copy `LEDSpicer.tar.gz` to the SD card, e.g. via the MiSTer Samba share (`smb://MiSTer/sdcard/linux/`) or `scp`.

2. On the MiSTer (ssh as `root`), extract it. If an older install exists, move it aside first:

   ```sh
   cd /media/fat/linux
   [ -d LEDSpicer ] && mv LEDSpicer LEDSpicer.old
   tar -xzf LEDSpicer.tar.gz
   ```

3. First install only: put the starter configuration in place.

   ```sh
   cd /media/fat/linux/LEDSpicer
   mkdir -p etc share/ledspicer/profiles
   cp share/doc/ledspicer/examples/mister/ledspicer.conf        etc/
   cp share/doc/ledspicer/examples/mister/basicColors.xml       share/ledspicer/
   cp share/doc/ledspicer/examples/mister/profiles/default.xml  share/ledspicer/profiles/
   ```

   When upgrading, keep your existing `etc/` and `share/ledspicer/` (copy them over from `LEDSpicer.old`).

4. Start at boot: use `share/doc/ledspicer/examples/mister/user-startup.sh` as `/media/fat/linux/user-startup.sh`, or add these lines to your existing one:

   ```sh
   setsid /media/fat/linux/LEDSpicer/bin/ledspicerd -f > /tmp/ledspicerd.log 2>&1 < /dev/null &
   sleep 2
   /media/fat/linux/LEDSpicer/bin/processLookup
   ```

   `ledspicerd` runs in foreground mode (`-f`) under `setsid`; see "LED-Wiz timing" below.

5. Test without rebooting:

   ```sh
   /media/fat/linux/LEDSpicer/bin/ledspicerd -f    # foreground, Ctrl-C to stop
   ```

   In foreground mode the log goes to stdout (or `/tmp/ledspicerd.log` when started from the startup script above).

### LED-Wiz timing

The LED-Wiz firmware is slow: if the host sends USB packets faster than it can process them it silently drops data, and sometimes locks up until it is power-cycled. Upstream LEDSpicer waits 1 ms between the four 8-byte packets of each frame, which on current MiSTer kernels is too fast. The panel then stays dark even though the daemon logs no errors. This build patches that wait to 10 ms (`LEDWIZ_WAIT_US` in the Dockerfile), and the starter config runs at 15 fps so a frame's four packets fit inside one frame interval.

If the board does get stuck, `share/doc/ledspicer/examples/mister/restart-ledspicer.sh` stops the daemon, re-enumerates the LED-Wiz on the USB bus and starts the daemon again. A hard lockup may still need a power cycle.

`ledspicerd` is started in foreground mode (`-f`) under `setsid`: it logs to `/tmp/ledspicerd.log` and avoids forking after the USB device is open, which libusb does not guarantee to be safe. `processLookup` does not touch USB and daemonizes normally.

### Starter configuration

`mister/ledspicer.conf` defines one LedWiz32 board with 32 single-colour elements named `Out1`..`Out32`, and `mister/profiles/default.xml` turns them all on. Rename the elements to match your panel wiring, add groups and animations, and keep everything under `/media/fat/linux/LEDSpicer`. Configuration files use data format version `1.1`; see the [LEDSpicer wiki](https://github.com/meduzapat/LEDSpicer/wiki) for the full syntax.

### Per-game lighting (processLookup and emitter)

`processLookup` watches the MiSTer process and, whenever a core or arcade game starts, runs `emitter LoadProfileByEmulator <set> <system>`. The daemon then looks for a profile, in order:

- Arcade cores: the MRA's `<setname>` is looked up in `share/ledspicer/gameData.xml` (set `craftProfile="True"` and `dataSource="file"` on the config root). The daemon crafts a profile on top of `profiles/profile_arcade.xml`, lighting elements named by the LEDSpicer convention: `P1_BUTTON1`..`P1_BUTTONn`, `P1_JOYSTICK1`, `P1_TRACKBALL1`, `P2_...`. It also loads animations named after the game's groups if they exist (`1_PLAYERS`, `2_PLAYERS`, `PLAYER1`, `2_COINS`, ...), which is a convenient place to light the start buttons. Games missing from the database fall back to `profiles/arcade.xml`.
- Other cores: `profiles/<Core>.xml`, where `<Core>` is the RBF filename up to the first underscore (`NES_20260823.rbf` loads `NES.xml`).
- Leaving a core restores the previous profile.

`gameData.xml` is not in the upstream tarball; take it from the `resources` branch of the upstream repository (`data/gameData.xml`, about 10,900 MAME sets) and put it in `share/ledspicer/`.

## Patches

Files in `patches/` are applied to the upstream checkout with `git apply` before building, and a patch that no longer applies fails the build. Current patches:

- `0001-processlookup-mister-pid-and-menu-path.patch`: current MiSTer firmware re-executes the main binary on every core load, so its PID changes; upstream `processLookup` threw "cannot find MiSTer" and aborted at the first core switch. The patch re-finds the process instead. It also recognises the menu by basename, since the firmware now passes `/media/fat/menu.rbf` rather than `menu.rbf`.

## Customization

### Updating LEDSpicer

Bump `LEDSPICER_REF` in the Dockerfile to a newer commit or tag from upstream and rebuild.

### Changing Build Options

Edit the `cmake` invocation in the Dockerfile. `MISTER_PREFIX` controls where the install is expected to live on the MiSTer.

### Modifying Toolchain

Edit `toolchain-armv7.cmake` to adjust cross-compilation settings.

## Notes

- PulseAudio support is disabled as it's not available on MiSTer
- The build uses ARM hard-float (armhf) architecture
- The container includes both native and ARM versions of development libraries for proper cross-compilation
- MiSTer runs everything as root, so the config uses `userId="0" groupId="0"` and no udev rules are needed
- The LED-Wiz needs slow USB writes; this build waits 10 ms between packets (see "LED-Wiz timing")
