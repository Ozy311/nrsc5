# Shared helpers for install-linux.sh, install-macos.sh and
# install-windows-msys2.sh (the MSYS2 half of install-windows.ps1).
# Sourced, not run directly. Written for bash 3.2 (macOS /bin/bash).

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SRC_DIR/build-lib"

PREFIX="${NRSC5_PREFIX:-}"
NO_DEPS="${NRSC5_NO_DEPS:-0}"
OFFLINE_DEPS="${NRSC5_OFFLINE_DEPS:-}"
OFFLINE_ARGS=()

trap 'echo "error: command failed (line $LINENO): $BASH_COMMAND" >&2' ERR

die() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo "==> $*"
}

is_msys() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
        *) return 1 ;;
    esac
}

# Path in the form the native tools (cmake, gcc) expect.
native_path() {
    if is_msys; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

usage() {
    cat <<EOF
usage: $(basename "$0") [--prefix DIR] [--no-deps] [--offline-deps DIR]

  --prefix DIR         install into DIR (default: $DEFAULT_PREFIX; env: NRSC5_PREFIX)
  --no-deps            do not install build dependencies
  --offline-deps DIR   build from local sources instead of downloading them:
                       DIR/faad2  DIR/fftw-3.3.10.tar.gz  DIR/libusb  DIR/rtl-sdr
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefix)
                [ $# -ge 2 ] || die "--prefix needs a directory"
                PREFIX="$2"; shift 2 ;;
            --prefix=*)
                PREFIX="${1#*=}"; shift ;;
            --no-deps)
                NO_DEPS=1; shift ;;
            --offline-deps)
                [ $# -ge 2 ] || die "--offline-deps needs a directory"
                OFFLINE_DEPS="$2"; shift 2 ;;
            --offline-deps=*)
                OFFLINE_DEPS="${1#*=}"; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                usage >&2; die "unknown option: $1" ;;
        esac
    done
}

