#!/bin/bash
# tools/android/build_deps.sh: what the Android app builds against, from pinned sources into build/android/deps
# (arm64-v8a, API 30): an LGPL-only FFmpeg with just what the game's movies need (the configuration of
# tools/linux/build_deps.sh, static), shaderc (GLSL -> SPIR-V, one static library), and the headers: Vulkan, Vulkan
# Memory Allocator, volk (Vulkan loaded at run time). (After LASRecomp-Android-Plus, MIT.) SDL3 is unpacked into
# build/android/SDL3 and built by the app's CMake (android/app/CMakeLists.txt) with its Java sources.
# Each part is skipped when its output exists (delete build/android/deps to redo).
set -euo pipefail
cd "$(dirname "$0")/../.."
S=$PWD/build/android/src
P=$PWD/build/android/deps
W=$PWD/build/android/work
mkdir -p "$S" "$P/include" "$P/lib" "$W"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
API=30

SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$(sed -n 's/^sdk.dir=//p' android/local.properties 2>/dev/null || true)}}
SDK=${SDK:-/opt/homebrew/share/android-commandlinetools}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/27.2.12479018}
[ -d "$NDK" ] || { echo "Android NDK 27.2 not found ($NDK): sdkmanager 'ndk;27.2.12479018'"; exit 1; }
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; *) HOST=linux-x86_64 ;; esac
TC=$NDK/toolchains/llvm/prebuilt/$HOST
CMAKE_ANDROID=(-DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a
               -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_static)

fetch() {  # url sha256 file
    [ -f "$S/$3" ] || { curl -fsSL -o "$S/$3.part" "$1" && mv "$S/$3.part" "$S/$3"; }
    echo "$2  $S/$3" | shasum -a 256 -c --quiet
}
# The other sources come from git at a pinned commit (GitHub's generated archives aren't byte-stable, and ffmpeg.org
# isn't reachable from every build machine): a shallow clone of the tag, checked against the commit.
fetch_git() {  # repo-url tag commit name
    if [ ! -d "$S/$4/.git" ] || [ "$(git -C "$S/$4" rev-parse HEAD)" != "$3" ]; then
        rm -rf "$S/$4" && git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$S/$4"
    fi
    [ "$(git -C "$S/$4" rev-parse HEAD)" = "$3" ] || { echo "deps: $4 $2 is not $3"; exit 1; }
}
unpack() { rm -rf "$W/$2" && mkdir -p "$W/$2" && git -C "$S/$1" archive HEAD | tar -x -C "$W/$2"; }

fetch https://github.com/libsdl-org/SDL/releases/download/release-3.4.18/SDL3-3.4.18.tar.gz \
      9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3 SDL3-3.4.18.tar.gz
fetch_git https://github.com/FFmpeg/FFmpeg n9.0.2 946fcce07b6dcd0331c8cc609192aeff5e1924f8 ffmpeg-9.0.2
fetch_git https://github.com/google/shaderc v2026.3 2c8cae778eec0283b44acbe7ed1a386865d78799 shaderc-2026.3
fetch_git https://github.com/KhronosGroup/Vulkan-Headers vulkan-sdk-1.4.350.1 8864cdc896bbc2a9b6eb36b3218fc9ef57908d77 \
      Vulkan-Headers-1.4.350.1
fetch_git https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator v3.3.0 \
      1d8f600fd424278486eade7ed3e877c99f0846b1 VulkanMemoryAllocator-3.3.0
fetch_git https://github.com/zeux/volk vulkan-sdk-1.4.350.1 3ca312a4f38baa63d8006b6905abbeeb89c8087d volk-1.4.350.1

if [ ! -f build/android/SDL3/CMakeLists.txt ]; then
    rm -rf build/android/SDL3 && mkdir -p build/android/SDL3
    tar -xf "$S/SDL3-3.4.18.tar.gz" -C build/android/SDL3 --strip-components 1
fi
if [ ! -f "$P/include/vulkan/vulkan.h" ]; then
    unpack Vulkan-Headers-1.4.350.1 vulkan-headers
    cp -R "$W/vulkan-headers/include/vulkan" "$W/vulkan-headers/include/vk_video" "$P/include/"
fi
if [ ! -f "$P/include/vma/vk_mem_alloc.h" ]; then
    unpack VulkanMemoryAllocator-3.3.0 vma
    mkdir -p "$P/include/vma" && cp "$W/vma/include/vk_mem_alloc.h" "$P/include/vma/"
fi
if [ ! -f "$P/include/volk/volk.c" ]; then
    unpack volk-1.4.350.1 volk
    mkdir -p "$P/include/volk" && cp "$W/volk/volk.h" "$W/volk/volk.c" "$W/volk/LICENSE.md" "$P/include/volk/"
fi

# FFmpeg: static, LGPL only, just the movies' codecs (WebM: VP9 + Vorbis; the rest as on the other systems)
if [ ! -f "$P/lib/libavcodec.a" ]; then
    unpack ffmpeg-9.0.2 ffmpeg
    (cd "$W/ffmpeg" && ./configure --prefix="$P" --enable-cross-compile --target-os=android --arch=aarch64 \
        --cc="$TC/bin/aarch64-linux-android$API-clang" --cxx="$TC/bin/aarch64-linux-android$API-clang++" \
        --nm="$TC/bin/llvm-nm" --ar="$TC/bin/llvm-ar" --ranlib="$TC/bin/llvm-ranlib" --strip="$TC/bin/llvm-strip" \
        --enable-static --disable-shared --enable-pic --extra-cflags="-O2" \
        --disable-autodetect --disable-programs --disable-doc --disable-network --disable-avdevice --disable-avfilter \
        --disable-swresample --disable-everything \
        --enable-protocol=file --enable-demuxer=matroska,mov \
        --enable-decoder=vp9,vp8,vorbis,opus,h264,aac --enable-parser=vp9,vp8,vorbis,opus,h264,aac \
        && make -j"$JOBS" && make install)
fi
grep -q 'GPL version 3\|--enable-gpl' "$P/lib/pkgconfig/libavcodec.pc" && { echo "deps: FFmpeg is not LGPL"; exit 1; }

# shaderc as one static library (glslang, SPIRV-Tools inside)
if [ ! -f "$P/lib/libshaderc_combined.a" ]; then
    unpack shaderc-2026.3 shaderc
    (cd "$W/shaderc" && python3 utils/git-sync-deps)
    cmake -S "$W/shaderc" -B "$W/shaderc/build" -G Ninja "${CMAKE_ANDROID[@]}" -DCMAKE_BUILD_TYPE=Release \
        -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_TESTS=ON \
        -DSPIRV_SKIP_EXECUTABLES=ON -DENABLE_GLSLANG_BINARIES=OFF -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF
    cmake --build "$W/shaderc/build" --target shaderc_combined -j"$JOBS"
    mkdir -p "$P/include/shaderc"
    cp "$W/shaderc/libshaderc/include/shaderc/"*.h "$P/include/shaderc/"
    cp "$W/shaderc/build/libshaderc/libshaderc_combined.a" "$P/lib/"
    cp "$W/shaderc/LICENSE" "$P/shaderc-LICENSE.txt"
    rm -rf "$W/shaderc"  # (~1 GB of sources and objects)
fi
echo "deps: $P"
