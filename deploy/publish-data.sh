#!/usr/bin/env bash
# Upload ELFfeatures.csv, ELFs.geojson and the two NRV burn probability COGs to the Arbutus object store, public-read.
# Run on the machine that has the files.
# Usage: deploy/publish-data.sh /path/to/folder/with/the/four/files
set -euo pipefail

SRC="${1:?folder containing the four files}"
REMOTE="${RCLONE_REMOTE:-newArbutus}"
DEST="$REMOTE:predictiveecology/firesense/elfmaps/"
TENANT="${ARBUTUS_TENANT:-<tenant>}"   # tenant id of the predictiveecology bucket

FILES=(ELFfeatures.csv ELFs.geojson NRVburnProbability.tif NRVburnProbabilityHistoric.tif)

for f in "${FILES[@]}"; do
  [ -s "$SRC/$f" ] || { echo "missing or empty: $SRC/$f" >&2; exit 1; }
done

for f in "${FILES[@]}"; do
  rclone copy "$SRC/$f" "$DEST" --s3-acl public-read --progress
done

BASE="https://object-arbutus.alliancecan.ca/${TENANT}:predictiveecology/firesense/elfmaps"
echo "Published. Public URLs:"
for f in "${FILES[@]}"; do echo "  $BASE/$f"; done
