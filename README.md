# LEDSpicer MiSTer Build Environment

Docker-based build environment for cross-compiling LEDSpicer for ARM (MiSTer platform) on Ubuntu 20.04.

## Overview

This project provides a Docker container setup to build LEDSpicer with ARM cross-compilation support. The container includes all necessary build tools and dependencies for compiling LEDSpicer for the MiSTer platform.

## Prerequisites

- Docker installed on your system
- Docker Compose (optional, for easier management)

## Project Structure

- `Dockerfile` - Container definition with build environment
- `docker-compose.yml` - Docker Compose configuration
- `toolchain-armv7.cmake` - CMake toolchain file for ARM cross-compilation

## Building the Image

### Using Docker Compose

```bash
docker-compose build
```

### Using Docker directly

```bash
docker build -t ledspicer-mister .
```

## Running the Container

### Using Docker Compose

To get an interactive shell:

```bash
docker-compose run ledspicer /bin/bash
```

To mount a volume when running:

```bash
docker-compose run -v /path/to/host:/workspace ledspicer /bin/bash
```

### Using Docker directly

```bash
docker run -it -v /path/to/host:/workspace ledspicer-mister /bin/bash
```

## What Gets Built

The Dockerfile:

1. Sets up Ubuntu 20.04 base image
2. Adds ARM hard-float (armhf) architecture support
3. Installs all required build dependencies including:
   - Build tools (gcc, g++, make, cmake)
   - ARM cross-compilation toolchain (gcc-arm-linux-gnueabihf, g++-arm-linux-gnueabihf)
   - Development libraries (libusb, libtinyxml2, libasound2, etc.) for both native and ARM architectures
4. Clones LEDSpicer from GitHub
5. Removes PulseAudio.cpp from CMakeLists.txt (not supported on MiSTer)
6. Copies the ARM toolchain configuration file
7. Builds LEDSpicer with the following CMake options:
   - `-DENABLE_LEDWIZ32=ON`
   - `-DENABLE_MISTER=ON`
   - `-DENABLE_PULSEAUDIO=OFF`
   - Uses ARM cross-compilation toolchain
8. Copies required ARM libraries to the build directory
9. Packages the build directory contents into `LEDSpicer.tar.gz` at `/root/LEDSpicer.tar.gz`

## Build Output

After the build completes, a packaged tar.gz file is created at `/root/LEDSpicer.tar.gz` inside the container. This archive contains all the compiled binaries and required libraries.

**To extract the package:**
```bash
tar -xzf LEDSpicer.tar.gz
```

This will extract to `./LEDSpicer` directory with all the build artifacts ready for deployment.

**To access the tar.gz file from your host machine:**
- Mount a volume when running the container and copy the file:
  ```bash
  docker-compose run -v /path/to/host:/workspace ledspicer /bin/bash
  cp /root/LEDSpicer.tar.gz /workspace/
  ```
- Or use `docker cp` to copy the file from a running container:
  ```bash
  docker cp <container-id>:/root/LEDSpicer.tar.gz ./
  ```

**To copy to MiSTer SD card via Samba:**
Once you have the `LEDSpicer.tar.gz` file on your host machine, you can copy it to your MiSTer SD card by accessing the MiSTer's Samba share (typically at `\\MiSTer\` or `smb://MiSTer/`), then extract it on the MiSTer system.

## Customization

### Changing Build Options

Edit the CMake command in the Dockerfile (line 59) to modify build options:

```dockerfile
RUN cd LEDSpicer && cd build && cmake .. -DCMAKE_CXX_FLAGS='-g0 -O3' -DCMAKE_TOOLCHAIN_FILE=$PWD/toolchain-armv7.cmake -DENABLE_LEDWIZ32=ON -DENABLE_MISTER=ON -DENABLE_PULSEAUDIO=OFF && make -j$(nproc)
```

### Modifying Toolchain

Edit `toolchain-armv7.cmake` to adjust cross-compilation settings.

## Notes

- PulseAudio support is disabled as it's not supported on MiSTer
- The build uses ARM hard-float (armhf) architecture for optimal performance
- The container includes both native and ARM versions of development libraries for proper cross-compilation
