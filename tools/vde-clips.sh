#!/bin/bash
# Regenerate the tegra-vde regression clips on the host (x264 via ffmpeg) and push them to the tablet's /tmp.
#   usage: [IP=192.168.1.111] [SRC=~/code/scratch/n9work/vde/src] tools/vde-clips.sh
# testsrc2 content (moving, varied) so every macroblock type gets exercised. Recipes:
#   m_plain  640x360 Baseline (CAVLC, no B)        m_cabac  640x360 Main CABAC, no B
#   m_b      640x360 Main CAVLC, 3 B, b-pyramid    m_bcabac 640x360 Main CABAC, 3 B, b-pyramid
#   f720     1280x720 Main CAVLC, no B             f1080    1920x1080 Main CAVLC, no B (60 frames)
#   m_bnw    m_b without implicit weighted bipred  m_bnwcabac  same, CABAC
#   m_btemp  m_bnw with temporal direct (x264 default weightb=1 means implicit WP -> m_b)
set -eu
IP=${IP:-192.168.1.111}
SRC=${SRC:-$HOME/code/scratch/n9work/vde/src}
mkdir -p "$SRC"
enc() {	# name size seconds x264-params profile
	[ -s "$SRC/$1.mp4" ] && return
	ffmpeg -v error -y -f lavfi -i "testsrc2=size=$2:rate=30:duration=$3" -pix_fmt yuv420p \
		-c:v libx264 -profile:v "$5" -preset medium -x264-params "$4" "$SRC/$1.mp4"
}
enc m_plain  640x360   3 "bframes=0:keyint=30"                                  baseline
enc m_cabac  640x360   3 "cabac=1:bframes=0:keyint=30:weightp=0"                main
enc m_b      640x360   3 "cabac=0:bframes=3:b-pyramid=normal:keyint=30:weightp=0" main
enc m_bcabac 640x360   3 "cabac=1:bframes=3:b-pyramid=normal:keyint=30:weightp=0" main
enc m_bnw      640x360   3 "cabac=0:bframes=3:b-pyramid=normal:keyint=30:weightp=0:weightb=0" main
enc m_bnwcabac 640x360   3 "cabac=1:bframes=3:b-pyramid=normal:keyint=30:weightp=0:weightb=0" main
enc m_btemp  640x360   3 "cabac=0:bframes=3:b-pyramid=normal:keyint=30:weightp=0:weightb=0:direct=temporal" main
enc f720     1280x720  2 "cabac=0:bframes=0:keyint=30:weightp=0"                main
enc f1080    1920x1080 2 "cabac=0:bframes=0:keyint=30:weightp=0"                main
scp -q "$SRC"/*.mp4 root@"$IP":/tmp/
ls -la "$SRC"
