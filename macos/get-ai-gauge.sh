#!/usr/bin/env bash
#
# AI Gauge - macOS installer / updater (run from Terminal)
#
#   curl -fsSL https://raw.githubusercontent.com/vh2c/ai-gauge/main/macos/get-ai-gauge.sh | bash
#
# What it does, in order:
#   1. checks your Mac (macOS version / CPU) and whether Node.js 18+ is installed
#   2. downloads the latest AI Gauge release and its SHA256SUMS.txt from GitHub
#   3. verifies the SHA-256 checksum (aborts, changing nothing, if it does not match)
#   4. quits a running AI Gauge, moves the old app to the Trash, installs the new one
#   5. opens AI Gauge
#
# Why use it: files downloaded with curl are not flagged as "downloaded from the internet", so macOS does not
# show the "Apple could not verify..." message for the app (it is not notarized yet).
# The script never uses sudo, never changes system security settings and only touches AI Gauge.app.
#
# Optional environment variables:
#   AIGAUGE_APP_DIR   where to install (default: /Applications; use "$HOME/Applications" if it is not writable)
#   AIGAUGE_VERSION   a release tag such as v1.1.1 (default: the latest release)
#   AIGAUGE_BASE_URL  download base URL (for testing)
#   AIGAUGE_SKIP_OPEN set to 1 to not open the app at the end

set -euo pipefail

APP_NAME="AI Gauge.app"
ZIP_NAME="AI-Gauge-macOS-vh2c.zip"
APP_DIR="${AIGAUGE_APP_DIR:-/Applications}"

if [ -n "${AIGAUGE_BASE_URL:-}" ]; then
  BASE_URL="${AIGAUGE_BASE_URL%/}"
elif [ -n "${AIGAUGE_VERSION:-}" ]; then
  BASE_URL="https://github.com/vh2c/ai-gauge/releases/download/${AIGAUGE_VERSION}"
else
  BASE_URL="https://github.com/vh2c/ai-gauge/releases/latest/download"
fi

say()  { printf '%s\n' "$*"; }

# If anything fails after the old app was moved to the Trash, put it back
TARGET=""
TRASHED=""
rollback() {
  if [ -n "$TRASHED" ] && [ -e "$TRASHED" ] && [ -n "$TARGET" ] && [ ! -e "$TARGET" ]; then
    mv "$TRASHED" "$TARGET" 2>/dev/null && printf '%s\n' "↩️  Previous version restored"
  fi
}
fail() { rollback; printf '\n❌ %s\n' "$*" >&2; exit 1; }

say "⚡ AI Gauge installer for macOS"
say ""

# ---- 1. Check the Mac ----------------------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS. See https://github.com/vh2c/ai-gauge/blob/main/INSTALL.md for Windows and Linux."

ARCH="$(uname -m)"
MACOS_VER="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VER%%.*}"
if [ "$ARCH" = "arm64" ]; then
  MIN_MAJOR=11
else
  MIN_MAJOR=13
fi
if [ "$MACOS_MAJOR" -lt "$MIN_MAJOR" ] 2>/dev/null; then
  fail "AI Gauge needs macOS ${MIN_MAJOR} or later on this kind of Mac (${ARCH}); you have macOS ${MACOS_VER}."
fi
say "✓ macOS ${MACOS_VER} (${ARCH})"

# Node.js 18+ is required by the app on macOS (it is not bundled)
find_node() {
  for p in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
    [ -x "$p" ] && { echo "$p"; return; }
  done
  if [ -d "$HOME/.nvm/versions/node" ]; then
    local v
    v="$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -n1 || true)"
    [ -n "$v" ] && [ -x "$HOME/.nvm/versions/node/$v/bin/node" ] && { echo "$HOME/.nvm/versions/node/$v/bin/node"; return; }
  fi
  command -v node 2>/dev/null || true
}
NODE_BIN="$(find_node)"
NODE_WARN=""
if [ -z "$NODE_BIN" ]; then
  NODE_WARN="Node.js was not found. AI Gauge needs Node.js 18 or later to read your quotas."
else
  NODE_VER="$("$NODE_BIN" -v 2>/dev/null | sed 's/^v//')"
  NODE_MAJOR="${NODE_VER%%.*}"
  if [ "${NODE_MAJOR:-0}" -lt 18 ] 2>/dev/null; then
    NODE_WARN="Node.js v${NODE_VER} is too old. AI Gauge needs Node.js 18 or later."
  else
    say "✓ Node.js v${NODE_VER}"
  fi