# Turn a user-supplied path into an absolute path without requiring it to exist.
absolute_path() {
    local p="$1"
    if is_msys; then p="$(cygpath -u "$p")"; fi
    case "$p" in
        "~"|"~/"*) p="$HOME${p#\~}" ;;
    esac
    case "$p" in
        /*) ;;
        *) p="$PWD/$p" ;;
    esac
    printf '%s\n' "$p"
}

# Sets PREFIX (absolute, POSIX spelling) and PREFIX_NATIVE.
resolve_prefix() {
    PREFIX="$(absolute_path "${PREFIX:-$DEFAULT_PREFIX}")"
    while [ "${#PREFIX}" -gt 1 ] && [ "${PREFIX%/}" != "$PREFIX" ]; do PREFIX="${PREFIX%/}"; done
    PREFIX_NATIVE="$(native_path "$PREFIX")"
    MANIFEST="$PREFIX/share/nrsc5/install-manifest.txt"
}

job_count() {
    nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2
}

# Fills OFFLINE_ARGS with the -D options for --offline-deps.
offline_args() {
    OFFLINE_ARGS=()
    [ -n "$OFFLINE_DEPS" ] || return 0
    local dir
    dir="$(absolute_path "$OFFLINE_DEPS")"
    [ -d "$dir" ] || die "--offline-deps: $dir is not a directory"
    [ -d "$dir/faad2" ] || die "--offline-deps: $dir/faad2 is missing (FAAD2 2.11.2 checkout)"
    local tag
    tag="$(git -C "$dir/faad2" describe --tags 2>/dev/null || true)"
    [ "$tag" = "2.11.2" ] || echo "warning: $dir/faad2 is at '${tag:-unknown}', the HDC patch expects tag 2.11.2" >&2
    OFFLINE_ARGS+=("-DFAAD2_SOURCE_DIR=$(native_path "$dir/faad2")")
    if [ -f "$dir/fftw-3.3.10.tar.gz" ]; then
        OFFLINE_ARGS+=("-DFFTW_TARBALL=$(native_path "$dir/fftw-3.3.10.tar.gz")")
    else
        echo "note: $dir/fftw-3.3.10.tar.gz not found; fftw is downloaded only if the system one is missing" >&2
    fi
    if [ -d "$dir/libusb" ]; then
        OFFLINE_ARGS+=("-DLIBUSB_SOURCE_DIR=$(native_path "$dir/libusb")")
    else
        echo "note: $dir/libusb not found; libusb is downloaded only if the system one is missing" >&2
    fi
    if [ -d "$dir/rtl-sdr" ]; then
        OFFLINE_ARGS+=("-DRTLSDR_SOURCE_DIR=$(native_path "$dir/rtl-sdr")")
    else
        echo "note: $dir/rtl-sdr not found; rtl-sdr is downloaded only if the system one is missing" >&2
    fi
}

# configure_build_install [extra cmake args...]
configure_build_install() {
    cd "$SRC_DIR"
    step "Configuring"
    cmake -S . -B build-lib -DCMAKE_BUILD_TYPE=Release -DUSE_FAAD2=ON -DBUILD_CLI=OFF \
        -DCMAKE_INSTALL_PREFIX="$PREFIX_NATIVE" \
        ${OFFLINE_ARGS[@]+"${OFFLINE_ARGS[@]}"} "$@"
    step "Building"
    cmake --build build-lib -j "$(job_count)"
    OLD_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/nrsc5-manifest.XXXXXX")"
    if [ -f "$MANIFEST" ]; then cp "$MANIFEST" "$OLD_MANIFEST"; else : > "$OLD_MANIFEST"; fi
    step "Installing into $PREFIX_NATIVE"
    cmake --install build-lib
}

# write_manifest [extra installed files...]
# Records every installed file, then removes files a previous install left
# behind that this one no longer produces.
write_manifest() {
    local new f
    new="$(mktemp "${TMPDIR:-/tmp}/nrsc5-manifest.XXXXXX")"
    mkdir -p "$(dirname "$MANIFEST")"
    {
        cat "$BUILD_DIR/install_manifest.txt"
        echo
        for f in ${@+"$@"}; do echo "$f"; done
        native_path "$MANIFEST"
    } | grep -v '^$' > "$new"
    while IFS= read -r f || [ -n "$f" ]; do
        if ! grep -Fxq -- "$f" "$new"; then
            case "$f" in
                "$PREFIX_NATIVE"/*) rm -f -- "$f" ;;
            esac
        fi
    done < "$OLD_MANIFEST"
    mv "$new" "$MANIFEST"
    rm -f "$OLD_MANIFEST"
    echo "Install manifest: $(native_path "$MANIFEST")"
}

# verify LIBRARY_PATH HEADER_PATH PC_PATH
# Builds scripts/smoketest.c against the installed header and runs it against
# the installed library, then prints the final summary.
verify() {
    local lib="$1" header="$2" pc="$3" cc exe="" ldl="" pcdir pc_version pc_commit out lib_version
    [ -f "$lib" ] || die "library not installed: $lib"
    [ -f "$header" ] || die "header not installed: $header"
    [ -f "$pc" ] || die "pkg-config file not installed: $pc"

    step "Verifying"
    local pkgconf
    pkgconf="$(command -v pkg-config || command -v pkgconf || true)"
    [ -n "$pkgconf" ] || die "pkg-config not found"
    pcdir="$PREFIX/lib/pkgconfig"
    export PKG_CONFIG_PATH="$pcdir${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    pc_version="$("$pkgconf" --modversion nrsc5)" || die "pkg-config cannot find nrsc5 in $pcdir"
    pc_commit="$("$pkgconf" --variable=nrsc5_commit nrsc5)"

    if is_msys; then cc="${CC:-gcc}"; exe=".exe"; else cc="${CC:-cc}"; fi
    if [ "$(uname -s)" = Linux ]; then ldl="-ldl"; fi
    # shellcheck disable=SC2046
    "$cc" -O1 -Wall "$SCRIPT_DIR/smoketest.c" -o "$BUILD_DIR/smoketest$exe" \
        $("$pkgconf" --cflags nrsc5) $ldl || die "smoke test failed to compile against $header"
    out="$(cd "$BUILD_DIR" && ./smoketest"$exe" "$lib")" || die "smoke test failed for $lib"
    echo "$out"
    lib_version="$(printf '%s\n' "$out" | sed -n 's/^version: //p')"
    if [ "$pc_commit" != unknown ] && [ "$lib_version" != unknown ]; then
        case "$pc_commit" in
            "$lib_version"*) ;;
            *) die "library reports commit $lib_version but nrsc5.pc records $pc_commit" ;;
        esac
    fi

    echo
    echo "Prefix:      $PREFIX_NATIVE"
    echo "Library:     $lib"
    echo "Header:      $header"
    echo "pkg-config:  $pc"
    echo "Version:     $pc_version (commit $pc_commit)"
    echo "OK"
}
