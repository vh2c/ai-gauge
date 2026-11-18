#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${SCRIPT_DIR}/AI Gauge.app"
BIN_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"

mkdir -p "${BIN_DIR}" "${RES_DIR}/core"

echo "🔨 Compiling Swift binary for AI Gauge..."
cp "${SCRIPT_DIR}/src/QuotaHubApp.swift" /tmp/QuotaHubApp.swift
swiftc -O -target arm64-apple-macos11.0 /tmp/QuotaHubApp.swift -o /tmp/AIGauge-arm64
swiftc -O -target x86_64-apple-macos13.0 /tmp/QuotaHubApp.swift -o /tmp/AIGauge-x86_64
lipo -create /tmp/AIGauge-arm64 /tmp/AIGauge-x86_64 -output "${BIN_DIR}/AIGauge"
rm -f /tmp/AIGauge-arm64 /tmp/AIGauge-x86_64

echo "📦 Bundling core engine & assets..."
cp -r "${REPO_DIR}/core/"* "${RES_DIR}/core/"

if [ -f "${REPO_DIR}/assets/AppIcon.icns" ]; then
    cp "${REPO_DIR}/assets/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
fi

if [ -f "${REPO_DIR}/assets/icon.png" ]; then
    cp "${REPO_DIR}/assets/icon.png" "${RES_DIR}/icon.png"
fi

cat << 'PLIST' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI Gauge</string>
    <key>CFBundleDisplayName</key>
    <string>AI Gauge</string>
    <key>CFBundleIdentifier</key>
    <string>br.com.vh2c.ai-gauge</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.3</string>
    <key>CFBundleVersion</key>
    <string>1.1.3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AIGauge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "🔏 Signing bundle (ad-hoc)..."
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
find "${APP_BUNDLE}" -name '._*' -delete
codesign --force --deep -s - "${APP_BUNDLE}"

echo "✅ App bundle created at ${APP_BUNDLE}"
