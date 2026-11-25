#!/bin/sh
# Unpacks Festival and the kal_diphone voice into ~/vc_festival/root WITHOUT installing anything system-wide (no root needed).
set -e
mkdir -p ~/vc_festival/debs ~/vc_festival/root
cd ~/vc_festival/debs
for p in libgomp1 libasound2t64 libpulse0 libsndfile1 libflac14 libogg0 libvorbis0a libvorbisenc2 libopus0 libmpg123-0t64 libmp3lame0 libasyncns0 libxcb1 libx11-6 libxau6 libxdmcp6 libbsd0 libmd0 libdbus-1-3 libwrap0 libsystemd0 libcap2; do apt download $p >/dev/null 2>&1 || echo "skip $p"; done
for d in *.deb; do dpkg -x "$d" ../root; done
cd ..
LD_LIBRARY_PATH=root/usr/lib/x86_64-linux-gnu ldd root/usr/bin/festival | grep 'not found' || echo "all libraries found"
