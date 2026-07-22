# In this app, we show a relative metric of forecasted mortality risk due to heat exposure for Switzerland
# through a map for a selected day (today - today+4days) and for searched locations
# over the entire 5-day forecast.

# To run the app, you need to run this script line by line

# packages
library(lubridate); library(sf); library(tidyverse); library(shiny); library(leaflet)
library(httr); library(jsonlite); library(bslib); library(rnaturalearth); library(rnaturalearthdata); library(leaflegend)


# clear environment
rm(list = ls())

# Data and preparation of UI
#----

# load data from group Health Impact Assessment
impacts <- read_csv("00_pipeline_data/warning_level.csv") |>
  rename(timestep = "time",
         risk = "warning_level",
         district = "BEZNAME") |>
    mutate(date_EU = format(timestep, "%d.%m.%y"))

# load and reproject shapefile
shp_distr=read_sf("00_pipeline_data/district_shapefile/") |>
    dplyr::select(BEZNAME, geometry)
shp_distr <- st_transform(shp_distr, crs = 4326)


# extract dates from data and convert to more visual form
unique_dates_US <- unique(impacts$timestep)
date_formatted <- format(unique_dates_US, "%d %b")  # gives "17 Jun"

#----


# start UI
ui <- fluidPage(
  theme = bs_theme(bootswatch = "flatly"),

  # logo and title
  #----

  tags$div(
    style = "display: flex; justify-content: space-between; align-items: center; padding: 10px 25px;",
    tags$div(
      tags$p(
        tags$span(
          "Forecasting\u00a0",
          style = "font-size: 100px; color: #1a1a1a; letter-spacing: -0.5px; font-weight: 700;"
        ),
        tags$span(
          "heat-related mortality",
          class = "heatwave-text",
          style = "font-size: 100px; color: #1a1a1a; letter-spacing: -0.5px;"
        ),
        tags$span(
          "\u00a0risk",
          style = "font-size: 100px; color: #1a1a1a; letter-spacing: -0.5px; font-weight: 700;"
        ),
        tags$span(
          "\u00a0in Switzerland",
          style = "font-size: 100px; color: #1a1a1a; letter-spacing: -0.5px; font-style: italic;"
        ),
        style = "margin: 0; line-height: 1.2;"
      ),
      tags$p(
        "Created by the Climate Epidemiology and Public Health research group from the University of Bern",
        style = "font-size: 40px; font-weight: 400; margin: 0;
                 color: #888888; letter-spacing: 0.3px;"
      )
    ),
    tags$img(src = "www/logo.png", height = "300px", width = "auto")
  ),

  #----

  # CSS
  #----

  tags$style(HTML("
    .heatwave-text {
      display: inline-block;
      position: relative;
      font-weight: 700;
      animation: heatwave 2s infinite ease-in-out;
    }
    @keyframes heatwave {
      0%   { filter: blur(0px); transform: translateY(0px) skewX(0deg); opacity: 1; }
      25%  { filter: blur(1px); transform: translateY(-0.5px) skewX(0.3deg); opacity: 0.8; }
      50%  { filter: blur(2px); transform: translateY(0.5px) skewX(-0.3deg); opacity: 0.6; }
      75%  { filter: blur(1px); transform: translateY(-0.5px) skewX(0.3deg); opacity: 0.8; }
      100% { filter: blur(0px); transform: translateY(0px) skewX(0deg); opacity: 1; }
    }
    .day-strip {
      display: flex;
      gap: 0;
      margin: 8px 15px 24px;
      border-radius: 9px;
      overflow: hidden;
      border: 1px solid #C0392B;
      background: white;
    }
    .day-btn {
      flex: 1;
      border: none;
      border-right: 1px solid #C0392B;
      background: white;
      padding: 10px 6px 9px;
      cursor: pointer;
      text-align: center;
      transition: background 0.12s;
      line-height: 1.3;
    }
    .day-btn:last-child { border-right: none; }
    .day-btn .lbl {
      display: block;
      font-size: 1.8rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.07em;
      color: #8a97a8;
    }
    .day-btn .dt {
      display: block;
      font-family: monospace;
      font-size: 2.2rem;
      font-weight: 600;
      color: #1e293b;
    }
    .day-btn .wd {
      display: block;
      font-size: 1.8rem;
      color: #b0bac6;
    }
    .day-btn.active { background: #C0392B; }
    .day-btn.active .lbl,
    .day-btn.active .dt,
    .day-btn.active .wd { color: white !important; opacity: 1; }
    .day-btn:not(.active):hover { background: #f4f6fa; }
    #address_input-label {
      font-size: 2.9rem;
      font-weight: 600;
      color: #1a1a1a;
      width: 80%;
      display: block;
    }
    #address_input {
      font-size: 2.9rem;
      width: 65% !important;
      box-sizing: border-box;
    }
    #address_input::placeholder {
      font-size: 2.7rem;
      color: #b0bac6;
    }
    .form-group {
      width: 100%;
    }
    .addr-suggestion {
      font-size: 2.3rem;
      width: 100%;
      text-align: left;
      border-radius: 0;
      border: none;
      border-bottom: 1px solid #eee;
      background: white;
      color: #333;
      white-space: normal;
      height: auto;
      padding: 8px 12px;
    }
  ")),

  #----

  # Two columns
  #----

  # main layout — flex container replacing fluidRow
  tags$div(
    style = "display: flex; align-items: stretch; padding: 0 15px;",

    # left column — buttons + map
    tags$div(
      style = "flex: 0 0 58%;",
      tags$div(
        class = "day-strip",
        lapply(seq_along(unique_dates_US), function(i) {
          date_obj       <- as.Date(unique_dates_US[i])
          date_formatted <- format(date_obj, "%d %b")
          weekday        <- format(date_obj, "%A")
          lbl            <- if (i == 1) "Today" else if (i == 2) "Tomorrow" else "\u00a0"
          tags$button(
            id      = paste0("btn_date_", i),
            class   = paste("day-btn", if (i == 1) "active" else ""),
            onclick = paste0("Shiny.setInputValue('btn_date_clicked', ", i, ", {priority: 'event'})"),
            tags$span(class = "lbl", lbl),
            tags$span(class = "dt",  date_formatted),
            tags$span(class = "wd",  weekday)
          )
        })
      ),
      leafletOutput("heat_map", height = "1100px")
    ),

    # right column — search + plot + text + disclaimer pinned to bottom
    tags$div(
      style = "flex: 0 0 42%; display: flex; flex-direction: column; padding-left: 15px;",

      # search bar
      tags$div(
        style = "padding: 8px 0;",
        textInput(
          inputId     = "address_input",
          label       = "Search your address to see your 5-day risk forecast:",
          placeholder = "e.g. Bundesplatz 3, Bern",
          width       = "100%"
        ),
        uiOutput("address_suggestions")
      ),

      # barplot
      plotOutput("risk_plot", height = "300px", width = "800px"),

      # text blocks
      tags$div(
        style = "padding: 15px 5px; font-size: 2.5rem; color: #333; line-height: 1.8;",

        tags$p(
          style = "font-size: 2.5rem; font-weight: 600; color: #1a1a1a; margin-bottom: 8px;",
          "What does this forecast show?"
        ),
        tags$p(
          style = "font-size: 2.2rem; color: #444;",
          "This tool displays the forecasted heat-related mortality risk for your district over the next 5 days.
           Risk levels are estimated based on temperature forecasts and historical exposure-response relationships."
        ),

        tags$br(),

        tags$p(
          style = "font-size: 2.5rem; font-weight: 600; color: #1a1a1a; margin-bottom: 8px;",
          "What should I do?"
        ),
        tags$p(
          style = "font-size: 2.2rem; color: #444;",
          "If risk is medium or high, please check on elderly or vulnerable people around you.
           For official heat health advice, visit the ",
          tags$a(
            href   = "https://www.bag.admin.ch",
            target = "_blank",
            style  = "color: #C0392B; text-decoration: underline;",
            "Federal Office of Public Health"
          ),
          "."
        ),

        tags$br(),

        tags$p(
          style = "font-size: 2.5rem; font-weight: 600; color: #1a1a1a; margin-bottom: 8px;",
          "About this project"
        ),
        tags$p(
          style = "font-size: 2.2rem; color: #444;",
          "Developed by the ",
          tags$a(
            href   = "https://www.ispm.unibe.ch/research/research_groups_and_themes/climate_epidemiology_and_public_health/index_eng.html",
            target = "_blank",
            style  = "color: #C0392B; text-decoration: underline;",
            "Climate Epidemiology and Public Health research group"
          ),
          " at the University of Bern. For questions, contact ",
          tags$a(
            href   = "mailto:info@ispm.unibe.ch",
            style  = "color: #C0392B; text-decoration: underline;",
            "info@ispm.unibe.ch"
          ),
          "."
        )
      ),

      # spacer pushes disclaimer to bottom
      tags$div(style = "flex: 1;"),

      # disclaimer pinned to bottom
      tags$p(
        style = "font-size: 2rem; color: #888; font-style: italic;
                 line-height: 1.5; padding: 0 5px 10px 5px; margin: 0;",
        "Disclaimer: This tool does not display uncertainties in the calculated risk levels and is not a prediction of future risk."
      )
    )
  ),

  # JS handler for active button state
  tags$script(HTML("
      Shiny.addCustomMessageHandler('setActiveBtn', function(i) {
          document.querySelectorAll('.day-btn').forEach(function(btn, idx) {
              btn.classList.toggle('active', idx + 1 === i);
          });
      });
  "))

  #----
)

# source server function
source("00_pipeline/0x_server_app.R")

# run app
shinyApp(ui = ui, server = server)

