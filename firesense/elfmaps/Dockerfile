FROM eddelbuettel/r2u:jammy

RUN install2.r --error shiny bslib DT leaflet sf jsonlite

RUN mkdir /app
COPY app.R /app/app.R
COPY data /app/data
WORKDIR /app

RUN addgroup --system shiny && adduser --system --ingroup shiny shiny
USER shiny

EXPOSE 8080
# DATA_URL: base URL (or folder) of the published ELFfeatures.csv + ELFs.geojson; defaults to the bundled ./data sample
ENV DATA_URL=./data
CMD ["R", "-e", "options('shiny.port'=8080,shiny.host='0.0.0.0');shiny::runApp('/app')"]
