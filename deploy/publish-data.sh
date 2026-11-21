#!/usr/bin/env bash
# Upload the fit-date csv and png made by fireSense_ELFs (fitDatesMap = TRUE) to the
# Arbutus object store, public-read. Run on the machine that has the module output.
# Usage: deploy/publish-data.sh /path/to/folder/with/ELFfitDates.{csv,png}
set -euo pipefail

SRC="${1:?folder containing ELFfitDates.csv and ELFfitDates.png}"
REMOTE="${RCLONE_REMOTE:-newArbutus}"
DEST="$REMOTE:predictiveecology/firesense/fitledger/"
TENANT="${ARBUTUS_TENANT:-<tenant>}"   # tenant id of the predictiveecology bucket

for f in ELFfitDates.csv ELFfitDates.png; do
  [ -s "$SRC/$f" ] || { echo "missing or empty: $SRC/$f" >&2; exit 1; }
done

rclone copy "$SRC/ELFfitDates.csv" "$DEST" --s3-acl public-read --progress
rclone copy "$SRC/ELFfitDates.png" "$DEST" --s3-acl public-read --progress

BASE="https://object-arbutus.alliancecan.ca/${TENANT}:predictiveecology/firesense/fitledger"
echo "Published. Public URLs:"
echo "  $BASE/ELFfitDates.csv"
echo "  $BASE/ELFfitDates.png"
