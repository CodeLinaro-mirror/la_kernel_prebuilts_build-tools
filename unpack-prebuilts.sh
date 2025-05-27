#!/bin/bash -eu

[ "$#" -eq 4 ] || {
  echo "usage: $0 <target dir> linux.zip linux_musl.zip linux_musl_sysroots.zip" >&2
  exit 1
}

TARGET="$1"
LINUX="$2"
LINUX_MUSL="$3"
LINUX_MUSL_SYSROOTS="$4"

function unzip_to() {
    rm -rf "$1"
    mkdir "$1"
    unzip -q -d "$1" "$2"
}

unzip_to "$TARGET"/linux-x86 "$LINUX"
unzip_to "$TARGET"/linux_musl-x86 "$LINUX_MUSL"
unzip_to "$TARGET"/sysroots/x86_64-unknown-linux-musl "$LINUX_MUSL_SYSROOTS"
