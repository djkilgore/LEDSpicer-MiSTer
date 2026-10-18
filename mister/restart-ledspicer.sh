#!/bin/sh
# Restart LEDSpicer and re-enumerate the LED-Wiz on the USB bus. Use this when
# the board stops responding (outputs frozen or dark) instead of rebooting the
# MiSTer. A hard firmware lockup may still need a power cycle.

LS=/media/fat/linux/LEDSpicer

# processLookup starts emitter by name through the shell, so the LEDSpicer
# bin directory must be on PATH.
export PATH="$PATH:/media/fat/linux/LEDSpicer/bin"

echo "Stopping ledspicerd and processLookup..."
for p in $(ps -ef | grep -E "ledspicerd|processLookup" | grep -v grep | awk '{print $1}'); do
	kill "$p" 2>/dev/null
done
sleep 3

# Logical disconnect/reconnect of every LED-Wiz (vendor fafa, product 00f0).
for d in /sys/bus/usb/devices/*; do
	[ -f "$d/idVendor" ] || continue
	if [ "$(cat "$d/idVendor")" = "fafa" ] && [ "$(cat "$d/idProduct")" = "00f0" ]; then
		echo "Re-enumerating LED-Wiz at $d"
		echo 0 > "$d/authorized"
		sleep 1
		echo 1 > "$d/authorized"
	fi
done
sleep 3

echo "Starting ledspicerd (log: /tmp/ledspicerd.log)..."
setsid "$LS/bin/ledspicerd" -f > /tmp/ledspicerd.log 2>&1 < /dev/null &
sleep 2
"$LS/bin/processLookup"
sleep 2
ps -ef | grep -E "ledspicerd|processLookup" | grep -v grep
tail -3 /tmp/ledspicerd.log
