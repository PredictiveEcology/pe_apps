# Deploying apps.predictiveecology.org

The VM `wbi` (floating IP 134.87.10.143, Ubuntu 24.04) already runs Docker Compose in `/srv/wbi`:
Caddy plus the two WBI Shiny containers. These steps add a second site, `apps.predictiveecology.org`,
to that same stack. They follow `01-cloud-vm/README.md` in `PredictiveEcology/wbi_shiny`.
DNS already points here. Nothing in the existing `wbi.predictiveecology.org` block changes.

## 1. Build and push the app image (from your machine)

    cd firesense/fitledger
    docker build -t ghcr.io/predictiveecology/firesense-fitledger:v1 .
    docker login ghcr.io          # GitHub user + a token with write:packages
    docker push ghcr.io/predictiveecology/firesense-fitledger:v1

If the package is private, run `docker login ghcr.io` on the VM too (token with read:packages),
or make the package public in the GitHub org settings.

## 2. Publish the data (from the machine with the module output)

    ARBUTUS_TENANT=<tenant> deploy/publish-data.sh /path/to/folder/with/ELFfitDates

Public URL pattern: `https://object-arbutus.alliancecan.ca/<tenant>:predictiveecology/firesense/fitledger/ELFfitDates.csv`
(and `.png`). Repeat after each fit round; the app reads the files when a page is opened, so no restart.

## 3. Copy the site and edit the server config

    rsync -a site/ ubuntu@134.87.10.143:/tmp/apps-site/
    ssh ubuntu@134.87.10.143
    cd /srv/wbi
    sudo mkdir -p apps-site && sudo cp -a /tmp/apps-site/. apps-site/
    sudo cp Caddyfile Caddyfile.bak && sudo cp docker-compose.yml docker-compose.yml.bak

Then edit by hand:

- `Caddyfile`: append the block in `deploy/Caddyfile.apps`.
- `docker-compose.yml`: add the `firesense-fitledger` service from `deploy/docker-compose.apps.yml`
  (fill in `<tenant>`), and add the volume `./apps-site:/srv/apps-site:ro` and
  `depends_on: firesense-fitledger` to the existing `caddy` service.

## 4. Start

    sudo docker compose pull firesense-fitledger
    sudo docker compose up -d
    sudo docker compose restart caddy     # Caddyfile changes are not picked up otherwise

(Use `docker-compose` if that is the installed command, as in the wbi README.)

## 5. Check

    curl -sI https://apps.predictiveecology.org/ | head -1
    curl -sI https://apps.predictiveecology.org/firesense/fitledger/ | head -1
    curl -sI https://wbi.predictiveecology.org/apps/wbi/ | head -1     # existing site still up

## Update later

New image: build and push as in step 1, then on the VM `sudo docker compose pull firesense-fitledger && sudo docker compose up -d`.
New site pages: rsync `site/` to `/srv/wbi/apps-site/`; Caddy serves them at once.
Roll back: restore `Caddyfile.bak` and `docker-compose.yml.bak`, then `up -d` and restart caddy.
