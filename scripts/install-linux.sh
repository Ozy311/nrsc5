#!/usr/bin/env bash
# Build the NRSC-5 digital broadcast receiver library from source and install
# it into a per-user prefix (default: $HOME/.local).
#
#   scripts/install-linux.sh [--prefix DIR] [--no-deps] [--offline-deps DIR]
#
# Installs: lib/libnrsc5.so, include/nrsc5.h, lib/pkgconfig/nrsc5.pc
# Environment: NRSC5_PREFIX overrides the default prefix.
set -Eeuo pipefail
DEFAULT_PREFIX="$HOME/.local"
. "$(dirname "$0")/common.sh"

install_deps() {
    local sudo="" pm
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 || die "root or sudo is needed to install packages; install the dependencies yourself and re-run with --no-deps"
        sudo="sudo"
    fi
    run() { echo "+ $*"; "$@"; }
    step "Installing build dependencies (sudo is only used for this step)"
    if command -v apt-get >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        run $sudo apt-get update
        # shellcheck disable=SC2086
        run $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            build-essential cmake autoconf automake libtool git patch pkg-config \
            libfftw3-dev librtlsdr-dev libusb-1.0-0-dev
    elif command -v dnf >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        run $sudo dnf install -y \
            gcc make cmake autoconf automake libtool git patch pkgconf-pkg-config \
            fftw-devel rtl-sdr-devel libusb1-devel
    elif command -v zypper >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        run $sudo zypper --non-interactive install \
            gcc make cmake autoconf automake libtool git patch pkg-config \
            fftw3-devel rtl-sdr-devel libusb-1_0-devel
    elif command -v pacman >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        run $sudo pacman -S --needed --noconfirm \
            base-devel cmake git fftw rtl-sdr libusb pkgconf
    else
        pm="apt, dnf, zypper or pacman"
        die "no supported package manager found ($pm); install cmake, autoconf, automake, libtool, fftw, rtl-sdr, libusb, git, patch and pkg-config yourself and re-run with --no-deps"
    fi
}

parse_args "$@"
resolve_prefix
[ "$NO_DEPS" = 1 ] || install_deps
offline_args
configure_build_install
write_manifest
verify "$PREFIX/lib/libnrsc5.so" "$PREFIX/include/nrsc5.h" "$PREFIX/lib/pkgconfig/nrsc5.pc"
echo
echo "To use the library from other software, point it at $PREFIX/lib/pkgconfig (PKG_CONFIG_PATH)"
echo "or load $PREFIX/lib/libnrsc5.so by absolute path; $PREFIX/lib is not on the default loader path."
