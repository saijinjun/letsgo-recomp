# Rules for this repository

This repository is public. These rules apply to every commit, branch, PR, release and CI run.

## Merging
- Don't merge to `main` until real CI has run on the PR's head commit and passed. A run that never got a runner (for
  example "account is locked") is not a test result, and neither is a green deploy preview.
- While CI can't run, run the checks in your own session and paste the commands and results into the PR. Still don't
  merge.
- Group small fixes into one PR per batch rather than one PR each.
- Don't schedule routines or wakeups just to poll CI.

## Game data and keys
- Never commit game files: `exefs/`, `romfs/`, `romfs.bin`, NSO/NCA/NSP/XCI files, or anything extracted from them.
- Never commit console keys (`prod.keys`, `title.keys`, `*.keys`).
- Never commit, upload or attach anything made from the game: `liblasgame.so`, `lasgame.so` / `lasgame.dll`, or a
  personal APK built by `tools/android/build_game.sh`. Those are built and installed on the player's own machine only.
  The shell APK from `assembleDebug` alone holds no game code.
- CI builds only the runtime and the Android app shell. It never runs `tools/gen.py` or `build_game.sh` on game files,
  and its artifacts and logs carry nothing from the game.
- Keep the game's and its makers' names, logos and art out of icons, screenshots and user-facing text.
- Run `tools/check_public.sh` before pushing. CI runs it too.

## Credits
Keep the upstream README credits and the existing `LICENSE` (MIT, upstream's) and `LICENSE-LASRecomp`. Don't add a
license that claims rights over upstream code.
