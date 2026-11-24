# FireSense ELF maps: one map of ELFs coloured by a chosen feature (observed
# data, fit information or spread coefficients). Display only. ELFfeatures.csv
# and ELFs.geojson are published to DATA_URL (a base URL or a local folder).
# This app reads no Google Drive and holds no credentials.
library(shiny)
library(bslib)
library(DT)
library(leaflet)
library(sf)

DATA_URL <- sub("/+$", "", Sys.getenv("DATA_URL", "./data"))
GROUPS <- c("Observed", "Fit", "Spread coefficients", "Spread fuel effect", "NRV burn probability")
RASTER_GROUP <- "NRV burn probability"
# Cloud-optimised GeoTIFFs, read in the browser by range requests from <app>/data/
# (the web server proxies that path to the bucket). Values are the mean annual share of
# each cell burned; shown x100, on one scale for both layers (capped at RASTER_CAP percent).
## Web Mercator (EPSG:3857) display copies made by deploy/publish-data.sh: the map draws them without reprojecting in the
## browser (the georaster layer misplaced the EPSG:3978 originals relative to the ELF outlines)
RASTERS <- c(sim = "NRVburnProbability_3857.tif", obs = "NRVburnProbabilityHistoric_3857.tif")
RASTER_LABELS <- c(sim = "Simulated (NRV simulations)", obs = "Observed (NBAC)")
RASTER_CAP <- 5
CDN <- c(proj4 = "https://cdn.jsdelivr.net/npm/proj4@2.11.0/dist/proj4.js",
         georaster = "https://cdn.jsdelivr.net/npm/georaster@1.6.0/dist/georaster.browser.bundle.min.js",
         layer = "https://cdn.jsdelivr.net/npm/georaster-layer-for-leaflet@3.10.0/dist/georaster-layer-for-leaflet.min.js")
NOVAL <- "#BDBDBD"

fetch <- function(name) {
  src <- paste0(DATA_URL, "/", name)
  if (!grepl("^https?://", src)) return(src)
  dest <- tempfile(fileext = paste0(".", tools::file_ext(name)))
  utils::download.file(src, dest, mode = "wb", quiet = TRUE)
  dest
}

# Read both files; return the data or an error message naming the file.
readData <- function() {
  one <- function(name, reader) {
    tryCatch(reader(fetch(name)),
             error = function(e) stop("Could not read ", name, " from ", DATA_URL, call. = FALSE),
             warning = function(w) stop("Could not read ", name, " from ", DATA_URL, call. = FALSE))
  }
  feat <- one("ELFfeatures.csv", function(f)
    utils::read.csv(f, stringsAsFactors = FALSE, colClasses = c(ELF = "character",
      group = "character", feature = "character", label = "character", units = "character",
      type = "character", value = "numeric"), na.strings = "NA"))
  feat$units[is.na(feat$units)] <- ""
  ## per ELF: for a species from a grouped fuel term, the species it shares that term with in THIS ELF
  feat$note <- if (is.null(feat$note)) "" else ifelse(is.na(feat$note), "", as.character(feat$note))
  geo <- one("ELFs.geojson", function(f) sf::st_read(f, quiet = TRUE))
  geo$ELF <- as.character(geo$ELF)
  list(feat = feat, geo = geo)
}

## Province and territory outlines for the raster layers: Natural Earth 1:10m admin-1 (public domain), Canada only,
## simplified to 0.01 degree; shipped with the app, not read from DATA_URL
JURISDICTIONS <- sf::st_read("data/jurisdictions.geojson", quiet = TRUE)  # shiny runs the app from its own folder

# Order of features in the selector, by the real feature ids. Observed and Fit have a fixed
# order. Spread coefficients: dominant AGB, subdominant AGB, non-forest classes, young stands
# and treed wetland, climate terms (anything else), then intercept, link shape and year SD.
# Within a rank: by label, with numbers compared as numbers (LCC 40 before LCC 100).
FIXED_ORDER <- c("naturalFiresPerYear", "haBurnedPerYear", "naturalFiresPer100km2PerYear",
                 "percentBurnedPerYear", "spreadFitDate", "ignitionFitDate")
