#!/usr/bin/env bash
# Builds the Android arm64-v8a libagyp2p.so consumed by the Flutter app via Dart FFI.
# Requires Go (with cgo) and the Android NDK (set ANDROID_NDK_ROOT, or CC to override).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/mobile/android/app/src/main/jniLibs/arm64-v8a"

if [ -z "${CC:-}" ]; then
  : "${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT (or CC) to build libagyp2p.so}"
  HOST_TAG=""
  for tag in linux-x86_64 darwin-x86_64 darwin-arm64 linux-arm64; do
    if [ -d "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$tag" ]; then HOST_TAG="$tag"; break; fi
  done
  [ -n "$HOST_TAG" ] || { echo "No NDK prebuilt toolchain found in $ANDROID_NDK_ROOT" >&2; exit 1; }
  CC="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android24-clang"
fi

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR/server"
CC="$CC" CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
  go build -buildmode=c-shared -trimpath -ldflags="-checklinkname=0 -s -w" \
  -o "$OUT_DIR/libagyp2p.so" ./pkg/mobilebridge
rm -f "$OUT_DIR/libagyp2p.h"
echo "Built $OUT_DIR/libagyp2p.so"
