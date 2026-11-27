#!/usr/bin/env bash
# Build libbasalt.so for Android (arm64-v8a).
# Requires:
#   ANDROID_NDK pointing at an NDK (r23+ recommended; r20b works too)
#   OPENCV_ANDROID_SDK pointing at the extracted OpenCV-android-sdk directory

set -euo pipefail

ANDROID_NDK="${ANDROID_NDK:-/home/yuancaimaiyi/xreal_metaloc/posidon/thirdparty/ndk/20.0.5594570}"
OPENCV_ANDROID_SDK="${OPENCV_ANDROID_SDK:-/home/yuancaimaiyi/android-sdks/OpenCV-android-sdk}"
ABI="${ABI:-arm64-v8a}"
API="${API:-24}"
BUILD_DIR="${BUILD_DIR:-build-android-${ABI}}"

[[ -d "$ANDROID_NDK" ]] || { echo "ANDROID_NDK not found: $ANDROID_NDK"; exit 1; }
[[ -d "$OPENCV_ANDROID_SDK/sdk/native/jni" ]] || { echo "OPENCV_ANDROID_SDK invalid: $OPENCV_ANDROID_SDK"; exit 1; }

cmake -S . -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="android-$API" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DBASALT_BUILD_SHARED_LIBRARY_ONLY=ON \
  -DBASALT_INSTANTIATIONS_FLOAT=ON \
  -DBASALT_INSTANTIATIONS_DOUBLE=OFF \
  -DOpenCV_DIR="$OPENCV_ANDROID_SDK/sdk/native/jni"

cmake --build "$BUILD_DIR" -j"$(nproc)"

echo
echo "Built: $BUILD_DIR/libbasalt.so"
file "$BUILD_DIR/libbasalt.so" || true
