#!/bin/bash
# Compiles and runs the routing layer (Models + Graph + Services) against the
# macOS SDK and asserts the expected routes for the bundled network.json.
#
# This needs only Command Line Tools — no Xcode, no simulator. Use it to sanity
# check the data file after regenerating it:
#
#   Tools/verify.sh                       # uses EnKisaYolculuk/Data/network.json
#   Tools/verify.sh path/to/other.json
#
# NOTE: the assertions in Tools/main.swift are written against the PLACEHOLDER
# data. Once the real network lands they will fail — update them to a handful
# of routes you have verified by hand, and keep them as the regression net.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -O -o "$OUT/verify" \
    EnKisaYolculuk/Models/*.swift \
    EnKisaYolculuk/Graph/*.swift \
    EnKisaYolculuk/Services/AppState.swift \
    EnKisaYolculuk/Services/NetworkLoader.swift \
    EnKisaYolculuk/Services/RouteService.swift \
    Tools/main.swift

"$OUT/verify" "${1:-EnKisaYolculuk/Data/network.json}"
