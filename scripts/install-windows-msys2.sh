#!/usr/bin/env bash
# MSYS2 UCRT64 half of install-windows.ps1. Run it through the PowerShell
# script (which finds or installs MSYS2 and opens the UCRT64 shell), or
# directly from an MSYS2 UCRT64 terminal:
#
#   scripts/install-windows-msys2.sh [--prefix DIR] [--no-deps] [--offline-deps DIR]
#
# Installs: bin/libnrsc5.dll (plus any non-system DLLs it needs),
# include/nrsc5.h, lib/pkgconfig/nrsc5.pc
# Environment: NRSC5_PREFIX overrides the default prefix.
set -Eeuo pipefail
DEFAULT_PREFIX="$(cygpath -u "${LOCALAPPDATA:-$HOME/AppData/Local}")/Programs/nrsc5"
. "$(dirname "$0")/common.sh"

[ "${MSYSTEM:-}" = UCRT64 ] || die "run this in the MSYS2 UCRT64 environment (MSYSTEM is '${MSYSTEM:-unset}')"

parse_args "$@"
resolve_prefix

if [ "$NO_DEPS" != 1 ]; then
    step "Installing build dependencies"
    echo "+ pacman -S --needed --noconfirm autoconf automake git make patch tar xz ${MINGW_PACKAGE_PREFIX}-{gcc,cmake,libtool,pkgconf}"
    pacman -S --needed --noconfirm autoconf automake git make patch tar xz \
        "${MINGW_PACKAGE_PREFIX}-gcc" "${MINGW_PACKAGE_PREFIX}-cmake" \
        "${MINGW_PACKAGE_PREFIX}-libtool" "${MINGW_PACKAGE_PREFIX}-pkgconf"
fi
offline_args

# cmake.exe is a native program, so MSYS2 rewrites ACLOCAL_PATH into a
# ';'-separated Windows path list for it; the aclocal run that libusb's
# bootstrap step starts underneath then mis-splits it and fails. Keep it POSIX.
export MSYS2_ENV_CONV_EXCL="ACLOCAL_PATH${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"

# A checkout made by Git for Windows usually has CRLF line endings, which this
# MSYS2 git would report as modifications ("-dirty" in the version). Treat CRLF
# as Git for Windows does.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=true

# Same flags as support/msys2-build, plus the library-only options.
configure_build_install -G "MSYS Makefiles" \
    -DUSE_STATIC=ON \
    -DUSE_SYSTEM_LIBUSB=OFF -DUSE_SYSTEM_RTLSDR=OFF -DUSE_SYSTEM_LIBAO=OFF -DUSE_SYSTEM_FFTW=OFF \
    -DUSE_SSE=ON

# Bundle every non-system DLL the library needs so that bin/ works when loaded
# from its own directory. A dependency is a system DLL when it is not shipped
# in the UCRT64 bin directory (kernel32, ws2_32, api-ms-win-crt-*, ...).
step "Checking runtime dependencies"
dll="$PREFIX/bin/libnrsc5.dll"
[ -f "$dll" ] || die "library not installed: $dll"
extras=()
queue=("$dll")
seen=" "
while [ "${#queue[@]}" -gt 0 ]; do
    f="${queue[0]}"
    queue=("${queue[@]:1}")
    echo "+ objdump -p $(basename "$f") | grep \"DLL Name\""
    deps="$(objdump -p "$f" | grep "DLL Name" | sed 's/.*DLL Name: *//' | tr -d '\r')"
    echo "$deps" | sed 's/^/    /'
    for name in $deps; do
        case "$seen" in *" $name "*) continue ;; esac
        seen="$seen$name "
        if [ -f "$MINGW_PREFIX/bin/$name" ]; then
            cp -f "$MINGW_PREFIX/bin/$name" "$PREFIX/bin/$name"
            extras+=("$(native_path "$PREFIX/bin/$name")")
            queue+=("$PREFIX/bin/$name")
            echo "bundled $name"
        fi
    done
done

write_manifest ${extras[@]+"${extras[@]}"}
verify "$PREFIX_NATIVE/bin/libnrsc5.dll" "$PREFIX_NATIVE/include/nrsc5.h" "$PREFIX_NATIVE/lib/pkgconfig/nrsc5.pc"
if [ -n "${NRSC5_RESULT_FILE:-}" ]; then printf 'OK\n' > "$(cygpath -u "$NRSC5_RESULT_FILE")"; fi
