#!/bin/bash
set -e

# Build and sign AirSense.ipa
# Usage: ./build_ipa.sh [device|sim]
#
# Prerequisites:
#   - THEOS env var set, or THEOS=/workspaces/theos used below
#   - zsign at /workspaces/tools/zsign
#   - iPhone toolchain on PATH

export THEOS="${THEOS:-/workspaces/theos}"
export PATH="$THEOS/bin:$PATH"
export THEOS_PLATFORM="${THEOS_PLATFORM:-iphone}"

cd "$(dirname "$0")"

echo ">> Compiling..."
rm -rf .theos packages/AirSense.ipa
make package 2>&1 | grep -E "error:|Error" || true

APP_BIN=".theos/obj/debug/AirSense.app/AirSense"
if [ ! -f "$APP_BIN" ]; then
    # Try alternative path for newer Theos
    APP_BIN="$(find .theos -name AirSense -type f -path '*/AirSense.app/*' | head -1)"
fi

if [ -z "$APP_BIN" ] || [ ! -f "$APP_BIN" ]; then
    echo "ERROR: Could not find compiled AirSense binary."
    exit 1
fi

echo ">> Assembling IPA..."
rm -rf /tmp/ipapack /tmp/ipa_verify
mkdir -p /tmp/ipapack/Payload

# Copy the .app bundle
APP_DIR="$(dirname "$APP_BIN")"
cp -r "$APP_DIR" /tmp/ipapack/Payload/

rm -rf .zsign_cache
/workspaces/tools/zsign -f -a /tmp/ipapack/Payload/AirSense.app -o packages/AirSense.ipa 2>&1 | grep -E "Archive"

echo ">> Verifying..."
export PATH="/workspaces/theos/toolchain/linux/iphone/bin:$PATH"
unzip -q packages/AirSense.ipa -d /tmp/ipa_verify
file /tmp/ipa_verify/Payload/AirSense.app/AirSense
ls -la packages/AirSense.ipa | awk '{print "IPA size:", $5, "bytes —", $NF}'
echo ">> Done. Output: packages/AirSense.ipa"
