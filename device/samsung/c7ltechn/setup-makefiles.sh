#!/bin/bash
#
# Regenerate vendor/samsung/c7ltechn/c7ltechn-vendor.mk from the committed
# blob tree (vendor/samsung/c7ltechn/proprietary).
#
set -e
cd "$(dirname "$0")/../.."
python3 tools/gen-vendor-mk.py vendor/samsung/c7ltechn
echo "Done."
