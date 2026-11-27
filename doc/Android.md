# Basalt 交叉编译 Android 完整指南

把 Basalt 编成 Android 上可用的 `libbasalt.so`（只包含 VIT interface，无 GUI，无 ROS，无标定工具）。
目标场景：AR 眼镜、手机、嵌入式 Android 设备上的 VIO 运行时。

> 本文档的所有命令都已在本机实测通过。NDK r20b + OpenCV-android-sdk 4.9.0 + arm64-v8a。
> 产物大小：stripped 后 **2.7 MB**。

---

## 一、总体思路

Basalt 原本是研究代码，依赖 Pangolin（OpenGL/EGL GUI）、ROS、opengv、apriltag、realsense 等一堆桌面侧的东西，直接交叉编译到 Android 会被这些拦住。思路是：

1. **开 `BASALT_BUILD_SHARED_LIBRARY_ONLY=ON`**——只产出 `libbasalt.so`（VIT interface），跳过所有工具链和 GUI。
2. **走 Android NDK 工具链交叉编译**，不动 host 侧配置。
3. **几个硬依赖替换**：
   - TBB 用 `thirdparty/oneTBB` 子模块编（NDK 没有系统 TBB）
   - fmt 用 `thirdparty/fmt` 子模块编
   - OpenCV 用 OpenCV Android SDK（手动 wire，不走 find_package）
4. **精度切换成 float**：`-DBASALT_INSTANTIATIONS_FLOAT=ON -DBASALT_INSTANTIATIONS_DOUBLE=OFF`

Basalt 的 `BASALT_BUILD_SHARED_LIBRARY_ONLY` 开关在 main 上已经存在，所有 Android 适配都复用这个开关，不再引入 "Android-only" 的特殊路径，host 侧想要最小 `.so` 一样能用。

---

## 二、前置条件

| 工具 | 版本 | 本机路径（示例） |
|---|---|---|
| Ubuntu | 20.04 | — |
| CMake | ≥ 3.16 | `sudo apt install cmake` |
| Android NDK | **r20b 实测通过**，r23+ 也行 | `/home/yuancaimaiyi/xreal_metaloc/posidon/thirdparty/ndk/20.0.5594570` |
| OpenCV Android SDK | 4.x（4.9.0 实测） | `/home/yuancaimaiyi/android-sdks/OpenCV-android-sdk` |

### 2.1 下载 NDK

如果没有 NDK：

```bash
mkdir -p ~/android-ndks && cd ~/android-ndks
# Google 官方 r20b（约 1GB）
wget https://dl.google.com/android/repository/android-ndk-r20b-linux-x86_64.zip
unzip android-ndk-r20b-linux-x86_64.zip
# 解压后即可用，无需安装
```

### 2.2 下载 OpenCV Android SDK

```bash
mkdir -p ~/android-sdks && cd ~/android-sdks
# OpenCV 4.9.0 Android SDK（约 240MB）
wget https://github.com/opencv/opencv/releases/download/4.9.0/opencv-4.9.0-android-sdk.zip \
     -O opencv-android-sdk.zip
unzip opencv-android-sdk.zip
# 产生 OpenCV-android-sdk/ 目录
```

### 2.3 拉子模块

一定要拉全，Basalt 的 fmt / oneTBB 都在子模块里：

```bash
cd /home/yuancaimaiyi/basalt
git submodule update --init --recursive
```

---

## 三、一键编译

脚本已经写好：`scripts/build_android.sh`。

```bash
export ANDROID_NDK=/home/yuancaimaiyi/xreal_metaloc/posidon/thirdparty/ndk/20.0.5594570
export OPENCV_ANDROID_SDK=/home/yuancaimaiyi/android-sdks/OpenCV-android-sdk
bash scripts/build_android.sh
```

产物：

```
build-android-arm64-v8a/libbasalt.so   # 未 strip 约 241MB（含 debug info）
```

Strip 以后 2.7MB，可以直接部署。

---

