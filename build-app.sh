#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

LAUNCH=true
for arg in "$@"; do
    case "${arg}" in
        --no-launch) LAUNCH=false ;;
    esac
done

APP="BarKeep.app"
# Prefer Xcode’s toolchain when present; otherwise use the active developer dir (CLT).
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppInfo.plist 2>/dev/null || echo "unknown")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' AppInfo.plist 2>/dev/null || echo "?")"

if [[ ! -f Assets/AppIcon.icns ]]; then
    if [[ -f Scripts/GenerateAppIcon.swift ]]; then
        echo "Generating app icon..."
        swift Scripts/GenerateAppIcon.swift
    fi
fi

echo "Building BarKeep ${VERSION} (${BUILD}) release..."
swift build -c release

BIN=".build/release/BarKeep"
if [[ ! -x "${BIN}" ]]; then
    echo "error: expected binary at ${BIN}" >&2
    exit 1
fi

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/BarKeep"
chmod +x "${APP}/Contents/MacOS/BarKeep"
cp AppInfo.plist "${APP}/Contents/Info.plist"

if [[ -f Assets/AppIcon.icns ]]; then
    cp Assets/AppIcon.icns "${APP}/Contents/Resources/"
fi

if [[ -d Help/BarKeep.help ]]; then
    echo "Bundling help book..."
    HELP_LPROJ="Help/BarKeep.help/Contents/Resources/en.lproj"
    HELP_ENGLISH="Help/BarKeep.help/Contents/Resources/English.lproj"
    if [[ -d "${HELP_LPROJ}" ]]; then
        rm -rf "${HELP_ENGLISH}"
        cp -R "${HELP_LPROJ}" "${HELP_ENGLISH}"
        if command -v hiutil >/dev/null 2>&1; then
            hiutil -C -a -m 2 -s en -f "${HELP_LPROJ}/BarKeep.helpindex" "${HELP_LPROJ}" >/dev/null 2>&1 || true
            if [[ -f "${HELP_LPROJ}/BarKeep.helpindex" ]]; then
                cp "${HELP_LPROJ}/BarKeep.helpindex" "${HELP_ENGLISH}/BarKeep.helpindex"
            fi
        fi
    fi
    rm -rf "${APP}/Contents/Resources/BarKeep.help"
    cp -R Help/BarKeep.help "${APP}/Contents/Resources/"
fi

echo "Signing ${APP}..."
xattr -cr "${APP}" 2>/dev/null || true
codesign --force --sign - --timestamp=none "${APP}/Contents/MacOS/BarKeep"
codesign --force --sign - --timestamp=none "${APP}"

echo "Done: ${APP} (v${VERSION} build ${BUILD})"
if [[ "${LAUNCH}" == "true" ]]; then
    pkill -x BarKeep 2>/dev/null || true
    sleep 0.2
    echo "Launching..."
    open "${APP}"
fi
