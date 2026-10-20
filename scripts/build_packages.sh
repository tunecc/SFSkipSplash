#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${TMPDIR:-/tmp}/SFSkipSplash-build-packages"
OUT_DIR="$ROOT_DIR/out"
DISPLAY_NAME="SFSkipSplash"
THEOS="${THEOS:-/opt/theos}"
export THEOS
export PATH="$THEOS/bin:$PATH"

# Theos 不支持含空格路径: 在无空格副本中构建
WORK_ROOT="${TMPDIR:-/tmp}/SFSkipSplash-work"
rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"
cp "$ROOT_DIR/Makefile" "$ROOT_DIR/control" "$ROOT_DIR/Tweak.xm" \
    "$ROOT_DIR/SFSkipSplash.plist" "$WORK_ROOT/"

shopt -s nullglob

clean_host_metadata() {
    local target_path
    for target_path in "$@"; do
        [ -e "$target_path" ] || continue
        find "$target_path" -type f \( -name '.DS_Store' -o -name '._*' \) -delete
        find "$target_path" -name '__MACOSX' -type d -prune -exec rm -rf {} +
    done
}

require_tool() {
    local tool_name="$1"
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        echo "missing required tool: $tool_name" >&2
        exit 1
    fi
}

copy_single_deb() {
    local package_dir="$1"
    local target_path="$2"
    local -a debs=("$package_dir"/*.deb)
    if [ "${#debs[@]}" -ne 1 ]; then
        echo "expected exactly one deb in $package_dir, got ${#debs[@]}" >&2
        exit 1
    fi
    cp -f "${debs[0]}" "$target_path"
}

assert_metadata_clean() {
    local deb_path="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$unpack_dir" >/dev/null
    if find "$unpack_dir" \( -name '.DS_Store' -o -name '._*' -o -name '__MACOSX' \) | grep -q .; then
        echo "host metadata found in $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    rm -rf "$unpack_dir"
}

# 权限位修正(规范 §10.6): plist/控制 644, dylib/可执行 755, 目录 755;归属由 --root-owner-group 统一 root
sanitize_permissions_deb() {
    local deb_path="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$unpack_dir"
    find "$unpack_dir" -type f -name '*.plist' -exec chmod 644 {} +
    find "$unpack_dir" -type f -name '*.dylib' -exec chmod 755 {} +
    find "$unpack_dir/DEBIAN" -type f -exec chmod 644 {} + 2>/dev/null || true
    find "$unpack_dir" -type d -exec chmod 755 {} +
    dpkg-deb -b --root-owner-group "$unpack_dir" "$deb_path" >/dev/null
    rm -rf "$unpack_dir"
}

assert_rootful_layout() {
    local deb_path="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$unpack_dir" >/dev/null
    if find "$unpack_dir" -path '*/var/jb*' | grep -q .; then
        echo "rootful package unexpectedly contains var/jb: $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    rm -rf "$unpack_dir"
}

assert_rootless_layout() {
    local deb_path="$1"
    local unpack_dir
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$unpack_dir" >/dev/null
    if [ ! -d "$unpack_dir/var/jb" ]; then
        echo "rootless package missing var/jb root: $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    rm -rf "$unpack_dir"
}

assert_roothide_layout() {
    local deb_path="$1"
    local unpack_dir dylib_path
    unpack_dir="$(mktemp -d)"
    dpkg-deb -R "$deb_path" "$unpack_dir" >/dev/null
    if [ -d "$unpack_dir/var/jb" ]; then
        echo "roothide package unexpectedly contains var/jb root: $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    dylib_path="$(find "$unpack_dir/Library/MobileSubstrate/DynamicLibraries" -maxdepth 1 -type f -name '*.dylib' | head -n 1)"
    if [ -z "$dylib_path" ]; then
        echo "roothide package missing tweak dylib: $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    if ! otool -L "$dylib_path" | grep -q '@loader_path/.jbroot'; then
        echo "roothide package missing .jbroot runtime linkage: $deb_path" >&2
        rm -rf "$unpack_dir"
        exit 1
    fi
    rm -rf "$unpack_dir"
}

build_scheme() {
    local scheme="$1"
    local expected_arch="$2"
    local short_arch="$3"
    local package_dir="$BUILD_ROOT/$scheme"
    local out_path version actual_arch

    rm -rf "$package_dir"
    mkdir -p "$package_dir" "$OUT_DIR"

    clean_host_metadata "$BUILD_ROOT" "$OUT_DIR" "$WORK_ROOT/.theos"

    case "$scheme" in
        rootful)
            (cd "$WORK_ROOT" && make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME= THEOS_PACKAGE_DIR="$package_dir")
            ;;
        rootless|roothide)
            (cd "$WORK_ROOT" && make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$scheme" THEOS_PACKAGE_DIR="$package_dir")
            ;;
        *)
            echo "unsupported scheme: $scheme" >&2
            exit 1
            ;;
    esac

    copy_single_deb "$package_dir" "$BUILD_ROOT/${scheme}.deb"
    version="$(dpkg-deb -f "$BUILD_ROOT/${scheme}.deb" Version)"
    out_path="$OUT_DIR/${DISPLAY_NAME}_${version}_${scheme}_${short_arch}.deb"
    cp -f "$BUILD_ROOT/${scheme}.deb" "$out_path"
    sanitize_permissions_deb "$out_path"

    actual_arch="$(dpkg-deb -f "$out_path" Architecture)"
    if [ "$actual_arch" != "$expected_arch" ]; then
        echo "unexpected architecture for $scheme: expected $expected_arch got $actual_arch" >&2
        exit 1
    fi

    dpkg-deb -f "$out_path" Package Version Architecture >/dev/null
    assert_metadata_clean "$out_path"

    case "$scheme" in
        rootful)
            assert_rootful_layout "$out_path"
            ;;
        rootless)
            assert_rootless_layout "$out_path"
            ;;
        roothide)
            assert_roothide_layout "$out_path"
            ;;
    esac

    echo "$out_path"
}

main() {
    require_tool make
    require_tool dpkg-deb
    require_tool otool

    mkdir -p "$BUILD_ROOT" "$OUT_DIR"

    build_scheme rootful iphoneos-arm arm
    build_scheme rootless iphoneos-arm64 arm64
    build_scheme roothide iphoneos-arm64e arm64e
}

main "$@"
