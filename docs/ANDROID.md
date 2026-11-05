# Let's Go Recomp on Android (work in progress)

A native arm64 Android build of the runtime, after [LASRecomp-Android-Plus](https://github.com/Nycolazs/LASRecomp-Android-Plus)
(MIT), which does the same for LAS Recomp. Status: the app (libmain.so + libSDL3.so) builds with NDK 27.2 and Gradle,
debug and release; it has not been run on a device yet.

## What differs from the desktop builds

- **Guest layout.** Android's zygote maps 0x70_0000_0000, where the Switch layout puts the game. On Android the whole
  guest window sits `GUEST_SHIFT` (0x60_0000_0000) lower (`runtime/cpu.h`). The generator takes `--shift` and writes
  shifted bases while function and label names, patches and hooks keep their Switch addresses.
- **Vulkan through volk** (`VK_NO_PROTOTYPES`): Android's libvulkan exports only the core entry points. `make VOLK=<volk
  checkout>` builds that path on Linux too. The renderer still needs a Vulkan 1.3 driver.
- **Platform layer:** `runtime/platform/android.c`: logcat + `lasrecomp.log`, no re-exec, libmain.so as the executable.
- **Data folder:** `Android/data/com.letsgorecomp.android/files/` (reachable over USB). Put the game files in
  `extracted/` there, the same as on desktop.
- **Touch controls** (`runtime/hle/touch.c`): a floating left stick, A B X Y, L/ZL, R/ZR, - and +, and a settings
  button; other fingers touch the game's screen. They hide when a controller or keyboard is used. `LARECOMP_TOUCH=1`
  shows them on the desktop with the mouse as a finger. The back button opens the menu.
- **Game code:** `liblasgame.so`, built on a computer from your own game files and packed into a personal APK.

## Building (Linux or macOS)

Needs the Android SDK with NDK 27.2.12479018 (and platform 36), CMake, Ninja, git, JDK 17 or newer, Python 3 and Gradle
(or Android Studio). `build_deps.sh` takes SDL3 from its release and the rest from git at pinned commits. The
Gradle wrapper isn't committed: make it once with `cd android && gradle wrapper` (the version is in
`android/gradle/wrapper/gradle-wrapper.properties`).

```
tools/android/build_deps.sh                         # FFmpeg, shaderc, Vulkan headers, VMA, volk, SDL3 sources
(cd android && ./gradlew assembleDebug)             # the app: libmain.so + libSDL3.so
tools/android/build_game.sh extracted --apk         # liblasgame.so from your exefs/, and a personal APK with it
adb install -r build/android/personal/letsgo-personal.apk
```

`liblasgame.so` and the personal APK hold code made from the game: build and install them on your own computer and
device only. They never go into git, CI artifacts, releases or PR attachments (`.gitignore` and `tools/check_public.sh`
guard against it). The app shell from `assembleDebug` alone holds no game code. CI (`.github/workflows/ci.yml`) builds
only the runtime and the app shell, and uploads nothing.

## Not done yet

- Drivers older than Vulkan 1.3 (Android-Plus bundles Mesa Turnip for Adreno 6xx).
- Building the game code on the device; the start screen's game file import (copy the files over USB for now).
- Page write tracking (`plat_watch_writes`): off, as on Linux.
