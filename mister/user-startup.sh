#!/bin/sh
# MiSTer runs /media/fat/linux/user-startup.sh at boot. LEDSpicer lives
# entirely on the SD card under /media/fat/linux/LEDSpicer (the MiSTer root
# filesystem is read-only). Library paths are compiled in (RPATH), so no
# LD_LIBRARY_PATH is needed.

echo "***" $1 "***"

# processLookup starts emitter by name through the shell, so the LEDSpicer
# bin directory must be on PATH.
export PATH="$PATH:/media/fat/linux/LEDSpicer/bin"

# ledspicerd runs in foreground mode (-f) detached with setsid: it keeps its
# log in /tmp (a tmpfs, cleared on boot) and avoids forking after the USB
# device is open, which libusb does not guarantee to be safe.
setsid /media/fat/linux/LEDSpicer/bin/ledspicerd -f > /tmp/ledspicerd.log 2>&1 < /dev/null &
sleep 2
/media/fat/linux/LEDSpicer/bin/processLookup
