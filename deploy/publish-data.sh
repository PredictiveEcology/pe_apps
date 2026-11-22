#!/usr/bin/env bash
# Upload ELFfeatures.csv, ELFs.geojson and the two NRV burn probability COGs to the Arbutus object store, public-read.
# Run on the machine that has the files.
# Usage: deploy/publish-data.sh /path/to/folder/with/the/four/files
set -euo pipefail

SRC="${1:?folder containing the four files}"
REMOTE="${RCLONE_REMOTE:-newArbutus}"
DEST="$REMOTE:predictiveecology/firesense/elfmaps/"
TENANT="${ARBUTUS_TENANT:-<tenant>}"   # tenant id of the predictiveecology bucket

## The map shows Web Mercator copies of the national rasters (no reprojection in the browser); made here with GDAL,
## 400 m cells (about 200-260 m on the ground in Canada, near the 250 m source)
for f in NRVburnProbability NRVburnProbabilityHistoric; do
  [ -s "$SRC/$f.tif" ] || { echo "missing: $SRC/$f.tif" >&2; exit 1; }
  if [ ! -s "$SRC/${f}_3857.tif" ] || [ "$SRC/$f.tif" -nt "$SRC/${f}_3857.tif" ]; then
    gdalwarp -q -overwrite -t_srs EPSG:3857 -tr 400 400 -r bilinear -dstnodata nan -of COG \
      -co COMPRESS=DEFLATE -co PREDICTOR=3 -co OVERVIEW_RESAMPLING=AVERAGE "$SRC/$f.tif" "$SRC/${f}_3857.tif"
  fi
done
FILES=(ELFfeatures.csv ELFs.geojson NRVburnProbability_3857.tif NRVburnProbabilityHistoric_3857.tif)

for f in "${FILES[@]}"; do
  [ -s "$SRC/$f" ] || { echo "missing or empty: $SRC/$f" >&2; exit 1; }
done

for f in "${FILES[@]}"; do
  rclone copy "$SRC/$f" "$DEST" --s3-acl public-read --progress
done

BASE="https://object-arbutus.alliancecan.ca/${TENANT}:predictiveecology/firesense/elfmaps"
echo "Published. Public URLs:"
for f in "${FILES[@]}"; do echo "  $BASE/$f"; done
