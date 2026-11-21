# FireSense fit ledger: shows, per ELF, the date of the latest production
# spread fit and ignition fit. Display only. The csv and png are made by the
# fireSense_ELFs module (fitDatesMap = TRUE, PredictiveEcology/fireSense_ELFs#60)
# and published to DATA_URL. This app reads no Google Drive and holds no credentials.
library(shiny)
library(bslib)
library(DT)

DATA_URL <- sub("/+$", "", Sys.getenv("DATA_URL", "./data"))
TZ <- "America/Vancouver"

fetch <- function(name, dest = tempfile(fileext = paste0(".", tools::file_ext(name)))) {
  src <- paste0(DATA_URL, "/", name)
  if (grepl("^https?://", src)) {
    utils::download.file(src, dest, mode = "wb", quiet = TRUE)
    dest
  } else {
    src
  }
}

readLedger <- function() {
  x <- utils::read.csv(fetch("ELFfitDates.csv"), stringsAsFactors = FALSE,
                       colClasses = "character", na.strings = c("", "NA"))
  for (col in c("spreadFitDate", "ignitionFitDate"))
    x[[col]] <- as.POSIXct(x[[col]], format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  x
}

ui <- page_fluid(
  theme = bs_theme(version = 5, preset = "shiny"),
  title = "FireSense fit ledger",
  tags$head(tags$style("img.map { max-width: 100%; height: auto; }")),
  h2("FireSense fit ledger"),
  p("Latest production spread fit and ignition fit for each ELF."),
  layout_columns(
    col_widths = c(12, 12, 12),
    uiOutput("counts"),
    card(card_header("Fitted in the last N days"),
         sliderInput("days", NULL, min = 1, max = 120, value = 30, width = "100%"),
         checkboxGroupInput("which", NULL, inline = TRUE,
                            choices = c("spread fit" = "spread", "ignition fit" = "ignition"),
                            selected = c("spread", "ignition")),
         p(class = "text-muted small mb-0",
           "The table lists ELFs with at least one selected fit inside the window.")),
    card(card_header("Map"), uiOutput("map"))
  ),
  card(card_header("ELFs"), DTOutput("tbl")),
  card(card_header("About"),
       p("This page only displays data. The dates, ledger names and map are produced by the",
         tags$code("fireSense_ELFs"), "module with", tags$code("fitDatesMap = TRUE"),
         "(", tags$a("PredictiveEcology/fireSense_ELFs#60",
                     href = "https://github.com/PredictiveEcology/fireSense_ELFs/pull/60"), ")",
         "and published as a csv and a png. Times are shown in Pacific time.")),
  tags$footer(class = "text-muted small my-3", textOutput("loaded"))
)

server <- function(input, output, session) {
  led <- tryCatch(readLedger(), error = function(e) e)
  mapFile <- tryCatch(fetch("ELFfitDates.png"), error = function(e) NULL)
  validate_led <- function() {
    validate(need(!inherits(led, "error"),
                  paste("Could not read ELFfitDates.csv from", DATA_URL)))
    led
  }
  ageDays <- function(t) as.numeric(difftime(Sys.time(), t, units = "days"))
  fmt <- function(t) ifelse(is.na(t), "", format(t, "%Y-%m-%d %H:%M", tz = TZ))

  output$counts <- renderUI({
    x <- validate_led()
    n <- nrow(x)
    ns <- sum(!is.na(x$spreadFitDate)); ni <- sum(!is.na(x$ignitionFitDate))
    rs <- sum(ageDays(x$spreadFitDate) <= input$days, na.rm = TRUE)
    ri <- sum(ageDays(x$ignitionFitDate) <= input$days, na.rm = TRUE)
    tile <- function(v, l) div(class = "col", div(class = "fs-3 fw-semibold", v),
                               div(class = "text-muted small", l))
    div(class = "row text-center",
        tile(n, "ELFs"),
        tile(ns, "with a spread fit"), tile(ni, "with an ignition fit"),
        tile(rs, paste("spread fits in last", input$days, "days")),
        tile(ri, paste("ignition fits in last", input$days, "days")))
  })

  output$map <- renderUI({
    if (is.null(mapFile) || !file.exists(mapFile)) return(p("Map not available."))
    tags$img(class = "map", alt = "Map of ELFs coloured by latest fit date",
             src = base64enc_uri(mapFile))
  })

  filtered <- reactive({
    x <- validate_led()
    keep <- rep(FALSE, nrow(x))
    if ("spread" %in% input$which) keep <- keep | ageDays(x$spreadFitDate) <= input$days
    if ("ignition" %in% input$which) keep <- keep | ageDays(x$ignitionFitDate) <= input$days
    x[which(keep), , drop = FALSE]
  })

  output$tbl <- renderDT({
    x <- filtered()
    d <- data.frame(ELF = x$ELF,
                    `Spread fit date` = fmt(x$spreadFitDate), `Spread ledger` = x$spreadLedger,
                    `Ignition fit date` = fmt(x$ignitionFitDate), `Ignition ledger` = x$ignitionLedger,
                    check.names = FALSE)
    datatable(d, rownames = FALSE, filter = "top", options = list(pageLength = 25, scrollX = TRUE,
              order = list(list(0, "asc"))))
  })

  output$loaded <- renderText(paste("Data from", DATA_URL))
}

base64enc_uri <- function(f) {
  raw <- readBin(f, "raw", file.size(f))
  paste0("data:image/png;base64,", jsonlite::base64_enc(raw))
}

shinyApp(ui, server)
