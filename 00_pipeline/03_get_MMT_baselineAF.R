# ──────────────────────────────────────────────────────────────────────────────
# get_MMT_baselineAF.R — post-process second-stage BLUP coefficients
# Annual Team Project 2026
#
# RUN THIS FIRST (before calculate_warning_level.R). For every district it:
#   (a) estimates the minimum-mortality temperature (MMT) from the BLUP curve,
#   (b) computes the historical heat-attributable fraction (AF), and
#   (c) derives district-specific baseline AF percentiles used as warning cut-points.
#
# Inputs : historical_temp_popw_mvngpop_2000_2024_district.csv
#          secondstage_blup.rds
# Outputs: mmt.rds
#          baseline_summer.csv
# ──────────────────────────────────────────────────────────────────────────────

# ---- 0. Set-up ---------------------------------------------------------------
# ---- Libraries ---------------------------------------------------------------
library(dlnm)       # onebasis(): exposure–response basis
library(mixmeta)    # second-stage / BLUP object methods
library(dplyr)      # data wrangling + the %>% pipe
library(lubridate)  # month(), day(), year()

# ---- Set up file paths -------------------------------------------------------
# Data directory is read from an environment variable so that no machine-specific
# path is hard-coded. Set ATP2026_DATA_DIR in your ~/.Renviron (see
# .Renviron.example). Falls back to a local "data/" folder if unset.
data_dir   <- getwd()

# Inputs
f_hist_temp <- file.path(data_dir,   "/00_pipeline_data/historical_temp_popw_mvngpop_2000_2024_district.csv")
f_forecast_temp <- file.path(data_dir,   "/00_pipeline_data/forecast_clean_district.csv")
f_blup <- file.path(data_dir, "/00_pipeline_data/stage2_blup.rds")

# Produced by get_MMT_baselineAF.R, consumed by calculate_warning_level.R
f_mmt <- file.path(data_dir, "/00_pipeline_data/mmt.rds")
f_baseline <- file.path(data_dir, "/00_pipeline_data/baseline_summer.csv")

# Final output of calculate_warning_level.R
f_warning       <- file.path(data_dir, "00_pipeline_data/warning_level.csv")

# ---- Configuration -----------------------------------------------------------

# District(s) to drop (no resident population / water body).
exclude_districts <- "2604"

# Exposure–response specification.
# IMPORTANT: these MUST match the specification used to FIT the first-/second-stage
# model that produced the BLUP coefficients. Changing them here without refitting
# the model will silently produce wrong attributable fractions.
varfun <- "ns"        # natural cubic spline
varper <- c(50, 90)   # internal knot placement (percentiles of temperature)


# ---- 1. Historical temperature (summer, May–Sep), per district ---------------
# f_hist_temp <- file.path(data_dir, "historical_temp_popw_mvngpop_2000_2024_district.csv")
temp_dist_sum <- read.csv(f_hist_temp) %>%
  select(-any_of("X")) %>%
  filter(month(time) %in% 5:9) %>%
  filter(BEZNR != exclude_districts)
temp_dist_list <- split(temp_dist_sum, temp_dist_sum$BEZNR)

# BLUP coefficients, keyed by district (see load_blup() note on ordering).
res_blup <- readRDS(f_blup)
names(res_blup) <- names(temp_dist_list)
district_ids <- names(res_blup)


# ---- 2. Estimate MMT per district --------------------------------------------
# MMT = the temperature (searched over the 25th–90th percentiles) at which the
# district BLUP exposure–response curve is lowest.
minperccity <- setNames(rep(NA_real_, length(district_ids)), district_ids)
mintempcity <- setNames(rep(NA_real_, length(district_ids)), district_ids)

for (dist_id in district_ids) {
  temps   <- temp_dist_list[[dist_id]]$mean_value
  predper <- 25:90                                  # candidate percentiles
  predvar <- quantile(temps, predper / 100, na.rm = TRUE)

  # REDEFINE THE FUNCTION USING ALL THE ARGUMENTS (BOUNDARY KNOTS INCLUDED)
  argvar <- list(
    x = predvar,
    fun = varfun,
    knots = quantile(temps, varper / 100, na.rm = T),
    Bound = range(temps, na.rm = T)
  )

  bvar <- do.call(onebasis, argvar)

  minperccity[dist_id] <- (25:90)[which.min((bvar %*% res_blup[[dist_id]]$blup))]
  mintempcity[dist_id] <- quantile(temps, minperccity[dist_id] / 100, na.rm = T)
}

