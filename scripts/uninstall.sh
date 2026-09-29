#!/usr/bin/env bash
# Remove exactly the files install-linux.sh / install-macos.sh installed,
# using the manifest written at install time (share/nrsc5/install-manifest.txt).
#
#   scripts/uninstall.sh [--prefix DIR]
#
# Environment: NRSC5_PREFIX overrides the default prefix.
set -Eeuo pipefail
DEFAULT_PREFIX="$HOME/.local"
. "$(dirname "$0")/common.sh"

usage() {
    echo "usage: $(basename "$0") [--prefix DIR]   (default: $DEFAULT_PREFIX; env: NRSC5_PREFIX)"
}

parse_args "$@"
resolve_prefix
[ -f "$MANIFEST" ] || die "no install manifest at $MANIFEST; nothing to uninstall"

count=0
while IFS= read -r f || [ -n "$f" ]; do
    case "$f" in
        *"/../"*) echo "skipping (suspicious path): $f" >&2; continue ;;
        "$PREFIX"/*) ;;
        *) echo "skipping (outside $PREFIX): $f" >&2; continue ;;
    esac
    if [ -e "$f" ] || [ -L "$f" ]; then
        rm -f -- "$f"
        count=$((count + 1))
        echo "removed $f"
    fi
    d="$(dirname "$f")"
    while [ "$d" != "$PREFIX" ] && rmdir "$d" 2>/dev/null; do d="$(dirname "$d")"; done
done < "$MANIFEST"
echo "Uninstalled nrsc5 from $PREFIX ($count files removed)"
