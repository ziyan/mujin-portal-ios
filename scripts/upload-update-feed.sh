#!/usr/bin/env bash
# Publishes the update feed the app reads, as an asset of the update-feed release.
# Does nothing when there is no feed file, which means no build can be installed yet.
#
#   scripts/upload-update-feed.sh <feed file>
set -euo pipefail

FEED_FILE="$1"
RELEASE_TAG="update-feed"

if [ ! -f "${FEED_FILE}" ]; then
  echo "upload-update-feed: no feed to publish"
  exit 0
fi
if ! gh release view "${RELEASE_TAG}" >/dev/null 2>&1; then
  gh release create "${RELEASE_TAG}" --prerelease --title "Update feed" \
    --notes "What the app reads to learn of a new TestFlight build. Published by the build pipeline."
fi
gh release upload "${RELEASE_TAG}" "${FEED_FILE}#testflight.json" --clobber