mmt_list <- list(minperccity = minperccity, mintempcity = mintempcity)

# Save results
saveRDS(mmt_list, f_mmt)


# ---- 3. Historical AF per district -------------------------------------------
af_list <- list()

# Calculate AF
for (dist_id in district_ids) {

  # Extract temp data for selected district
  dist_temp <- temp_dist_list[[dist_id]]

  # Define argvar, centering and coef-vcov
  argvar <- list(fun = varfun,
                 knots = quantile(dist_temp$mean_value, varper / 100, na.rm = T),
                 Bound = range(dist_temp$mean_value, na.rm = T))

  cen <- mintempcity[[dist_id]]
  p025 <- quantile(dist_temp$mean_value, 0.025, na.rm = TRUE)
  p975 <- quantile(dist_temp$mean_value, 0.975, na.rm = TRUE)

  # EXTRACT PARAMETERS
  coef <- res_blup[[dist_id]]$blup
  vcov <- res_blup[[dist_id]]$vcov

  # Derive the centered basis
  bvar <- do.call(onebasis, c(list(x = dist_temp$mean_value), argvar))
  cenvec <- do.call(onebasis, c(list(x = cen), argvar))
  bvarcen <- scale(bvar, center = cenvec, scale = F)

  af_dist <- (1 - exp(-bvarcen %*% coef))
  dist_temp_df <- cbind(dist_temp, af_dist)
  dist_temp_df$ind_heat_total <- dist_temp_df$mean_value > cen

  af_list[[dist_id]] <- dist_temp_df
  rm(dist_temp_df)

}

# ---- 4. District baseline AF percentiles -------------------------------------
# Restricted to heat days (above MMT), peak summer (Jun–Aug), recent years (2015+).
baseline_df <- bind_rows(lapply(district_ids, function(dist_id) {
  af_list[[dist_id]] %>%
    filter(ind_heat_total,
           month(time) %in% 6:8,
           year(time) >= 2015) %>%
    summarise(
      mean   = mean(af_dist,   na.rm = TRUE),
      median = median(af_dist, na.rm = TRUE),
      p75    = quantile(af_dist, 0.75,  na.rm = TRUE),
      p90    = quantile(af_dist, 0.90,  na.rm = TRUE),
      p95    = quantile(af_dist, 0.95,  na.rm = TRUE),
      p975   = quantile(af_dist, 0.975, na.rm = TRUE),
      p99    = quantile(af_dist, 0.99,  na.rm = TRUE)
    ) %>%
    mutate(dist_num = dist_id, .before = 1)
}))

# Save results
write.csv(baseline_df, f_baseline, row.names = FALSE)





# ──────────────────────────────────────────────────────────────────────────────
# calculate_warning_level.R — forecast AF and assign heat-warning levels
# Annual Team Project 2026
#
# RUN AFTER get_MMT_baselineAF.R For each district and forecast day it computes the
# heat-attributable fraction (AF) from forecast temperatures, then classifies
# each district-day into a warning level (0–3).
#
# Inputs : forcast_temp_popw_district.csv
#          historical_temp_popw_mvngpop_2000_2024_district.csv  (defines the basis)
#          secondstage_blup.rds
#          mmt.rds                (from get_MMT_baselineAF.R)
#          baseline_summer.csv    (from get_MMT_baselineAF.R; baseline mode only)
# Output : warning_level.csv
# ──────────────────────────────────────────────────────────────────────────────

# ---- 1. Warning-level configuration ------------------------------------------
#   "fixed"    : the same AF cut-points for every district (fixed_cuts below).
#   "baseline" : district-specific percentiles from baseline_summer.csv
#                (columns dist_num, p75, p90, p95), produced by stage2_BLUP.R.
threshold_method <- "fixed"
fixed_cuts <- c(level1 = 0.075, level2 = 0.10, level3 = 0.15)


