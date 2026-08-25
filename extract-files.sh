#!/bin/bash
#
# Extract proprietary blobs from a stock c7ltechn system dump.
#
# The blobs are already committed to vendor/samsung/c7ltechn/proprietary,
# so this script is only needed to (re)generate the vendor tree from a dump,
# e.g. from the same C7000ZCS3CRJ1 firmware used for this tree.
#
# Usage: ./extract-files.sh <path-to-dump-root>   (dump root contains /system and /vendor)
#
set -e

DEVICE=c7ltechn
VENDOR=samsung

DUMP="$1"
if [ -z "$DUMP" ]; then
    echo "Usage: $0 <dump-root>  (dir containing system/vendor, e.g. extracted system partition)"
    exit 1
fi

PROPRIETARY=vendor/$VENDOR/$DEVICE/proprietary
LIST=../../../../out/proprietary-files.txt

if [ ! -f "$LIST" ]; then
    echo "Missing blob list: $LIST"
    echo "Generate it from the dump with tools/gen-vendor-mk.py, or use the committed list:"
    ls vendor/$VENDOR/$DEVICE/ 2>/dev/null || true
    exit 1
fi

mkdir -p "$PROPRIETARY"
while read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        vendor/*) src="$DUMP/system/vendor/${f#vendor/}"; dst="$PROPRIETARY/vendor/${f#vendor/}";;
        system/*) src="$DUMP/${f#system/}";               dst="$PROPRIETARY/system/${f#system/}";;
        *) continue;;
    esac
    if [ -e "$src" ] || [ -L "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
    else
        echo "WARN: missing $src" >&2
    fi
done < "$LIST"

echo "Done. Blobs extracted to $PROPRIETARY"
