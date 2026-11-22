#!/usr/bin/env bash
# Upload ELFfeatures.csv and ELFs.geojson to the Arbutus object store, public-read.
# Run on the machine that has the files.
# Usage: deploy/publish-data.sh /path/to/folder/with/ELFfeatures.csv/and/ELFs.geojson
set -euo pipefail

SRC="${1:?folder containing ELFfeatures.csv and ELFs.geojson}"
REMOTE="${RCLONE_REMOTE:-newArbutus}"
DEST="$REMOTE:predictiveecology/firesense/elfmaps/"
TENANT="${ARBUTUS_TENANT:-<tenant>}"   # tenant id of the predictiveecology bucket

for f in ELFfeatures.csv ELFs.geojson; do
  [ -s "$SRC/$f" ] || { echo "missing or empty: $SRC/$f" >&2; exit 1; }
done

rclone copy "$SRC/ELFfeatures.csv" "$DEST" --s3-acl public-read --progress
rclone copy "$SRC/ELFs.geojson" "$DEST" --s3-acl public-read --progress

BASE="https://object-arbutus.alliancecan.ca/${TENANT}:predictiveecology/firesense/elfmaps"
echo "Published. Public URLs:"
echo "  $BASE/ELFfeatures.csv"
echo "  $BASE/ELFs.geojson"
