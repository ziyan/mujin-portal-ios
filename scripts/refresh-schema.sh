#!/usr/bin/env bash
# Refreshes Schema/schema.json from a Portal GraphQL introspection file.
#
#   scripts/refresh-schema.sh /path/to/schema.json
#
# The schema check in the PortalKit tests validates every GraphQL document the
# app sends against this copy. Only names, types and arguments are kept: every
# description is dropped, because descriptions are prose that can name hosts
# and products. The script refuses to write a copy that still mentions a host.
set -euo pipefail

SOURCE="${1:?usage: scripts/refresh-schema.sh <path to a Portal introspection schema.json>}"
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIRECTORY}/../Schema/schema.json"

python3 - "${SOURCE}" "${TARGET}" <<'PYTHON'
import json
import re
import sys

source, target = sys.argv[1], sys.argv[2]
document = json.load(open(source))


def strip(value):
    if isinstance(value, dict):
        return {key: strip(item) for key, item in value.items() if key not in ("description", "deprecationReason")}
    if isinstance(value, list):
        return [strip(item) for item in value]
    return value


text = json.dumps(strip(document), sort_keys=True, separators=(",", ":"))
hosts = sorted(set(re.findall(r"[A-Za-z0-9.-]+\.(?:co\.jp|cloud|com|net|org|io)\b", text)))
if hosts:
    sys.exit("refusing to write a schema that mentions hosts: " + ", ".join(hosts))
open(target, "w").write(text + "\n")
print("wrote", target, len(text), "bytes")
PYTHON
