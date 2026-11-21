# pe_apps

Source for https://apps.predictiveecology.org: a static landing page and the Shiny apps it links to.
Local only so far; nothing here has been deployed.

## Layout

    site/                     static landing page (index.html, inline CSS)
    firesense/fitledger/      Shiny app: latest spread-fit and ignition-fit date per ELF
      app.R  Dockerfile  data/   (data/ is a small sample for local testing)
    deploy/                   Caddyfile block, compose additions, publish-data.sh, deploy steps
    README.md

## FireSense fit ledger

Shows a map, a sortable and searchable table, a "fitted in the last N days" slider and counts.
It only displays data. The csv (`ELF, spreadFitDate, spreadLedger, ignitionFitDate, ignitionLedger`)
and the png map are made by the `fireSense_ELFs` module with `fitDatesMap = TRUE`
(https://github.com/PredictiveEcology/fireSense_ELFs/pull/60) and uploaded with `deploy/publish-data.sh`.
The app reads them from `DATA_URL` (default `./data`) and holds no credentials.

Run locally:

    cd firesense/fitledger
    Rscript -e 'shiny::runApp(".", port = 3871)'     # needs shiny, bslib, DT, jsonlite
    # or: docker build -t fitledger . && docker run -p 8080:8080 fitledger
    # real data: docker run -e DATA_URL=https://... -p 8080:8080 fitledger

## Add an app

1. Make `<group>/<app>/` with a Shiny app and a Dockerfile that serves on port 8080 and uses relative URLs.
2. Image name `ghcr.io/predictiveecology/<group>-<app>:v1`.
3. Add a card to `site/index.html` (a link only once the app is live; text only for "coming").
4. In `deploy/`, add a service to the compose file and a `handle_path /<group>/<app>/*` block (with the matching
   `redir`) to the Caddyfile block, then follow `deploy/README.md`.