## 四、手动编译命令（等价于脚本内容）

```bash
export ANDROID_NDK=/path/to/ndk
export OPENCV_ANDROID_SDK=/path/to/OpenCV-android-sdk

cmake -S . -B build-android-arm64-v8a \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DBASALT_BUILD_SHARED_LIBRARY_ONLY=ON \
  -DBASALT_INSTANTIATIONS_FLOAT=ON \
  -DBASALT_INSTANTIATIONS_DOUBLE=OFF \
  -DOpenCV_DIR=$OPENCV_ANDROID_SDK/sdk/native/jni

cmake --build build-android-arm64-v8a -j$(nproc)
```

**关键参数解释：**

| 参数 | 作用 |
|---|---|
| `CMAKE_TOOLCHAIN_FILE` | 让 CMake 用 NDK 的 clang 而非 host gcc |
| `ANDROID_ABI=arm64-v8a` | 目标 CPU 架构。眼镜/手机一般都是 arm64。32位用 `armeabi-v7a` |
| `ANDROID_PLATFORM=android-24` | 最低 Android API 等级。Android 7.0 = API 24，覆盖率很好 |
| `ANDROID_STL=c++_shared` | 用动态 libc++。若多个 .so 混用必须用 shared |
| `BASALT_BUILD_SHARED_LIBRARY_ONLY=ON` | **核心开关**，跳过所有工具/GUI |
| `BASALT_INSTANTIATIONS_FLOAT=ON` | 开 float 模板 |
| `BASALT_INSTANTIATIONS_DOUBLE=OFF` | 关 double 模板（省编译时间、二进制）|
| `OpenCV_DIR` | OpenCV Android SDK 的 CMake 目录 |

---

## 五、产物验证

```bash
# 1. 架构核对
file build-android-arm64-v8a/libbasalt.so
# 应输出：ELF 64-bit LSB shared object, ARM aarch64, ...

# 2. 导出符号（应该只有 vit_tracker_* 开头）
readelf --dyn-syms build-android-arm64-v8a/libbasalt.so | grep ' vit_tracker_' | head

# 3. 运行时依赖
readelf -d build-android-arm64-v8a/libbasalt.so | grep NEEDED
# 期望输出：
#  libopencv_java4.so
#  libdl.so
#  libm.so
#  libc++_shared.so
#  libc.so
# 不应该有：libpangolin*、libGL*、libX11*、libfortran*
```

TBB 已经**静态链入** `libbasalt.so`，不需要单独发 `libtbb.so`。

---

## 六、部署到 Unity 项目

```bash
STRIP=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/aarch64-linux-android/bin/strip
UNITY_LIBS=/path/to/UnityProject/Assets/Plugins/Android/libs/arm64-v8a

# 1. strip basalt 本体
$STRIP -o $UNITY_LIBS/libbasalt.so build-android-arm64-v8a/libbasalt.so

# 2. 一起拷依赖的 .so
cp $OPENCV_ANDROID_SDK/sdk/native/libs/arm64-v8a/libopencv_java4.so $UNITY_LIBS/
cp $ANDROID_NDK/sources/cxx-stl/llvm-libc++/libs/arm64-v8a/libc++_shared.so $UNITY_LIBS/
```

**注意**：Unity 项目里放的 `.so` 的 ABI 必须和 Build Setting 里勾的 ABI 一致，不匹配会直接 crash。

---

## 七、所有踩过的坑（给未来接手的人）

### 坑 1：OpenCV Android SDK 的 `OpenCVModules.cmake` 和我们的 TBB 冲突

**现象**：`find_package(OpenCV REQUIRED)` 报错
```
Some (but not all) targets in this export set were already defined.
Targets Defined: tbb
Targets not yet defined: libcpufeatures;libjpeg-turbo;...;opencv_core;...
```

**根因**：OpenCV Android SDK 自己带了一个 `libtbb.a`，它的 `OpenCVModules.cmake` 做严格 export set 检查，期望所有 target 都没定义过。但我们的 `thirdparty/oneTBB` 已经先定义了 `tbb`。

