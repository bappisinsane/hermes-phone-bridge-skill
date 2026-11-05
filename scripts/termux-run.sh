#!/usr/bin/env bash
# Run a local shell script inside Termux on the connected Android device.
#
#   termux-run.sh <script-file>
#
# Why this exists: `adb shell` joins its arguments with spaces before handing them to
# the device shell, so quoting a multi-command script by hand is fragile -- a
# mis-quoted `bash -lc '...'` silently runs as the Android `shell` user instead of the
# Termux app. Carrying the script as base64 sidesteps that entirely.
#
# Requires the Termux GitHub build, which sets android:debuggable=true, so
# `adb shell run-as com.termux` yields the Termux app uid.
set -euo pipefail

ADB="${ADB:-$HOME/Desktop/hermes-storage/android-platform-tools/platform-tools/adb.exe}"
PREFIX_DIR="/data/data/com.termux/files/usr"
HOME_DIR="/data/data/com.termux/files/home"

if [ ! -x "$ADB" ] && [ ! -f "$ADB" ]; then
  echo "termux-run.sh: adb not found at $ADB" >&2
  echo "  install platform-tools, or set ADB=/path/to/adb.exe" >&2
  exit 2
fi

if [ $# -lt 1 ]; then
  echo "usage: $0 <script-file>" >&2
  exit 2
fi

SCRIPT="$1"
if [ ! -f "$SCRIPT" ]; then
  echo "termux-run.sh: no such file: $SCRIPT" >&2
  exit 2
fi

B64="$(base64 -w0 < "$SCRIPT")"

"$ADB" shell "run-as com.termux files/usr/bin/bash -c 'export PREFIX=$PREFIX_DIR; export HOME=$HOME_DIR; export PATH=\$PREFIX/bin:\$PATH; export LD_LIBRARY_PATH=\$PREFIX/lib; export LANG=C.UTF-8; export TMPDIR=\$HOME/tmp; mkdir -p \$TMPDIR; echo $B64 | base64 -d | bash -s --'"
