#!/usr/bin/env bash
# Build the NRSC-5 digital broadcast receiver library from source and install
# it into a per-user prefix (default: $HOME/.local). Build dependencies come
# from Homebrew.
#
#   scripts/install-macos.sh [--prefix DIR] [--no-deps] [--offline-deps DIR]
#
# Installs: lib/libnrsc5.dylib, include/nrsc5.h, lib/pkgconfig/nrsc5.pc
# Environment: NRSC5_PREFIX overrides the default prefix.
set -Eeuo pipefail
DEFAULT_PREFIX="$HOME/.local"
. "$(dirname "$0")/common.sh"

install_deps() {
    if ! command -v brew >/dev/null 2>&1; then
        cat >&2 <<'MSG'
Homebrew is required to install the build dependencies but was not found.
Install it with the official one-liner, then re-run this script:

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

(or install cmake, autoconf, automake, libtool, pkgconf, fftw, librtlsdr and
libusb yourself and re-run with --no-deps)
MSG
        exit 1
    fi
    step "Installing build dependencies with Homebrew"
    echo "+ brew install cmake autoconf automake libtool pkgconf fftw librtlsdr libusb"
    brew install cmake autoconf automake libtool pkgconf fftw librtlsdr libusb
}

parse_args "$@"
resolve_prefix
[ "$NO_DEPS" = 1 ] || install_deps
offline_args

cmake_args=(-DCMAKE_INSTALL_NAME_DIR="$PREFIX_NATIVE/lib" -DCMAKE_OSX_ARCHITECTURES="$(uname -m)")
if command -v brew >/dev/null 2>&1; then
    cmake_args+=(-DCMAKE_PREFIX_PATH="$(brew --prefix)")
fi
configure_build_install "${cmake_args[@]}"

# The install name must be absolute so consumers can load the library from
# anywhere without an rpath.
dylib="$PREFIX/lib/libnrsc5.dylib"
if [ "$(otool -D "$dylib" | tail -n 1)" != "$dylib" ]; then
    install_name_tool -id "$dylib" "$dylib"
fi
[ "$(otool -D "$dylib" | tail -n 1)" = "$dylib" ] || die "install name of $dylib is not absolute"
echo "Install name: $dylib"

write_manifest
verify "$dylib" "$PREFIX/include/nrsc5.h" "$PREFIX/lib/pkgconfig/nrsc5.pc"
echo
echo "To use the library from other software, point it at $PREFIX/lib/pkgconfig (PKG_CONFIG_PATH)"
echo "or load $dylib by absolute path."
