#!/usr/bin/env bash
# Fails when a grid of tiles holds a NavigationLink or a Button. A grid of tiles
# is one List row, and a List row that holds several of them activates all of
# them on a tap (a tap on one tile pushed the whole stack). Tiles that open a
# screen pass `route:` to StatTile and the List applies routePushing(); other
# tiles use rowTapTarget. See PortalApp/Sources/RowControls.swift.
#
# This is the cheap guard that runs on every pull request. The UI tests in
# PortalUITests/ are the one that taps through the real screens.
#
#   scripts/check-row-controls.sh
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIRECTORY}/.."

FAILED=0

while IFS= read -r -d '' FILE; do
  RESULT="$(awk '
    # Inside a tile grid from its opening brace to the matching closing one.
    /(StatGrid|tileGrid|WebAppGrid|TileGridLayout)[^{]*\{[ \t]*$/ && depth == 0 { inside = 1; depth = 0; start = NR }
    inside {
      line = $0
      sub(/\/\/.*/, "", line)
      if (line ~ /NavigationLink|Button[ ({]/) { print FILENAME ":" NR ": " $0 }
      opens = gsub(/\{/, "{", line)
      closes = gsub(/\}/, "}", line)
      depth += opens - closes
      if (depth <= 0) { inside = 0; depth = 0 }
    }
  ' "${FILE}")"
  if [ -n "${RESULT}" ]; then
    echo "${RESULT}" >&2
    echo "check-row-controls: ${FILE}: a tile grid holds a NavigationLink or a Button" >&2
    FAILED=1
  fi
done < <(git ls-files -z -- 'PortalApp/Sources/*.swift' 'Shared/*.swift')

if [ "${FAILED}" -ne 0 ]; then
  exit 1
fi
echo "check-row-controls: ok"
