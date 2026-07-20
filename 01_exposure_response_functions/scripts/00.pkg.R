###################################################################################
# Load packages
###################################################################################

library(data.table) # HANDLE LARGE DATASETS
library(dlnm) ; library(gnm) ; library(splines) # MODELLING TOOLS
library(dplyr) ; library(tidyr) # DATA MANAGEMENT TOOLS
library(ggplot2) ; library(patchwork) # PLOTTING TOOLS

###################################################################################
# Load functions
###################################################################################

# Load min mortality function from Tobias,... 
source('scripts/functions/findmin.R')

###################################################################################
# Other specifications
###################################################################################

#Specification for the lag function in crossbasis.
#How many lags are we considering for temperature?
lag <- 3