featureOrder <- function(id, label) {
  rank <- ifelse(id %in% FIXED_ORDER, match(id, FIXED_ORDER),
          ifelse(grepl("^(spread|spreadEffect)_dom_agb", id), 11,
          ifelse(grepl("^(spread|spreadEffect)_sec_agb", id), 12,
          ifelse(grepl("^spread_nfLCC", id), 13,
          ifelse(grepl("^spread_(youngAge|treedWetland)", id), 14,
          ifelse(grepl("^spread_(Intercept|maxAsymptote|hillSlope|inflectionPoint|yearSpreadSD)", id), 16,
                 15)))))) 
  text <- gsub("[0-9]+", "", label)
  nums <- vapply(regmatches(label, gregexpr("[0-9]+", label)),
                 function(m) paste(sprintf("%08d", as.integer(m)), collapse = "-"), "")
  order(rank, text, nums, label)
}

fmtValue <- function(v, type) {
  ifelse(is.na(v), "no value",
         if (identical(type, "date")) format(as.Date(v, origin = "1970-01-01"), "%Y-%m-%d")
         else format(signif(v, 4), trim = TRUE, scientific = FALSE))
}

RASTER_JS <- "
(function () {
  var layer = null, token = 0, loaded = null;
  function load(src) {
    return new Promise(function (ok, bad) {
      var s = document.createElement('script');
      s.src = src; s.onload = ok; s.onerror = function () { bad(new Error('could not load ' + src)); };
      document.head.appendChild(s);
    });
  }
  function libs(l) {
    if (!loaded) loaded = load(l.proj4).then(function () {
      proj4.defs('EPSG:3978', '+proj=lcc +lat_0=49 +lon_0=-95 +lat_1=49 +lat_2=77 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs');
      return load(l.georaster);
    }).then(function () { return load(l.layer); });
    return loaded;
  }
  function note(map, msg) {
    if (map._elfNote) { map._elfNote.remove(); map._elfNote = null; }
    if (!msg) return;
    var c = L.control({position: 'topleft'});
    c.onAdd = function () { var d = L.DomUtil.create('div', 'alert alert-secondary py-1 px-2 mb-0 small'); d.textContent = msg; return d; };
    c.addTo(map); map._elfNote = c;
  }
  Shiny.addCustomMessageHandler('elfRaster', function (m) {
    var w = HTMLWidgets.find('#map'); if (!w) return;
    var map = w.getMap(), me = ++token;
    if (layer) { map.removeLayer(layer); layer = null; }
    note(map, null);
    if (!m.url) return;
    note(map, 'Loading raster...');
    libs(m.libs).then(function () {
      return parseGeoraster(new URL(m.url, document.baseURI).href);
    }).then(function (g) {
      if (me !== token) return;
      var n = m.colors.length;
      layer = new GeoRasterLayer({
        georaster: g, opacity: 0.85, resolution: 128,
        pixelValuesToColorFn: function (v) {
          var x = v[0] * 100;
          if (!isFinite(x) || x <= 0) return null;
          return m.colors[Math.min(n - 1, Math.round(x / m.cap * (n - 1)))];
        }
      });
      layer.addTo(map); note(map, null);
    }).catch(function (e) { if (me === token) note(map, 'Raster not available: ' + e.message); });
  });
})();
"

## the map-height slider: sets the map's height to a share of the window, redraws Leaflet, keeps the choice per browser
MAPHEIGHT_JS <- "
window.elfMapHeight = function (v) {
  var el = document.getElementById('map'); if (!el) return;
  el.style.height = v + 'vh';
  var s = document.getElementById('mapHv'); if (s) s.textContent = v + '% of window';
  var w = window.HTMLWidgets && HTMLWidgets.find('#map'); if (w && w.getMap) w.getMap().invalidateSize();
  try { localStorage.setItem('elfMapH', v); } catch (e) {}
};
$(document).on('shiny:connected', function () {
  var v = null; try { v = localStorage.getItem('elfMapH'); } catch (e) {}
  if (v) { var r = document.getElementById('mapH'); if (r) r.value = v; setTimeout(function () { elfMapHeight(v); }, 300); }
});
"

