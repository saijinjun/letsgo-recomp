// Let's Go Recomp for Android: SDL's activity running libmain.so (the runtime) on libSDL3.so. The game code,
// liblasgame.so, is inside a personal APK (tools/android/build_game.sh --apk) and the game files are copied into
// Android/data/com.letsgorecomp.android/files/ over USB (runtime/paths.c: the data folder).
package com.letsgorecomp.android;

import org.libsdl.app.SDLActivity;

public class LetsGoActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] {"SDL3", "main"};
    }
}
