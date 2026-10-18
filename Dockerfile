# Pin to amd64: this is a cross-compile to armhf, so the build host arch
# must not change which apt mirrors are used (see sources.list below).
# Use an ARG (not a literal) so the linter is happy and it stays overridable.
ARG BUILD_PLATFORM=linux/amd64
FROM --platform=${BUILD_PLATFORM} ubuntu:20.04

# Set environment variable to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Add armhf architecture for cross-compilation
RUN dpkg --add-architecture armhf

# armhf packages are NOT on archive.ubuntu.com (amd64/i386 only) -- they live
# on ports.ubuntu.com. Without this split, `apt-get update` 404s on the armhf
# package indexes. Restrict the default mirrors to amd64 and add ports for armhf.
RUN printf '%s\n' \
    'deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ focal main restricted universe multiverse' \
    'deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ focal-updates main restricted universe multiverse' \
    'deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ focal-backports main restricted universe multiverse' \
    'deb [arch=amd64] http://security.ubuntu.com/ubuntu/ focal-security main restricted universe multiverse' \
    'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports/ focal main restricted universe multiverse' \
    'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports/ focal-updates main restricted universe multiverse' \
    'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports/ focal-backports main restricted universe multiverse' \
    'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports/ focal-security main restricted universe multiverse' \
    > /etc/apt/sources.list

# Update package list and install required packages
RUN apt-get update && apt-get install -y \
    build-essential \
    vim \
    git \
    libncurses-dev \
    flex \
    bison \
    openssl \
    libssl-dev \
    dkms \
    libelf-dev \
    libudev-dev \
    libpci-dev \
    libiberty-dev \
    autoconf \
    liblz4-tool \
    bc \
    curl \
    gcc \
    libncurses5-dev \
    lzop \
    make \
    u-boot-tools \
    libgmp3-dev \
    libmpc-dev \
    cmake \
    pkg-config \
    libasound2-dev \
    libtinyxml2-dev \
    libusb-1.0-0-dev \
    libusb-1.0-0-dev:armhf \
    libtinyxml2-dev:armhf \
    libasound2-dev:armhf \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

# Clone LEDSpicer from GitHub
# Pinned to a specific upstream commit for reproducible builds.
# To update: bump LEDSPICER_REF to a newer commit/tag from
# https://github.com/meduzapat/LEDSpicer
# Current pin: 0.7.7 (master as of 2026-10).
ARG LEDSPICER_REF=5c59d19ad48aa9782b0602e1eb4f44b7d14ebcc8
RUN git clone https://github.com/meduzapat/LEDSpicer.git && \
    cd LEDSpicer && git checkout "$LEDSPICER_REF"

# Slow down LED-Wiz USB writes. Upstream waits 1 ms between the four 8-byte
# packets of each frame; the LED-Wiz firmware drops data or hangs when fed that
# fast on current MiSTer kernels (panel stays dark, or the board locks up until
# power-cycled). 10 ms is comfortably safe. The grep makes the build fail loudly
# if upstream renames the constant.
ARG LEDWIZ_WAIT_US=10000
RUN grep -q '#define LEDWIZ_WAIT *1000 ' LEDSpicer/src/devices/GroovyGameGear/LedWiz32.hpp && \
    sed -i "s/#define LEDWIZ_WAIT *1000 /#define LEDWIZ_WAIT            ${LEDWIZ_WAIT_US} /" \
        LEDSpicer/src/devices/GroovyGameGear/LedWiz32.hpp && \
    grep 'define LEDWIZ_WAIT' LEDSpicer/src/devices/GroovyGameGear/LedWiz32.hpp

# Copy toolchain-armv7.cmake file to LEDSpicer build directory
COPY toolchain-armv7.cmake LEDSpicer/build/toolchain-armv7.cmake

# Everything is installed under one directory on the MiSTer SD card. The
# MiSTer root filesystem (linux.img) is mounted read-only and replaced
# wholesale by MiSTer updates, so config, data and plugins must not live in
# /etc or /usr. These paths are compiled into the binaries (config file,
# data dir, devices dir) and used as the shared-library RPATH, so no
# LD_LIBRARY_PATH or -c flag is needed at runtime.
ARG MISTER_PREFIX=/media/fat/linux/LEDSpicer

# Build LEDSpicer and install it into a staging root (DESTDIR).
# ALSA is enabled explicitly: upstream flipped its default to OFF in 0.7.7.
RUN cd LEDSpicer/build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$MISTER_PREFIX" \
        -DCMAKE_INSTALL_SYSCONFDIR="$MISTER_PREFIX/etc" \
        -DCMAKE_INSTALL_RPATH="$MISTER_PREFIX/lib" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DCMAKE_CXX_FLAGS='-g0 -O3' \
        -DCMAKE_TOOLCHAIN_FILE=$PWD/toolchain-armv7.cmake \
        -DENABLE_LEDWIZ32=ON \
        -DENABLE_MISTER=ON \
        -DENABLE_ALSAAUDIO=ON \
        -DENABLE_PULSEAUDIO=OFF && \
    make -j$(nproc) && \
    make install DESTDIR=/tmp/pkgroot

# Bundle runtime libraries the MiSTer Linux image does not ship.
RUN cp /usr/lib/arm-linux-gnueabihf/libtinyxml2.so.6 "/tmp/pkgroot$MISTER_PREFIX/lib/" && \
    cp /usr/lib/arm-linux-gnueabihf/libasound.so.2 "/tmp/pkgroot$MISTER_PREFIX/lib/"

# MiSTer starter configuration (LED-Wiz 32, all outputs on). Shipped under
# examples so re-extracting a newer tarball never clobbers a tuned config.
COPY mister/ /tmp/pkgroot${MISTER_PREFIX}/share/doc/ledspicer/examples/mister/

# Package: extracting LEDSpicer.tar.gz in /media/fat/linux/ yields
# /media/fat/linux/LEDSpicer/{bin,lib,share}.
RUN tar -czf /root/LEDSpicer.tar.gz -C /tmp/pkgroot/media/fat/linux LEDSpicer && \
    rm -rf /tmp/pkgroot