**解决**：Android 下**不走** `find_package(OpenCV)`，直接手动 wire：
```cmake
set(OpenCV_INCLUDE_DIRS "${OpenCV_DIR}/include")
set(OpenCV_LIBS "${_opencv_sdk_root}/native/libs/${ANDROID_ABI}/libopencv_java4.so")
```
OpenCV Android SDK 的 `libopencv_java4.so` 是胖库，包含 core/imgproc/calib3d/highgui 全部组件。

> 不能直接复用 OpenCV 自带的 `libtbb.a`，因为 OpenCV Android SDK **没带 TBB headers**，我们的代码 include `<tbb/concurrent_unordered_map.h>` 会直接报 "file not found"。

### 坑 2：Eigen `blas/lapack` 子目录会要求 Fortran

**现象**：
```
Looking for a Fortran compiler - /usr/bin/f95
The Fortran compiler is not able to compile a simple test program.
f95: error: unrecognized command line option '-Qunused-arguments'
```

**根因**：Basalt 自带的 Eigen（`thirdparty/basalt-headers/thirdparty/eigen`）在顶层 `CMakeLists.txt` 里有 `add_subdirectory(blas EXCLUDE_FROM_ALL)`，`blas/CMakeLists.txt` 里 `project(blas Fortran C)` 会在 configure 时启用 Fortran。NDK 没有 Fortran 编译器，host 的 gfortran 又不认识 NDK 的 clang 标志。

**解决**：`thirdparty/CMakeLists.txt` 里在 `add_subdirectory(basalt-headers)` 外面套一层 `add_subdirectory` 宏拦截，遇到 `blas` 或 `lapack` 子目录就跳过：
```cmake
if(ANDROID)
  macro(add_subdirectory _dir)
    if("${_dir}" STREQUAL "blas" OR "${_dir}" STREQUAL "lapack")
      message(STATUS "ANDROID: skipping eigen subdirectory '${_dir}'")
    else()
      _add_subdirectory(${_dir} ${ARGN})
    endif()
  endmacro()
endif()
add_subdirectory(basalt-headers EXCLUDE_FROM_ALL)
```
`EXCLUDE_FROM_ALL` 只影响 build 阶段，不影响 configure，所以不能靠它绕过。

> Posidon 的做法是 `sudo mv /usr/bin/gfortran /usr/bin/gfortran.bk` —— 太暴力，污染 host 环境，不采用。

### 坑 3：Eigen 的 `FindStandardMathLibrary.cmake` 强制清空 flags

**现象**：
```
Performing Test standard_math_library_linked_to_automatically - Failed
Performing Test standard_math_library_linked_to_as_m - Failed
Can't link to the standard math library.
```

**根因**：Eigen 的 `FindStandardMathLibrary.cmake` 第 33 行把 `CMAKE_REQUIRED_FLAGS` 置空，然后用 `CHECK_CXX_SOURCE_COMPILES` 测一段用 `std::sin`/`std::log` 的代码。NDK 的 libc++ 需要显式 C++14 以上才能 `#include <cmath>`，空 flags 等于 C++98 默认模式，直接 fail。

**解决**：patch 文件 `thirdparty/basalt-headers/thirdparty/eigen/cmake/FindStandardMathLibrary.cmake`：
```diff
-set(CMAKE_REQUIRED_FLAGS "")
+set(CMAKE_REQUIRED_FLAGS "-std=c++14")
```

> Posidon 也遇到了这个问题，解决方案一致。

### 坑 4：NDK r20b libc++ 声明了 `<filesystem>` 但没实现符号

**现象**：link 阶段报
```
undefined reference to `std::__ndk1::__fs::filesystem::__remove_all(...)'
undefined reference to `std::__ndk1::__fs::filesystem::directory_iterator::...'
```

