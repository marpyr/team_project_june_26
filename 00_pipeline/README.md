# Pipeline for Forecasting Heat-Related Mortality Risk in Switzerland

This folder contains the code pipeline which forecasts district-level heat health risk in Switzerland over a 5-day horizon by combining ICON-CH2 numerical weather forecasts with historical exposure-response relationships between temperature and mortality, and displays the results in an interactive map application.

## Pipeline overview

The scripts are numbered and must be run **in order**. Each step reads outputs produced by the previous one from the shared `00_pipeline_data/` folder.

| Step | Script | Description |
|------|--------|-------------|
| 1 | `01_download_iconfc_regrid.py` | Downloads the latest ICON-CH2 00 UTC forecast run (5-day horizon, hourly 2 m temperature) via Meteodata-lab, aggregates it to daily means, and regrids it from the native triangular ICON grid to a regular lat/lon grid. Saves the result as a NetCDF file for use in R. |
| 2 | `02_forecast_district_reformating.R` | Loads the regridded forecast raster and the Swiss district shapefile, extracts the (population-weighted and simple) mean daily temperature per district, and reshapes the result into a long-format CSV. |
| 3 | `03_get_MMT_baselineAF.R` | Two-part script: (a) `get_MMT_baselineAF` — estimates each district's minimum-mortality temperature (MMT) from the second-stage BLUP exposure-response curves and computes historical heat-attributable fraction (AF) baseline percentiles; (b) `calculate_warning_level` — applies the same exposure-response model to the forecast temperatures to compute forecast AF per district-day, then classifies each district-day into a heat-warning level (0–3), using either fixed or district-specific (baseline percentile) cut-points. |
| 4 | `04_ui_app.R` | Shiny app that visualizes the resulting warning levels on an interactive map of Swiss districts for the selected forecast day, plus a 5-day risk profile for a searched address. |

> **Note:** `0x_server_app.R` is not a pipeline step. It defines the Shiny `server` logic and is sourced automatically by `04_ui_app.R` — you don't need to run it directly.

## Requirements

**Python** (step 1):
- `earthkit-data`
- `meteodata-lab`
- `numpy`, `pandas`, `xarray`, `rasterio`

**R** (steps 2–4):
- `sf`, `terra`, `dplyr`, `tidyr`, `exactextractr`, `lubridate`
- `dlnm`, `mixmeta`
- `shiny`, `leaflet`, `leaflegend`, `bslib`, `httr`, `jsonlite`, `tidyverse`, `rnaturalearth`, `rnaturalearthdata`

## Data

All intermediate and input data are expected in a shared `00_pipeline_data/` folder (created relative to the repository root), including:
- the district shapefile
- gridded population data (`population.RDS`)
- historical district temperature time series (2000–2024)
- second-stage BLUP coefficients (`stage2_blup.rds`)


## Usage

1. Run `01_download_iconfc_regrid.py` to fetch and process the latest forecast.
2. Run `02_forecast_district_reformating.R` to aggregate the forecast to district level.
3. Run `03_get_MMT_baselineAF.R` to compute MMT/baseline AF and assign warning levels.
4. Run `04_ui_app.R` to launch the Shiny app.

