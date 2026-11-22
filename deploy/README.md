# Deploying apps.predictiveecology.org

The VM `wbi` (floating IP 134.87.10.143, Ubuntu 24.04) already runs Docker Compose in `/srv/wbi`:
Caddy plus the two WBI Shiny containers. These steps add a second site, `apps.predictiveecology.org`,
to that same stack. They follow `01-cloud-vm/README.md` in `PredictiveEcology/wbi_shiny`.
DNS already points here. Nothing in the existing `wbi.predictiveecology.org` block changes.

## 1. Build the app image and load it on the VM (from your machine)

    cd firesense/elfmaps
    docker build -t firesense-elfmaps:v6 .
    docker save firesense-elfmaps:v6 | gzip -1 | ssh ubuntu@134.87.10.143 'gunzip | sudo docker load'

No registry, so the VM needs no login (compose has `pull_policy: never`).

## 2. Publish the data (from the machine with the module output)

    ARBUTUS_TENANT=529feda02d404836b0e91b1d360b4df0 deploy/publish-data.sh /path/to/folder/with/ELFfeatures.csv/and/ELFs.geojson

Public URL pattern: `https://object-arbutus.alliancecan.ca/529feda02d404836b0e91b1d360b4df0:predictiveecology/firesense/elfmaps/ELFfeatures.csv`
(and `ELFs.geojson`, `NRVburnProbability.tif`, `NRVburnProbabilityHistoric.tif`). Repeat whenever the data change; the app reads the files when a page is opened, so no restart.

## 3. Copy the site and edit the server config

    rsync -a site/ ubuntu@134.87.10.143:/tmp/apps-site/
    ssh ubuntu@134.87.10.143
    cd /srv/wbi
    sudo mkdir -p apps-site && sudo cp -a /tmp/apps-site/. apps-site/
    sudo cp Caddyfile Caddyfile.bak && sudo cp docker-compose.yml docker-compose.yml.bak

Then edit by hand:

- `Caddyfile`: append the block in `deploy/Caddyfile.apps`.
- `docker-compose.yml`: add the `firesense-elfmaps` service from `deploy/docker-compose.apps.yml`
  and add the volume `./apps-site:/apps-site:ro` and
  `depends_on: firesense-elfmaps` to the existing `caddy` service.

## 4. Start

    sudo docker compose up -d
    sudo docker compose restart caddy     # Caddyfile changes are not picked up otherwise

(Use `docker-compose` if that is the installed command, as in the wbi README.)

Mount the site at `/apps-site`, not under `/srv`: `/srv` is the wbi site's read-only mount, and a mount point inside it stops Caddy from starting (it took wbi down for 2 min on 2026-11-21).

## 5. Check

    curl -sI https://apps.predictiveecology.org/ | head -1
    curl -sI https://apps.predictiveecology.org/firesense/elfmaps/ | head -1
    curl -sI https://apps.predictiveecology.org/firesense/fitledger/ | head -1   # 301 to /firesense/elfmaps/
    curl -s -o /dev/null -w "%{http_code}\n" -H "Range: bytes=0-99" https://apps.predictiveecology.org/firesense/elfmaps/data/NRVburnProbability.tif   # 206
    curl -sI https://wbi.predictiveecology.org/apps/wbi/ | head -1     # existing site still up

## Update later

New image: build and load as in step 1 (bump the tag), then on the VM `sudo docker compose up -d`.
New site pages: rsync `site/` to `/srv/wbi/apps-site/`; Caddy serves them at once.
Roll back: restore `Caddyfile.bak` and `docker-compose.yml.bak`, then `up -d` and restart caddy.
