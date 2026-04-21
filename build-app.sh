#!/bin/bash
# Build MacExpert.app as a universal (arm64 + x86_64) binary so it runs
# natively on both Apple Silicon and Intel Macs without Rosetta.
#
# Builds each arch separately (Swift Package Manager doesn't do fat
# binaries in a single invocation), then fuses them with `lipo`. The
# resource bundles produced by SwiftPM for each arch are identical, so
# we take them from the arm64 tree.
set -e

# Script lives inside the Swift Package directory; the .app bundle sits
# one level up alongside it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$SCRIPT_DIR"
APP_DIR="$(dirname "$SCRIPT_DIR")/MacExpert.app"

cd "$PKG_DIR"

echo "Building MacExpert (release, arm64)..."
swift build -c release --arch arm64

echo "Building MacExpert (release, x86_64)..."
swift build -c release --arch x86_64

ARM_BIN="$PKG_DIR/.build/arm64-apple-macosx/release/MacExpert"
INTEL_BIN="$PKG_DIR/.build/x86_64-apple-macosx/release/MacExpert"

if [ ! -x "$ARM_BIN" ] || [ ! -x "$INTEL_BIN" ]; then
    echo "ERROR: one or both per-arch binaries missing." >&2
    echo "  arm64:  $ARM_BIN" >&2
    echo "  x86_64: $INTEL_BIN" >&2
    exit 1
fi

echo "Assembling MacExpert.app..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

lipo -create -output "$APP_DIR/Contents/MacOS/MacExpert" "$ARM_BIN" "$INTEL_BIN"
echo "Universal binary: $(lipo -archs "$APP_DIR/Contents/MacOS/MacExpert")"

cp "$PKG_DIR/MacExpert/Resources/ExpertIcon.icns" "$APP_DIR/Contents/Resources/ExpertIcon.icns"

# Copy Swift resource bundles (take the arm64 set; they're architecture-
# independent so the other arch's copies would be identical).
for bundle in "$PKG_DIR/.build/arm64-apple-macosx/release/"*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

echo "Done! App at: $APP_DIR"
echo "Run: open \"$APP_DIR\""
