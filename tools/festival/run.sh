#!/bin/sh
# Usage: run.sh script.scm   (runs Festival from the unpacked ~/vc_festival/root in batch mode)
# Festival's library path is compiled in (/usr/share/festival), so it runs inside a private user+mount namespace
# where an overlay puts the unpacked files there. Nothing is installed or changed system-wide.
R=$HOME/vc_festival/root
U=$HOME/vc_festival/upper
W=$HOME/vc_festival/work
mkdir -p "$U" "$W"
ln -sfn "$R/usr/share/festival" "$U/festival"
export LD_LIBRARY_PATH=$R/usr/lib/x86_64-linux-gnu:$R/usr/lib/x86_64-linux-gnu/pulseaudio
exec unshare -rm sh -c "mount -t overlay overlay -o lowerdir=/usr/share,upperdir=$U,workdir=$W /usr/share && exec $R/usr/bin/festival -b $*"
