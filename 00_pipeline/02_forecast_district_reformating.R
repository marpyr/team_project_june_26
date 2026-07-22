# In this script we load the downloaded temperature forecasts, and
# calculate populationweighted daily mean temperatures for each day of the forecast


# packages
library(sf); library(terra); library(dplyr); library(tidyr); library(exactextractr); library(lubridate)


## File paths
#----

ref_date <- as.Date(today())
date_forecast = seq(ref_date,ref_date+4,by=1)

# output directory
output_district_csv = "00_pipeline_data/forecast_clean_district.csv"

# forecast temperature
forecast_temp = rast("00_pipeline_data/forecast_raw_icon_ch2_2kmRegCons_daily_00utc_data.nc")
raster_dat = forecast_temp-273.15

# shapefiles of regions
districts=read_sf("00_pipeline_data/district_shapefile/")

# population densities
pop_rast_list = readRDS("00_pipeline_data/population.RDS")
pop_rast=pop_rast_list[[length(pop_rast_list)]]
pop_rast=project(pop_rast,forecast_temp)

#----


# Computation helpers
#----

# long_format_helper
long_format = function(average_dat,date_forecast,districts,name_var="mean_value"){
  colnames(average_dat)=date_forecast
  average_dat$BEZNAME = districts$BEZNAME
  average_dat$BEZNR = districts$BEZNR
  colnames(average_dat)
  new_long_format_table = average_dat %>% pivot_longer(
    cols = -c(BEZNAME,BEZNR),
    names_to = "time",
    values_to = name_var
  )
  return(new_long_format_table)
}

# district extraction
district_extract = function(raster_dat,districts,pop_rast,date_forecast){
  pop_rast_comput <- project(pop_rast, raster_dat)

  average_dat_raw = exact_extract(raster_dat,districts,fun = "mean",coverage_area=T)
  average_dat = exact_extract(raster_dat,districts, fun = "weighted_mean",weights=pop_rast_comput,coverage_area=T)

  long_format_table = long_format(average_dat_raw,date_forecast,districts,name_var = "Temperature_raw")
  long_format_table_pop = long_format(average_dat,date_forecast,districts,name_var = "Temperature_pop")

  long_format_table2 = left_join(long_format_table,long_format_table_pop)
  return(long_format_table2)
}

#----


# File creation and saving
#----

forecast_long_dat <- district_extract(raster_dat,districts,pop_rast,date_forecast)

write.csv(forecast_long_dat,output_district_csv)

#----
