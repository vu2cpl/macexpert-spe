#!/bin/bash
# Install the freshly-built MacExpert.app into /Applications/ and
# relaunch it. Solves the "I built a fix but I'm still running the old
# install" trap — diagnosed live 2026-05-20 when an updated decoder
# wasn't actually in the running process because Dock / Spotlight were
# launching the older v2.0.2 release install from /Applications.
#
# Usage:
#   ./install.sh                # install the existing build (default)
#   ./install.sh --build        # build via build-app.sh first, then install
#   ./install.sh --backup       # rename existing install to
#                               # /Applications/MacExpert-prev.app first
#   ./install.sh --no-relaunch  # install but don't `open` afterwards
#   ./install.sh --src PATH     # install from a different .app bundle
#                               # (defaults to ../MacExpert.app, the
#                               # build-app.sh output)
#
# Flags can be combined. Examples:
#   ./install.sh --build --backup       # rebuild, keep old as -prev, install
#   ./install.sh --src dist/MacExpert.app # install a release-style bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$SCRIPT_DIR"
DEFAULT_SRC="$(dirname "$SCRIPT_DIR")/MacExpert.app"
DEST="/Applications/MacExpert.app"

DO_BUILD=0
DO_BACKUP=0
DO_RELAUNCH=1
SRC="$DEFAULT_SRC"

while [ $# -gt 0 ]; do
    case "$1" in
        --build)       DO_BUILD=1; shift ;;
        --backup)      DO_BACKUP=1; shift ;;
        --no-relaunch) DO_RELAUNCH=0; shift ;;
        --src)         SRC="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^set -e$/p' "$0" | sed 's/^# \{0,1\}//; /^set -e$/d'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ "$DO_BUILD" = "1" ]; then
    echo "==> Building first (build-app.sh)..."
    "$PKG_DIR/build-app.sh"
fi

if [ ! -d "$SRC" ]; then
    echo "ERROR: source bundle not found: $SRC" >&2
    echo "       Run with --build, or pass --src /path/to/MacExpert.app." >&2
    exit 1
fi

SRC_BIN="$SRC/Contents/MacOS/MacExpert"
if [ ! -x "$SRC_BIN" ]; then
    echo "ERROR: source bundle is missing the executable: $SRC_BIN" >&2
    exit 1
fi

echo "==> Source:      $SRC ($(date -r "$SRC_BIN" '+%Y-%m-%d %H:%M:%S'))"
echo "==> Destination: $DEST"

# Quit any running copy first — rsync can't reliably replace files that
# are mmap'd by a running process, and the user wants the new bits in
# the next launch anyway. Try a graceful quit first (gives unsaved
# state a chance to persist), then fall back to a hard kill on anything
# still hanging around.
if pgrep -f "/MacExpert\\.app/Contents/MacOS/MacExpert" >/dev/null; then
    echo "==> Quitting running MacExpert..."
    osascript -e 'tell application "MacExpert" to quit' 2>/dev/null || true
    # Wait up to 5 s for graceful quit.
    for _ in 1 2 3 4 5; do
        pgrep -f "/MacExpert\\.app/Contents/MacOS/MacExpert" >/dev/null || break
        sleep 1
    done
    if pgrep -f "/MacExpert\\.app/Contents/MacOS/MacExpert" >/dev/null; then
        echo "    (still running, sending SIGTERM)"
        pkill -f "/MacExpert\\.app/Contents/MacOS/MacExpert" || true
        sleep 1
    fi
fi

if [ "$DO_BACKUP" = "1" ] && [ -d "$DEST" ]; then
    BACKUP="/Applications/MacExpert-prev.app"
    echo "==> Backing up existing install: $DEST -> $BACKUP"
    rm -rf "$BACKUP"
    mv "$DEST" "$BACKUP"
fi

echo "==> Copying bundle into /Applications/..."
# Trailing slashes + --delete give us a clean atomic-ish swap of the
# bundle contents. Stale files from a previous install (e.g. removed
# resource bundles) get cleaned up rather than lingering.
rsync -a --delete "$SRC/" "$DEST/"

echo "==> Verifying signature..."
if codesign --verify --deep --strict "$DEST" 2>&1; then
    echo "    signature OK"
else
    echo "    WARNING: signature verification failed — Gatekeeper may complain on launch." >&2
fi

echo "==> Architectures: $(lipo -archs "$DEST/Contents/MacOS/MacExpert")"
echo "==> Installed:     $(date -r "$DEST/Contents/MacOS/MacExpert" '+%Y-%m-%d %H:%M:%S')"

if [ "$DO_RELAUNCH" = "1" ]; then
    echo "==> Relaunching..."
    open "$DEST"
fi

echo "Done."
