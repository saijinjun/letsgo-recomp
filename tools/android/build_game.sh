#!/bin/bash
# tools/android/build_game.sh <game folder> [--apk] [--push]: the game code library for the Android app, from your own
# game files (the folder holding exefs/, or exefs/ itself). On this computer: the generator (tools/gen.py, with the
# Android address shift) turns exefs/main, sdk, subsdk0 and subsdk1 into C, the NDK compiles that into liblasgame.so
# (build/android/gamelib/arm64-v8a/), linked against the app's own libmain.so (build the app first:
# cd android && ./gradlew assembleDebug).
#   --apk   also build a personal APK with it inside (build/android/personal/letsgo-personal.apk)
#   --push  copy it into the app on the device connected over adb (debug builds: run-as)
# The result holds code made from the game: keep it on your own computer and device. Never commit, upload or attach
# liblasgame.so or the personal APK (git, CI artifacts, releases, PRs).
# (After LASRecomp-Android-Plus' tools/android/build_game.sh, MIT.)
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
GAME=${1:?usage: tools/android/build_game.sh <game folder> [--apk] [--push]}
shift
APK=0 PUSH=0
for a in "$@"; do case $a in --apk) APK=1 ;; --push) PUSH=1 ;; *) echo "unknown option $a"; exit 1 ;; esac; done

EXEFS=$GAME
[ -f "$EXEFS/main" ] || EXEFS=$GAME/exefs
for m in main sdk subsdk0 subsdk1; do [ -f "$EXEFS/$m" ] || { echo "no exefs/$m in $GAME"; exit 1; }; done
EXEFS=$(cd "$EXEFS" && pwd)  # (the generator runs in tools/)

SDK=${ANDROID_HOME:-$(sed -n 's/^sdk.dir=//p' android/local.properties 2>/dev/null || true)}
SDK=${SDK:-$HOME/Android/Sdk}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/27.2.12479018}
case "$(uname -s)" in Darwin) HOST=darwin-x86_64; JOBS=$(sysctl -n hw.ncpu) ;; *) HOST=linux-x86_64; JOBS=$(nproc) ;; esac
CC="$NDK/toolchains/llvm/prebuilt/$HOST/bin/aarch64-linux-android30-clang"
[ -x "$CC" ] || { echo "Android NDK 27.2 not found ($NDK)"; exit 1; }
MAINLIB=$(ls -t android/app/build/intermediates/cxx/*/*/obj/arm64-v8a/libmain.so 2>/dev/null | head -1 || true)
[ -n "$MAINLIB" ] || { echo "build the app first: cd android && ./gradlew assembleDebug"; exit 1; }

# the generator's Python (capstone, unicorn, lz4)
VENV=build/android/venv
if [ ! -x "$VENV/bin/python" ]; then
    "$(command -v python3.12 || command -v python3.11 || command -v python3)" -m venv "$VENV"
    "$VENV/bin/pip" install -q capstone==5.0.9 unicorn==2.1.4 lz4==4.4.5
fi

# (the runtime's gamelib_id(): GAMELIB_ID + "-" + the CPU level, "base" on arm64; runtime/gamelib.c)
ID=$(tools/android/gamelib_id.sh)-base
FLAGS=$(tools/android/gamelib_id.sh --flags)
GENARGS=$(tools/android/gamelib_id.sh --gen-args)
GEN=build/android/gen
OBJ=build/android/gen-obj
OUT=build/android/gamelib/arm64-v8a
mkdir -p "$GEN" "$OBJ" "$OUT"

echo "== generating C (game code id $ID)"
# (the bases are the Switch layout's, as in the Makefile's gen target; --shift moves them, runtime/rt.h)
(cd tools && "$ROOT/$VENV/bin/python" gen.py sdk "$EXEFS/sdk" 0x7004000000 "$ROOT/$GEN/sdk" --hle ../runtime/hle/hle_symbols.txt \
    $GENARGS)
(cd tools && "$ROOT/$VENV/bin/python" gen.py main "$EXEFS/main" 0x7000000000 "$ROOT/$GEN/main" $GENARGS)
(cd tools && "$ROOT/$VENV/bin/python" gen.py subsdk0 "$EXEFS/subsdk0" 0x7006000000 "$ROOT/$GEN/subsdk0" $GENARGS)
(cd tools && "$ROOT/$VENV/bin/python" gen.py subsdk1 "$EXEFS/subsdk1" 0x7008000000 "$ROOT/$GEN/subsdk1" $GENARGS)

echo "== compiling ($JOBS jobs)"
compile() {  # <source> <object>
    [ "$2" -nt "$1" ] && [ "$2" -nt runtime/cpu.h ] && [ "$2" -nt tools/android/gamelib_id.sh ] && return 0
    "$CC" $FLAGS -c "$1" -o "$2.tmp" && mv "$2.tmp" "$2"
}
export -f compile
export CC FLAGS
# the largest first (no long file left alone at the end)
ls -S "$GEN"/sdk/*.c "$GEN"/main/*.c "$GEN"/subsdk0/*.c "$GEN"/subsdk1/*.c |
    while read -r c; do echo "$c $OBJ/$(basename "$(dirname "$c")")_$(basename "$c" .c).o"; done |
    xargs -P "$JOBS" -n 2 bash -c 'compile "$0" "$1" || exit 255'
"$CC" $FLAGS -DGAMELIB_ID="\"$ID\"" -c tools/gamelib_entry.c -o "$OBJ/gamelib_entry.o"

# (objects of chunks the generator no longer writes - another split into files - would define functions twice)
for o in "$OBJ"/*_*.o; do
    b=$(basename "$o" .o); m=${b%%_*}
    case $m in main|sdk|subsdk0|subsdk1) [ -e "$GEN/$m/${b#*_}.c" ] || rm -f "$o" ;; esac
done
echo "== linking"
# DT_NEEDED libmain.so: the runtime functions the game code calls are the app's own (it is loaded first)
"$CC" -shared -fuse-ld=lld -Wl,-z,max-page-size=16384 -Wl,-Bsymbolic -Wl,-soname,liblasgame.so \
    -o "$OUT/liblasgame.so.tmp" "$OBJ"/*.o -L"$(dirname "$MAINLIB")" -lmain
mv "$OUT/liblasgame.so.tmp" "$OUT/liblasgame.so"
echo "$ID" > "$OUT/liblasgame.so.id"
ls -la "$OUT/liblasgame.so"

if [ $APK = 1 ]; then
    echo "== personal APK"
    (cd android && ./gradlew assembleDebug -q -PlasGameLib="$ROOT/build/android/gamelib")
    # moved out of Gradle's output folder, so the shell APK's path never holds one with the game code inside
    mkdir -p build/android/personal
    mv android/app/build/outputs/apk/debug/app-debug.apk build/android/personal/letsgo-personal.apk
    ls -la build/android/personal/letsgo-personal.apk
fi
if [ $PUSH = 1 ]; then
    echo "== into the app on the device"
    PKG=com.letsgorecomp.android
    adb push "$OUT/liblasgame.so" "$OUT/liblasgame.so.id" /data/local/tmp/
    adb shell "run-as $PKG cp /data/local/tmp/liblasgame.so /data/local/tmp/liblasgame.so.id files/ &&
               rm /data/local/tmp/liblasgame.so /data/local/tmp/liblasgame.so.id"
    adb shell "run-as $PKG ls -la files/liblasgame.so files/liblasgame.so.id"
fi