fi
[ -n "$NODE_WARN" ] && say "⚠️  ${NODE_WARN}"

# ---- 2. Download -----------------------------------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aigauge-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

say "⬇️  Downloading ${ZIP_NAME} ..."
PROGRESS="-sS"; [ -t 2 ] && PROGRESS="--progress-bar"   # a progress bar only makes sense in a terminal
curl -fL --retry 2 $PROGRESS -o "$TMP/$ZIP_NAME" "$BASE_URL/$ZIP_NAME" \
  || fail "Could not download ${BASE_URL}/${ZIP_NAME}. Check your internet connection."
curl -fsSL --retry 2 -o "$TMP/SHA256SUMS.txt" "$BASE_URL/SHA256SUMS.txt" \
  || fail "Could not download the checksum file (SHA256SUMS.txt). Nothing was installed."

# ---- 3. Verify ---------------------------------------------------------------------------------------------
EXPECTED="$(awk -v f="$ZIP_NAME" '($2==f || $2=="*"f) {print $1; exit}' "$TMP/SHA256SUMS.txt")"
[ -n "$EXPECTED" ] || fail "SHA256SUMS.txt has no entry for ${ZIP_NAME}. Nothing was installed."
ACTUAL="$(shasum -a 256 "$TMP/$ZIP_NAME" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  fail "Checksum does not match. Expected ${EXPECTED}, got ${ACTUAL}. Nothing was installed."
fi
say "✓ Checksum verified (SHA-256)"

ditto -x -k "$TMP/$ZIP_NAME" "$TMP/extracted" || fail "Could not extract the download."
[ -d "$TMP/extracted/$APP_NAME" ] || fail "The download does not contain ${APP_NAME}. Nothing was installed."

# ---- 4. Install ---------------------------------------------------------------------------------------------
mkdir -p "$APP_DIR" 2>/dev/null || true
[ -w "$APP_DIR" ] || fail "Cannot write to ${APP_DIR}. Run again with AIGAUGE_APP_DIR=\"\$HOME/Applications\" in front of the command."

TARGET="$APP_DIR/$APP_NAME"

# Quit the running copy that lives in the target folder (and only that one).
# Uses ps, not pgrep: pgrep skips the ancestors of the caller, and when the app updates itself this script is its child.
RUNNING_PIDS="$(ps -axo pid=,command= | grep -F "$TARGET/Contents/MacOS/" | grep -v grep | awk '{print $1}')"
if [ -n "$RUNNING_PIDS" ]; then
  say "⏹  Closing the running AI Gauge ..."
  kill $RUNNING_PIDS >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    STILL=""
    for pid in $RUNNING_PIDS; do kill -0 "$pid" 2>/dev/null && STILL="$STILL $pid"; done
    [ -z "$STILL" ] && break
    sleep 0.5
  done
  [ -n "${STILL:-}" ] && kill -9 $STILL >/dev/null 2>&1 || true
fi

# Keep the old version in the Trash (recoverable) instead of deleting it
if [ -e "$TARGET" ]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$HOME/.Trash"
  mv "$TARGET" "$HOME/.Trash/AI Gauge ${STAMP}.app" || fail "Could not move the old version to the Trash. Nothing was changed."
  TRASHED="$HOME/.Trash/AI Gauge ${STAMP}.app"
  say "🗑  Previous version moved to the Trash"
fi

if ! ditto "$TMP/extracted/$APP_NAME" "$TARGET"; then
  rm -rf "$TARGET"          # remove the partial copy so the previous version can be restored
  fail "Could not copy the app into ${APP_DIR}."
fi
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

if codesign --verify --deep --strict "$TARGET" >/dev/null 2>&1; then
  say "✓ App signature is intact"
else
  say "⚠️  Could not verify the app signature (the app is not notarized, this is expected)."
fi

NEW_VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || echo '?')"
say ""
say "✅ AI Gauge ${NEW_VER} installed in ${APP_DIR}"

# ---- 5. Open -----------------------------------------------------------------------------------------------
if [ "${AIGAUGE_SKIP_OPEN:-0}" != "1" ]; then
  open "$TARGET" || say "Open it from ${APP_DIR}."
fi

if [ -n "$NODE_WARN" ]; then
  say ""
  say "👉 Install Node.js (LTS) from https://nodejs.org or with 'brew install node', then reopen AI Gauge."
fi
say ""
say "To update later, run the same command again."
