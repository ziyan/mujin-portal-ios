#!/usr/bin/env bash
# Fails when a tracked file holds something that must never be in this public
# repository: an internal host, a real controller id, or a schema that kept its
# descriptions. Run it before a push; the first CI job runs it too.
#
#   scripts/check-public-content.sh
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIRECTORY}/.."

SELF="scripts/check-public-content.sh"
FAILED=0

# Patterns are assembled from pieces so this file never contains a match itself.
DOT='\.'
INTERNAL_HOSTS="mujin${DOT}co${DOT}jp|${DOT}mujin-corp|git${DOT}mujin"
CONTROLLER_IDENTIFIER='controller1[0-9]{3}'

report() {
  echo "check-public-content: $1" >&2
  FAILED=1
}

while IFS= read -r -d '' FILE; do
  [ "${FILE}" = "${SELF}" ] && continue
  [ -f "${FILE}" ] || continue
  if grep -IinqE "${INTERNAL_HOSTS}" -- "${FILE}"; then
    report "${FILE}: mentions an internal host"
  fi
  if grep -IqE "${CONTROLLER_IDENTIFIER}" -- "${FILE}"; then
    report "${FILE}: mentions a real controller id"
  fi
done < <(git ls-files -z)

if [ -f Schema/schema.json ] && grep -q '"description":' Schema/schema.json; then
  report "Schema/schema.json has descriptions; refresh it only with scripts/refresh-schema.sh"
fi

if [ "${FAILED}" -ne 0 ]; then
  exit 1
fi
echo "check-public-content: ok"
