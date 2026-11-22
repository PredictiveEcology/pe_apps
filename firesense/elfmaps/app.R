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
GROUPS <- c("Observed", "Fit", "Spread coefficients")
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
  geo <- one("ELFs.geojson", function(f) sf::st_read(f, quiet = TRUE))
  geo$ELF <- as.character(geo$ELF)
  list(feat = feat, geo = geo)
}

# Order of features in the selector: dominant AGB, subdominant AGB, non-forest,
# climate, everything else; alphabetical by label (so by species) within each.
featureOrder <- function(id, label) {
  rank <- ifelse(grepl("^agb_dom", id), 1,
          ifelse(grepl("^agb_sub", id), 2,
          ifelse(grepl("non.?forest", id, ignore.case = TRUE), 3,
          ifelse(grepl("^clim|cmd|temperature|precip", id, ignore.case = TRUE), 4, 5))))
  order(rank, label)
}

fmtValue <- function(v, type) {
  ifelse(is.na(v), "no value",
         if (identical(type, "date")) format(as.Date(v, origin = "1970-01-01"), "%Y-%m-%d")
         else format(signif(v, 4), trim = TRUE, scientific = FALSE))
}

ui <- page_fluid(
  theme = bs_theme(version = 5, preset = "shiny"),
  title = "FireSense ELF maps",
  h2("FireSense ELF maps"),
  p("Observed data, fit information and fitted spread coefficients for each ELF",
    "(ecologically-based low fractal-dimension polygon). Pick a group and a feature to colour the map."),
  p(class = "text-muted small",
    "Spread coefficients are means over each fit's parameter sets, on the fitted covariate scale",
    "(fuel = biomass/1e4, centred). Compare them across ELFs only within one coefficient."),
  layout_columns(
    col_widths = c(4, 8),
    selectInput("group", "Show", GROUPS),
    selectInput("feature", "Feature", character(0), width = "100%")
  ),
  uiOutput("msg"),
  card(leafletOutput("map", height = 560)),
  card(card_header("ELFs"), DTOutput("tbl")),
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
    req(ok)
    f <- dat$feat[dat$feat$group == input$group, c("feature", "label")]
    f <- f[!duplicated(f$feature), ]
    f <- f[featureOrder(f$feature, f$label), ]
    updateSelectInput(session, "feature", choices = stats::setNames(f$feature, f$label))
  })

  # One row per ELF in the geometry, with the chosen feature's value.
  current <- reactive({
    req(ok, input$feature)
    f <- dat$feat[dat$feat$group == input$group & dat$feat$feature == input$feature, ]
    req(nrow(f) > 0)
    g <- dat$geo
    g$value <- f$value[match(g$ELF, f$ELF)]
    list(g = g, type = f$type[1], units = f$units[1], label = f$label[1])
  })

  output$map <- renderLeaflet({
    m <- leaflet() |> addProviderTiles("CartoDB.Positron")
    if (ok) {
      b <- sf::st_bbox(dat$geo)
      m <- fitBounds(m, b[["xmin"]], b[["ymin"]], b[["xmax"]], b[["ymax"]])
    } else m <- setView(m, -96, 56, 3)
    m
  })

  observe({
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
    html <- sprintf("<b>ELF %s</b><br>%s<br>%s: %s%s", g$ELF, htmltools::htmlEscape(g$name),
                    htmltools::htmlEscape(cur$label), shown, unitTxt)
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

  output$tbl <- renderDT({
    cur <- current()
    g <- sf::st_drop_geometry(cur$g)
    val <- if (identical(cur$type, "date")) ifelse(is.na(g$value), NA_character_, fmtValue(g$value, "date"))
           else g$value
    d <- data.frame(ELF = g$ELF, Name = g$name, Value = val, check.names = FALSE)
    names(d)[3] <- if (nzchar(cur$units)) paste0("Value (", cur$units, ")") else "Value"
    datatable(d, rownames = FALSE, filter = "top",
              options = list(pageLength = 25, scrollX = TRUE, order = list(list(0, "asc"))))
  })
}

shinyApp(ui, server)