# ---- 2. Inputs ---------------------------------------------------------------
# Forecast temperatures (one row per district-day).
forecast_temp <- read.csv(f_forecast_temp) %>%
  select(-any_of("X")) %>%
  filter(BEZNR != exclude_districts)
forecast_temp_list <- split(forecast_temp, forecast_temp$BEZNR)

# Historical summer temperature — defines the spline support (knots/boundary)
# per district, so the basis matches the one used to fit the model.
temp_dist_sum <- read.csv(f_hist_temp) %>%
  select(-any_of("X")) %>%
  filter(month(time) %in% 5:9) %>%
  filter(BEZNR != exclude_districts)
temp_dist_list <- split(temp_dist_sum, temp_dist_sum$BEZNR)

# MMT per district, BLUP coefficients, and (optionally) baseline percentiles.
mmt_list <- readRDS(f_mmt)
res_blup <- readRDS(f_blup)
names(res_blup) <- names(forecast_temp_list)

baseline_summer <- if (file.exists(f_baseline)) read.csv(f_baseline) else NULL

# ---- 3. Forecast AF per district-day -----------------------------------------
af_fcst_list <- list()

# Calculate AF
for (k in seq(length(res_blup))) {

  dist_num <- names(res_blup)[k]

  # Extract temp data for selected district
  dist_temp <- temp_dist_list[[dist_num]]

  # Define argvar, centering and coef-vcov
  argvar <- list(fun = varfun,
                 knots = quantile(dist_temp$mean_value, varper / 100, na.rm = T),
                 Bound = range(dist_temp$mean_value, na.rm = T))

  cen <- mmt_list$mintempcity[k]

  # EXTRACT PARAMETERS
  coef <- res_blup[[k]]$blup
  vcov <- res_blup[[k]]$vcov

  # Derive the centered basis
  bvar <- do.call(onebasis, c(list(x = forecast_temp_list[[dist_num]]$Temperature_pop), argvar))
  cenvec <- do.call(onebasis, c(list(x = cen), argvar))
  bvarcen <- scale(bvar, center = cenvec, scale = F)


  af_dist_forecast <- (1 - exp(-bvarcen %*% coef))
  af_dsit_fcst_df <- cbind(forecast_temp_list[[dist_num]], af_dist_forecast)
  af_dsit_fcst_df$ind_heat_total <- af_dsit_fcst_df$Temperature_pop > cen

  af_fcst_list[[dist_num]] <- af_dsit_fcst_df
  rm(af_dsit_fcst_df)

}

names(af_fcst_list) <- names(res_blup)


# ---- 4. Assign warning level -------------------------------------------------
assign_warning <- function(df, dist_id) {
  if (threshold_method == "baseline") {
    if (is.null(baseline_summer)) {
      stop("baseline_summer.csv not found — run stage2_BLUP.R or use threshold_method = 'fixed'.")
    }
    b  <- baseline_summer[as.character(baseline_summer$dist_num) == dist_id, ]
    c1 <- b$p75; c2 <- b$p90; c3 <- b$p95
  } else {
    c1 <- fixed_cuts[["level1"]]
    c2 <- fixed_cuts[["level2"]]
    c3 <- fixed_cuts[["level3"]]
  }

  # case_when evaluates top to bottom, so each line implies "and >= the previous
  # cut". NA AF values stay NA (there is no catch-all TRUE branch).
  df %>% mutate(warning_level = case_when(
    af_dist_forecast <  c1 ~ "0",
    af_dist_forecast <  c2 ~ "1",
    af_dist_forecast <  c3 ~ "2",
    af_dist_forecast >= c3 ~ "3"
  ))
}

# ---- 5. Combine & export -----------------------------------------------------
dist_fcst_warning <- Map(assign_warning, af_fcst_list, names(af_fcst_list)) %>%
  bind_rows() %>%
  select(BEZNAME, BEZNR, time, warning_level)

# row.names = FALSE avoids writing an extra index column (the "X" we drop on read).
write.csv(dist_fcst_warning, f_warning, row.names = FALSE)
