# pe_apps

Source for https://apps.predictiveecology.org: a static landing page and the Shiny apps it links to.
Local only so far; nothing here has been deployed.

## Layout

    site/                     static landing page (index.html, inline CSS)
    firesense/elfmaps/        Shiny app: map and table of ELF features (observed, fit, spread coefficients)
      app.R  Dockerfile  data/   (data/ is a synthetic sample for local testing)
    deploy/                   Caddyfile block, compose additions, publish-data.sh, deploy steps
    README.md

## FireSense ELF maps

Replaces the fit ledger app (`/firesense/fitledger/` now redirects here). A leaflet map coloured by one
feature at a time, with a sortable table. It only displays data. `ELFfeatures.csv` (long table: ELF, group,
feature, label, units, type, value) and `ELFs.geojson` (ELF, name; EPSG:4326) and two NRV burn probability COGs are uploaded with
`deploy/publish-data.sh`. The app reads them from `DATA_URL` (default `./data`, a small bundled copy of the first two) at the
start of each session and holds no credentials. The rasters are streamed by the browser from `<app>/data/`, which Caddy proxies to the bucket.

Run locally:

    cd firesense/elfmaps
    Rscript -e 'shiny::runApp(".", port = 3871)'     # needs shiny, bslib, DT, leaflet, sf
    # or: docker build -t firesense-elfmaps:v4 . && docker run -p 18080:8080 firesense-elfmaps:v4
    # real data: docker run -e DATA_URL=https://... -p 18080:8080 firesense-elfmaps:v4

## Add an app

1. Make `<group>/<app>/` with a Shiny app and a Dockerfile that serves on port 8080 and uses relative URLs.
2. Image name `ghcr.io/predictiveecology/<group>-<app>:v1`.
3. Add a card to `site/index.html` (a link only once the app is live; text only for "coming").
4. In `deploy/`, add a service to the compose file and a `handle_path /<group>/<app>/*` block (with the matching
   `redir`) to the Caddyfile block, then follow `deploy/README.md`.