**根因**：NDK r20b 的 libc++ 头文件里有 `<filesystem>`，但对应的 `.a`/`.so` 里没编入符号实现（NDK r22+ 才有）。Basalt 的 `src/io/marg_data_io.cpp` 用了 `fs::create_directory` / `fs::directory_iterator` 做 marginalization data 的调试存档。

**解决**：Android 下**排除** `marg_data_io.cpp`（功能是调试存档，运行时不需要），同时在 `src/vit/vit_tracker.cpp` 里把 `MargDataSaver` 的实例化用 `#ifndef BASALT_BUILD_SHARED_LIBRARY_ONLY` 包起来：
```cpp
#ifndef BASALT_BUILD_SHARED_LIBRARY_ONLY
#include <basalt/io/marg_data_io.h>
#endif
...
#ifndef BASALT_BUILD_SHARED_LIBRARY_ONLY
  MargDataSaver::Ptr marg_data_saver;
#endif
```
CMakeLists.txt 里把这个 .cpp 挪进 `if(NOT BASALT_BUILD_SHARED_LIBRARY_ONLY)` 块。

> 如果升级到 NDK r23+，这个限制可能消失，但为了兼容 posidon 已经在用的 r20b 就不升了。

### 坑 5：Pangolin 从 `libbasalt.so` 剥离

**现象**：直接开 `BASALT_BUILD_SHARED_LIBRARY_ONLY=ON` 时，`src/vit/vit_tracker.cpp` 里 include 了 `vit_tracker_ui.hpp`（间接拉进整个 Pangolin），即便 `show_gui=false` 在运行时跳过，**链接期**仍需要 Pangolin 符号。Android 上不可能编 Pangolin。

**解决**：`vit_tracker.cpp` 里 6 处 `ui.*` 调用全部用 `#ifndef BASALT_BUILD_SHARED_LIBRARY_ONLY` 包；`vit_tracker_ui.hpp` include 也包起来；缺失的 `ASSERT`/`ASSERT_` 宏在包里用本地定义补上。另外 `thirdparty/CMakeLists.txt` 里 `add_subdirectory(Pangolin)` 和 `add_subdirectory(opengv)` 整块包进 `if(NOT BASALT_BUILD_SHARED_LIBRARY_ONLY)`，CMakeLists.txt 里 `basalt_internal` 对 pangolin 的 link 也改成条件链接。

**效果**：shared-only 模式下**完全不需要 Pangolin**，host 构建和 Android 构建统一走这一条路径。

### 坑 6：CLI11 的 `std::filesystem` 探测

**现象**：历史上 NDK 旧版本编 CLI11 会在 filesystem 相关代码炸。

**解决**：`-DCLI11_HAS_FILESYSTEM=0`，CLI11 自动改用 POSIX 实现。

### 坑 7：`-march=native` 和 NDK 冲突

**现象**：`-march=native` 让 clang 用 host 的 x86 feature flag，和 NDK 的 arm64 目标互斥。

**解决**：Android 下跳过 `BASALT_MARCH_FLAGS` 的设置，让 NDK toolchain 自己选 `-march`（它会按 `ANDROID_ABI` 选 `armv8-a` 等）。

### 坑 8：`stdc++fs` 不是独立库

**现象**：host Ubuntu 上 `std::filesystem` 要 `-lstdc++fs`，所以 Basalt 默认链这个库。NDK clang 的 libc++ 已经把 filesystem 实现（在 r22+）直接融进 libc++ 本体，再去显式链 `stdc++fs` 会 "library not found"。

**解决**：Android 下清空 `STD_CXX_FS`。

### 坑 9：oneTBB 静态库的 "discouraged" 警告

**现象**：
```
CMake Warning:
You are building oneTBB as a static library.
This is highly discouraged and such configuration is not supported.
```

**根因**：oneTBB 官方推荐动态链接，因为多个 .so 独立链入 TBB 可能导致全局单例（scheduler）重复。

**是否要处理**：**不用**。Basalt 是 **单进程、单 .so 内自用** TBB，没有和其它 TBB 使用者共享的问题，静态链接反而更省心（无需单独发 `libtbb.so`）。这个警告忽略即可。

