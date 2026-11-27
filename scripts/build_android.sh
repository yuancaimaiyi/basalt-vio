#!/usr/bin/env bash
# One-shot cross-compile of libbasalt.so for Android.
#
# Required environment variables:
#   ANDROID_NDK          Path to Android NDK (r20b and newer both work).
#   OPENCV_ANDROID_SDK   Path to extracted OpenCV-android-sdk/ directory.
#
# Optional:
#   ABI        Target ABI (default: arm64-v8a).
#   API        Minimum Android API level (default: 24, i.e. Android 7.0).
#   BUILD_DIR  Output directory (default: build-android-${ABI}).
#
# Usage from a fresh clone:
#   git submodule update --init --recursive
#   export ANDROID_NDK=/path/to/android-ndk
#   export OPENCV_ANDROID_SDK=/path/to/OpenCV-android-sdk
#   bash scripts/build_android.sh

set -euo pipefail

# Always run from repo root, regardless of where the script was invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ABI="${ABI:-arm64-v8a}"
API="${API:-24}"
BUILD_DIR="${BUILD_DIR:-build-android-${ABI}}"

# ---- sanity checks -----------------------------------------------------------

if [[ -z "${ANDROID_NDK:-}" ]]; then
  cat >&2 <<EOF
ERROR: ANDROID_NDK is not set.

Download the NDK (r20b works, r23+ also fine) from Google:
  https://dl.google.com/android/repository/android-ndk-r20b-linux-x86_64.zip

Then:
  export ANDROID_NDK=/path/to/android-ndk-r20b
  bash scripts/build_android.sh
EOF
  exit 1
fi

if [[ ! -f "$ANDROID_NDK/build/cmake/android.toolchain.cmake" ]]; then
  echo "ERROR: ANDROID_NDK does not look like a valid NDK: $ANDROID_NDK" >&2
  echo "       Expected: \$ANDROID_NDK/build/cmake/android.toolchain.cmake" >&2
  exit 1
fi

if [[ -z "${OPENCV_ANDROID_SDK:-}" ]]; then
  cat >&2 <<EOF
ERROR: OPENCV_ANDROID_SDK is not set.

Download OpenCV Android SDK 4.x from:
  https://github.com/opencv/opencv/releases/download/4.9.0/opencv-4.9.0-android-sdk.zip

Then:
  unzip opencv-4.9.0-android-sdk.zip
  export OPENCV_ANDROID_SDK=/path/to/OpenCV-android-sdk
  bash scripts/build_android.sh
EOF
  exit 1
fi

if [[ ! -d "$OPENCV_ANDROID_SDK/sdk/native/jni" ]]; then
  echo "ERROR: OPENCV_ANDROID_SDK does not look valid: $OPENCV_ANDROID_SDK" >&2
  echo "       Expected: \$OPENCV_ANDROID_SDK/sdk/native/jni/OpenCVConfig.cmake" >&2
  exit 1
fi

if [[ ! -f "$OPENCV_ANDROID_SDK/sdk/native/libs/$ABI/libopencv_java4.so" ]]; then
  echo "ERROR: OpenCV lib for ABI=$ABI not found:" >&2
  echo "       $OPENCV_ANDROID_SDK/sdk/native/libs/$ABI/libopencv_java4.so" >&2
  exit 1
fi

# Verify submodules are initialized. Spot-check the two Android-specific ones
# plus basalt-headers (always needed).
for sub in thirdparty/fmt thirdparty/oneTBB thirdparty/basalt-headers; do
  if [[ ! -f "$sub/CMakeLists.txt" ]]; then
    cat >&2 <<EOF
ERROR: Submodule '$sub' is not initialized.

Run once after cloning:
  git submodule update --init --recursive

Then rerun this script.
EOF
    exit 1
  fi
done

# ---- configure & build -------------------------------------------------------

echo "=== Basalt Android build ==="
echo "  NDK:      $ANDROID_NDK"
echo "  OpenCV:   $OPENCV_ANDROID_SDK"
echo "  ABI:      $ABI"
echo "  API:      android-$API"
echo "  Output:   $BUILD_DIR/"
echo

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

# ---- summary + stripped artifact --------------------------------------------

LIB="$BUILD_DIR/libbasalt.so"
STRIP="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/aarch64-linux-android/bin/strip"

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: expected output not found: $LIB" >&2
  exit 1
fi

echo
echo "=== Built ==="
echo "  Unstripped: $LIB ($(du -h "$LIB" | cut -f1))"
file "$LIB" | sed 's/^/  /'

if [[ -x "$STRIP" ]]; then
  STRIPPED="${LIB%.so}_stripped.so"
  "$STRIP" -o "$STRIPPED" "$LIB"
  echo "  Stripped:   $STRIPPED ($(du -h "$STRIPPED" | cut -f1))"
else
  echo "  (strip tool not found at $STRIP; produce stripped version manually)"
fi
