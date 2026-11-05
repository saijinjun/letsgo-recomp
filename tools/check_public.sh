#!/bin/bash
# tools/check_public.sh [ref]: fails when the tree at <ref> (default: the index) holds something a public repository
# must not: game files (exefs/romfs folders, NSO/NCA/NSP/XCI, Switch NSO/NRO/NPDM binaries), console keys, the game
# code library made from the player's exefs (liblasgame.so, lasgame.so/.dll) or any APK/AAB, or any ELF or ZIP file
# that contains liblasgame. Run before pushing; CI runs it too.
set -euo pipefail
cd "$(dirname "$0")/.."
REF=${1:-}
if [ -n "$REF" ]; then files() { git ls-tree -r --name-only "$REF"; }; blob() { git show "$REF:$1"; }
else files() { git ls-files; }; blob() { git show ":$1"; }; fi

bad=0
while IFS= read -r f; do
    case "$f" in
        *.nso|*.nca|*.nsp|*.xci|*.nro|*.npdm|*.keys|*.apk|*.aab|*prod.keys*|*title.keys*) reason="game file, key or APK" ;;
        exefs/*|*/exefs/*|romfs/*|*/romfs/*|extracted/*|extracted-*/*) reason="game data folder" ;;
        *liblasgame.so*|*lasgame.so*|*lasgame.dll*) reason="game code made from the exefs" ;;
        *) reason="" ;;
    esac
    if [ -z "$reason" ]; then
        # contents: Switch executables (NSO0/NRO0/META magics) and ELF/ZIP files carrying the game code library
        magic=$({ blob "$f" || true; } | head -c 4 | od -An -c | tr -d ' \n')
        case "$magic" in
            NSO0|NRO0|META) reason="Switch executable" ;;
            177ELF|PK0034) { blob "$f" || true; } | grep -aq 'liblasgame' && reason="binary holding the game code library" ;;
        esac
    fi
    if [ -n "$reason" ]; then echo "check_public: $f: $reason"; bad=1; fi
done < <(files)
[ $bad = 0 ] && echo "check_public: ok ($(files | wc -l) files)"
exit $bad
