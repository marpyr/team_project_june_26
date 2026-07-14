library(sf)
library(terra)
library(dplyr)
library(tidyr)
library(exactextractr)
library(lubridate)

# this scripts loads a forecast

################### SETUP

### ADAPT PATH IF NEEDED
dir_forecast_path = "//ispm.unibe.ch/fs/_ISPM/CCH/AnnualTeamProject2026/Forecast_team_data/Daily_MCH_forecasts/"

district_path = "//ispm.unibe.ch/fs/_ISPM/CCH/AnnualTeamProject2026/Boundaries_G1_District_20260101/Boundaries_G1_District_20260101.shp"

population_path = "//ispm.unibe.ch/fs/_ISPM/CCH/AnnualTeamProject2026/population_grid/population.RDS"

output_directory_template = "//ispm.unibe.ch/fs/_ISPM/CCH/AnnualTeamProject2026/Forecast_team_data/R_pipeline/District_forecast_"

### Overwriting or not the output directory

overwrite = T

### load forecast

ref_date = as.Date(today())

forecast_temp_file = paste0(dir_path,"icon_ch2_2kmRegCons_daily_00utc_",format(ref_date, "%Y%m%d"),".nc")

forecast_temp = rast(forecast_temp_file)

raster_dat = forecast_temp-273.15

date_forecast = seq(ref_date,ref_date+4,by=1)

### load districts

districts=read_sf(district_path)

### load population (last population dataset of structured list)
pop_rast_list = readRDS(population_path)
pop_rast=pop_rast_list[[length(pop_rast_list)]]
pop_rast=project(pop_rast,forecast_temp)

### output definition

output_dir = paste0(output_directory_template,format(ref_date,"%Y%m%d"))
if(dir.exists(output_dir)){
  if(overwrite) {file.remove(list.files(output_dir,full.names = T));print("Output directory was overwritten")}
  else stop("Output directory already exists and overwrite = FALSE.")
}else dir.create(output_dir)

output_district_csv = paste0(output_dir,'/outputfile_forecast_muni_',format(ref_date,"%Y%m%d"),'.csv')

################ Computation helpers

#long_format_helper
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

#district extraction
district_extract = function(raster_dat,districts,pop_rast,date_forecast){
  pop_rast_comput <- project(pop_rast, raster_dat)

  average_dat_raw = exact_extract(raster_dat,districts,fun = "mean",coverage_area=T)
  average_dat = exact_extract(raster_dat,districts, fun = "weighted_mean",weights=pop_rast_comput,coverage_area=T)

  long_format_table = long_format(average_dat_raw,date_forecast,districts,name_var = "Temperature_raw")
  long_format_table_pop = long_format(average_dat,date_forecast,districts,name_var = "Temperature_pop")

  long_format_table2 = left_join(long_format_table,long_format_table_pop)
  return(long_format_table2)
}

################ File creation and saving

forecast_long_dat=district_extract(raster_dat,districts,pop_rast,date_forecast)

write.csv(forecast_long_dat,output_district_csv)