---

## 八、精度：为什么用 float 不用 double

AR 眼镜/手机场景强烈建议 float：

- **Hexagon/DSP 前端本来就是 fp32**。双精度要在 CPU-DSP 边界做类型转换，白白增加延迟。
- **ARM NEON fp32 吞吐是 fp64 的 2 倍**，内存/cache 占用减半，功耗显著更低——眼镜是热/电关键。
- **Basalt 的数值设计就是 for fp32**：
  - **√BA**（square-root BA）把 Hessian 条件数开根号
  - **FEJ**（First Estimate Jacobian）固定线性化点，避免 marg 累积偏差
  - **逆深度参数化** 压缩深度动态范围
- 实测上 EuRoC/TUM-VI 的 ATE/RPE，float vs double 差距一般在 mm 级，远小于传感器噪声。

什么时候才需要 double：
- 做论文复现的精度基线对拍
- 排查前端数值问题时隔离变量

生产部署：float 就够了。

---

## 九、FAQ

**Q: 7-run-basalt-in-android 这个老分支还要吗？**
A: 不要了。那个分支停更在 2024-07，落后 main 33 个 commits（丢失 VIT 2.0.1、长期关键帧、landmark recall、frontend 重构等）。它的所有 Android 适配都已经前向移植到当前 main，且做得更彻底（Pangolin 剥离、Eigen Fortran/math 规避、marg_data_io 排除等它都没做）。

**Q: Host 构建会不会被影响？**
A: 不会。所有 Android 改动都在 `if(ANDROID)` 或 `if(BASALT_BUILD_SHARED_LIBRARY_ONLY)` 保护下，默认开关 OFF 时主干编译行为和改动前完全一致（已测过 `basalt_internal` host 构建无回归）。

**Q: 想编 32 位 armeabi-v7a 怎么办？**
A: 把脚本里 `ABI=arm64-v8a` 改成 `armeabi-v7a`，重新跑。注意 Unity 侧也要勾对应 ABI。但 AR 眼镜/现代手机基本都是 arm64，32 位场景越来越少。

**Q: 能换成 NDK r23+ 吗？**
A: 可以，脚本会自动适配。换 r23+ 的话 **坑 4**（`std::filesystem` 符号缺失）会自动消失，`marg_data_io.cpp` 可以不再排除。其它改动都保留。

**Q: `libbasalt.so` 241MB 正常吗？**
A: 正常。里面含 debug symbols（RelWithDebInfo 式），strip 后 2.7MB 才是部署尺寸。

**Q: 为什么 TBB 要用 oneTBB 而不是 OpenCV 自带的 libtbb.a？**
A: OpenCV Android SDK 只给了 `.a`，**没给 headers**。我们的代码依赖 `<tbb/concurrent_unordered_map.h>` 等 TBB 头文件，没 header 没法编。

---

## 十、改了什么（代码层面）

本次 Android 支持的改动清单：

- **`CMakeLists.txt`**：加入 7 处 `if(ANDROID)` 分支
- **`thirdparty/CMakeLists.txt`**：`add_subdirectory` 宏拦截 + Pangolin/opengv 包入 `BASALT_BUILD_SHARED_LIBRARY_ONLY` 条件
- **`src/vit/vit_tracker.cpp`**：7 处 `#ifndef BASALT_BUILD_SHARED_LIBRARY_ONLY` 编译期剥离 UI 和 `MargDataSaver`
- **`thirdparty/basalt-headers/thirdparty/eigen/cmake/FindStandardMathLibrary.cmake`**：Eigen math library 探测 patch（1 行）
- **`.gitmodules` + `thirdparty/fmt` + `thirdparty/oneTBB`**：新增两个子模块（fmt 10.2.1、oneTBB v2021.11.0）
- **`scripts/build_android.sh`**：一键编译脚本
- **`doc/Android.md`**：本文档

一次性全部完成，host 构建零回归。