ui <- page_fluid(
  theme = bs_theme(version = 5, preset = "shiny"),
  title = "FireSense ELF maps",
  tags$head(tags$script(HTML(RASTER_JS))),
  h2("FireSense ELF maps"),
  p("Observed data, fit information and fitted spread coefficients for each ELF",
    "(ecologically-based low fractal-dimension polygon). Pick a group and a feature to colour the map."),
  p(class = "text-muted small",
    "Spread coefficients are means over each fit's parameter sets, on the fitted covariate scale",
    "(fuel = biomass/1e4, centred). Compare them across ELFs only within one coefficient.",
    "Spread fuel effect: the change in spread probability when a species' fuel term goes from 0 to its",
    "median non-zero biomass in the fit data, other covariates at their centres."),
  layout_columns(
    col_widths = c(4, 8),
    selectInput("group", "Show", GROUPS),
    selectInput("feature", "Feature", character(0), width = "100%")
  ),
  uiOutput("msg"),
  ## map height: a slider (share of the window height, remembered in this browser) and the card's full-screen button
  div(class = "d-flex align-items-center gap-2 small mb-1",
      tags$label("Map height", `for` = "mapH", class = "mb-0"),
      tags$input(type = "range", id = "mapH", min = 40, max = 100, step = 5, value = 75, style = "width: 12em;",
                 oninput = "elfMapHeight(this.value)"),
      span(id = "mapHv", "75% of window")),
  card(full_screen = TRUE, leafletOutput("map", height = "75vh")),
  tags$script(HTML(MAPHEIGHT_JS)),
  uiOutput("tblCard"),
  tags$footer(class = "text-muted small my-3", textOutput("loaded"))
)

