FROM ubuntu:20.04

# Set environment variable to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Add armhf architecture for cross-compilation
RUN dpkg --add-architecture armhf

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
RUN git clone https://github.com/meduzapat/LEDSpicer.git && cd LEDSpicer && git checkout master

# Remove PulseAudio.cpp line from CMakeLists.txt (I cant get it to compile and its not supported on MiSTer anyways)
RUN sed -i '/src\/animations\/PulseAudio\.cpp/d' LEDSpicer/CMakeLists.txt

# Copy toolchain-armv7.cmake file to LEDSpicer build directory
COPY toolchain-armv7.cmake LEDSpicer/build/toolchain-armv7.cmake

# Build LEDSpicer
RUN cd LEDSpicer/build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=staging \
        -DCMAKE_INSTALL_SYSCONFDIR=/etc \
        -DCMAKE_INSTALL_DATADIR=/usr/share \
        -DCMAKE_CXX_FLAGS='-g0 -O3' \
        -DCMAKE_TOOLCHAIN_FILE=$PWD/toolchain-armv7.cmake \
        -DENABLE_LEDWIZ32=ON \
        -DENABLE_MISTER=ON \
        -DENABLE_PULSEAUDIO=OFF && \
    make -j$(nproc) && \
    make install

# Copy Libraries
RUN cp /usr/lib/arm-linux-gnueabihf/libtinyxml2.so.6 /root/LEDSpicer/build/staging/lib/libtinyxml2.so.6
RUN cp /usr/lib/arm-linux-gnueabihf/libasound.so.2 /root/LEDSpicer/build/staging/lib/libasound.so.2

# Package LEDSpicer/build directory contents into tar.gz
RUN mkdir -p /tmp/package/LEDSpicer && \
    cp -r /root/LEDSpicer/build/staging/* /tmp/package/LEDSpicer/ && \
    tar -czf /root/LEDSpicer.tar.gz -C /tmp/package LEDSpicer && \
    rm -rf /tmp/package