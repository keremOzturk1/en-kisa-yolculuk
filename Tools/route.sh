#!/bin/bash
# Spot-check routes against any network.json without Xcode.
#
#   Tools/route.sh                                   # list stations + their lines
#   Tools/route.sh yenikapi otogar                   # route on the bundled data
#   Tools/route.sh yenikapi otogar other.json        # route on another file

set -euo pipefail
cd "$(dirname "$0")/.."

JSON="EnKisaYolculuk/Data/network.json"
FROM=""; TO=""
case $# in
  0) ;;
  1) JSON="$1" ;;
  2) FROM="$1"; TO="$2" ;;
  *) FROM="$1"; TO="$2"; JSON="$3" ;;
esac

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

mkdir -p "$OUT/src"
cp Tools/query_main.swift "$OUT/src/main.swift"

swiftc -O -o "$OUT/route" \
    EnKisaYolculuk/Models/*.swift \
    EnKisaYolculuk/Graph/*.swift \
    EnKisaYolculuk/Services/AppState.swift \
    EnKisaYolculuk/Services/NetworkLoader.swift \
    EnKisaYolculuk/Services/RouteService.swift \
    "$OUT/src/main.swift"

"$OUT/route" "$JSON" ${FROM:+"$FROM"} ${TO:+"$TO"}