server <- function(input, output, session) {
  dat <- tryCatch(readData(), error = function(e) e)
  ok <- !inherits(dat, "error")

  output$msg <- renderUI({
    if (!ok) div(class = "alert alert-warning", conditionMessage(dat))
  })
  output$loaded <- renderText(paste("Data from", DATA_URL))

  observeEvent(input$group, {
    if (input$group == RASTER_GROUP) {
      updateSelectInput(session, "feature", choices = stats::setNames(names(RASTERS), RASTER_LABELS))
      return()
    }
    req(ok)
    f <- dat$feat[dat$feat$group == input$group, c("feature", "label")]
    f <- f[!duplicated(f$feature), ]
    f <- f[featureOrder(f$feature, f$label), ]
    updateSelectInput(session, "feature", choices = stats::setNames(f$feature, f$label))
  })

  # One row per ELF in the geometry, with the chosen feature's value.
  isRaster <- reactive(identical(input$group, RASTER_GROUP))

  current <- reactive({
    req(ok, input$feature, !isRaster())
    f <- dat$feat[dat$feat$group == input$group & dat$feat$feature == input$feature, ]
    req(nrow(f) > 0)
    g <- dat$geo
    g$value <- f$value[match(g$ELF, f$ELF)]
    g$note <- f$note[match(g$ELF, f$ELF)]
    g$note[is.na(g$note)] <- ""
    list(g = g, type = f$type[1], units = f$units[1], label = f$label[1])
  })

  output$map <- renderLeaflet({
    m <- leaflet() |> addProviderTiles("Esri.WorldGrayCanvas") # Carto basemaps now need an API key (tiles say "API KEY REQUIRED")
    if (ok) {
      b <- sf::st_bbox(dat$geo)
      m <- fitBounds(m, b[["xmin"]], b[["ymin"]], b[["xmax"]], b[["ymax"]])
    } else m <- setView(m, -96, 56, 3)
    m
  })

  # Raster group: province and territory outlines without fill (Natural Earth admin-1, bundled in data/),
  # the chosen COG drawn under them by the browser.
  observe({
    req(ok, isRaster(), input$feature %in% names(RASTERS))
    pal <- colorNumeric("YlOrRd", c(0, RASTER_CAP))
    title <- paste0("Mean annual % of area burned<br>(", RASTER_LABELS[[input$feature]], ")")
    g <- JURISDICTIONS
    html <- sprintf("<b>%s</b>", htmltools::htmlEscape(g$name))
    leafletProxy("map", data = g) |>
      clearShapes() |> clearControls() |>
      addPolygons(fill = FALSE, color = "#333333", weight = 1.2, opacity = 0.9,
                  label = lapply(html, htmltools::HTML),
                  highlightOptions = highlightOptions(weight = 3, color = "#000000")) |>
      addLegend("bottomright", pal = pal, values = c(0, RASTER_CAP), title = title, opacity = 0.9,
                labFormat = function(type, cuts, p) ifelse(cuts >= RASTER_CAP, paste0(cuts, "+"), cuts))
    session$sendCustomMessage("elfRaster", list(
      url = paste0("data/", RASTERS[[input$feature]]), cap = RASTER_CAP,
      colors = pal(seq(0, RASTER_CAP, length.out = 256)), libs = as.list(CDN)))
  })

  observe({
    if (!isRaster()) session$sendCustomMessage("elfRaster", list(url = NULL))
  })

  observe({
    req(!isRaster())
    cur <- current()
    g <- cur$g; v <- g$value
    isDate <- identical(cur$type, "date")
    rng <- range(v, na.rm = TRUE)
    if (!is.finite(rng[1])) rng <- c(0, 1)
    if (input$group == "Spread coefficients") {
      m <- max(abs(rng)); if (m == 0) m <- 1
      dom <- c(-m, m)
      pal <- colorNumeric(c("#2166AC", "#FFFFFF", "#B2182B"), dom, na.color = NOVAL)
    } else if (isDate) {
      dom <- if (rng[1] == rng[2]) rng + c(-1, 1) else rng
      pal <- colorNumeric(c("#D73027", "#FEE08B", "#1A9850"), dom, na.color = NOVAL)  # old red, new green
    } else {
      dom <- if (rng[1] == rng[2]) rng + c(-1, 1) else rng
      pal <- colorNumeric("YlGnBu", dom, na.color = NOVAL)
    }
    shown <- fmtValue(v, cur$type)
    unitTxt <- ifelse(nzchar(cur$units) & !is.na(v), paste0(" ", cur$units), "")
    html <- sprintf("<b>ELF %s</b><br>%s<br>%s: %s%s%s", g$ELF, htmltools::htmlEscape(g$name),
                    htmltools::htmlEscape(cur$label), shown, unitTxt,
                    ifelse(nzchar(g$note), paste0("<br><i>", htmltools::htmlEscape(g$note), " in this ELF</i>"), ""))
    labFmt <- if (isDate) function(type, cuts, p) format(as.Date(cuts, origin = "1970-01-01"), "%Y-%m-%d")
              else labelFormat()
    title <- if (nzchar(cur$units)) paste0(cur$label, " (", cur$units, ")") else cur$label
    leafletProxy("map", data = g) |>
      clearShapes() |> clearControls() |>
      addPolygons(fillColor = ~pal(value), fillOpacity = 0.8, color = "#555555", weight = 1,
                  label = lapply(html, htmltools::HTML), popup = html,
                  highlightOptions = highlightOptions(weight = 3, color = "#000000", bringToFront = TRUE)) |>
      addLegend("bottomright", pal = pal, values = dom, title = title, opacity = 0.9,
                labFormat = labFmt, na.label = "no value")
  })

  output$tblCard <- renderUI({
    if (!isRaster()) card(card_header("ELFs"), DTOutput("tbl"))
  })

  output$tbl <- renderDT({
    cur <- current()
    g <- sf::st_drop_geometry(cur$g)
    val <- if (identical(cur$type, "date")) ifelse(is.na(g$value), NA_character_, fmtValue(g$value, "date"))
           else g$value
    d <- data.frame(ELF = g$ELF, Name = g$name, Value = val, check.names = FALSE)
    names(d)[3] <- if (nzchar(cur$units)) paste0("Value (", cur$units, ")") else "Value"
    if (any(nzchar(g$note))) d[["Fuel term shared with"]] <- sub("^shared with ", "", g$note)
    datatable(d, rownames = FALSE, filter = "top",
              options = list(pageLength = 25, scrollX = TRUE, order = list(list(0, "asc"))))
  })
}

shinyApp(ui, server)
