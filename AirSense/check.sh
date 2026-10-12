#!/bin/bash
# iOS SDK compile check (Step 4a). Deployment target is iOS 16.0 per spec.
cd "$(dirname "$0")"
CC="/workspaces/theos/toolchain/linux/iphone/bin/clang"
SDK="$(ls -d /workspaces/theos/sdks/iPhoneOS*.sdk | sort -V | tail -n1)"
FLAGS="-fsyntax-only -fobjc-arc -fobjc-weak -fobjc-runtime=ios-16.0 -target arm64-apple-ios16.0 -mios-version-min=16.0 -Wall -Wextra -Wno-unused-parameter -isysroot $SDK -I."
fail=0
for f in "$@"; do
  out=$($CC $FLAGS "$f" 2>&1)
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -30; fail=1; fi
done
[ $fail -eq 0 ] && echo "ALL CLEAN"
