
################################################################################
# Run statistical models for 1st and 2nd stage of the analysis
################################################################################

#README:
#To run this code you need to be connect to the server.

###################################
#LOAD THINGS
###################################

#Load packages, function and other specifications
source('scripts/00.pkg.R')

#Load municipality-district lookup table
lookup <- fread("/Volumes/FS/_ISPM/CCH/AnnualTeamProject2026/Boundaries_and_shapefiles/Gemeindestand_lookup_districts.csv")

#Load processed mortality data 
death <- readRDS("/Volumes/FS/_ISPM/CCH/AnnualTeamProject2026/01_exposure_response_functions/death6924.RDS")

#Load processed temperature data
temp <- fread( "/Volumes/FS/_ISPM/CCH/AnnualTeamProject2026/Historical_temp_data/historical_temp_popw_muni_2000_2024.csv")

###################################
#PROCESS DATA BEFORE RUNNING ANALYSIS
###################################

#Rename temperature columns
setnames(temp, 
         old = c("time", "GDENR", "mean_value"),
         new = c("date", "muncode", "tmean"))

#Rename lookup columns
setnames(lookup, 
         old = c("Bezirks-nummer", "BFS Gde-nummer","Kanton"),
         new = c("distcode", "muncode","canton"))
lookup <- lookup[Gemeindename != "Moutier"]

#Truncated data for the period 2014-2024 
death <- death[year(date)>=2014]
temp <- temp[year(date)>=2014] 

#Merge death and temperature data
data <- merge(death, temp, by=c("muncode", "date"), all.x=T)
setkey(data, muncode, date)

#Define time columns 
data$year <- year(data$date)
data$month <- month(data$date)
data$doy <- yday(data$date)
data$dow <- wday(data$date)

#Subset data to summer months
data <- subset(data, month%in%6:9)


###################################
#FIRST STAGE 
###################################

#Each element include municipalities within each district
dlist<- split(lookup$muncode, lookup$distcode)

#Initialite results containers
firststage <- list()
cp_list <- list()
coefall <- matrix(NA, nrow=length(dlist), ncol=3)
vcovall <- list()

#i<-1
#Run loop by district
for (i in seq_along(dlist)) {
   
  #Subset data to municipality within specific district
  subdata <- data[muncode %in% dlist[[i]],]
  
  if(nrow(subdata>=1)){
     
    #Define spline arguments and splines (lag was defined in 00.pkg.R)
    argvar <- list(fun="ns", knots=quantile(subdata$tmean, c(50,90)/100, na.rm=T),
                   Boundary.knots=range(subdata$tmean)) 
    arglag <- list(fun="ns", knots=2) 
    spldoy <- onebasis(subdata$doy, "ns", df=3)
    group <- factor(paste(subdata$muncode, subdata$year, sep="-"))
    cbtmean <- crossbasis(subdata$tmean, lag=lag, argvar=argvar, arglag=arglag, group=group)
    
    # DEFINE THE STRATA
    subdata[, stratum:=factor(paste(muncode, year, month, dow, sep=":"))]
    
    # RUN THE MODEL
    # NB: EXCLUDE EMPTY STRATA, OTHERWISE BIAS IN gnm WITH quasipoisson # we can control the seasonal patterns using the approach from Gasparrini et al--> https://github.com/gasparrini/CTS-smallarea
    subdata[,  keep:=sum(dcount)>0, by=stratum]
    modfull <- gnm::gnm(dcount ~ cbtmean, eliminate=stratum, data=subdata, family=quasipoisson, subset=keep)
    mmti <- findmin(cbtmean, model=modfull, 
                    from=quantile(subdata$tmean, 0.25),
                    to=quantile(subdata$tmean, 0.90)) 
    
    #Save results
    cp_list[[i]] <- crossreduce(cbtmean, modfull, cen=mmti)
    coefall[i,] <-  cp_list[[i]]$coefficients
    vcovall[[i]] <-  cp_list[[i]]$vcov
  }
  else{
    cp_list[[i]] <- NA
    coefall[i,] <- NA
    vcovall[[i]] <- NA
  }
}

#Store coefficients and variance-covariance matrices
names(cp_list) <- names(dlist)
rownames(coefall) <- names(dlist)
names(vcovall) <- names(dlist)
stage1 <-list(coefall=coefall, vcovall=vcovall)

#Store first stage plot
pdf(paste0("output/stage1.pdf"))
for(x in 1:length(cp_list)){
  plot(cp_list[[x]], main=paste("First stage",  names(cp_list)[x]))
}
dev.off()

#Save first stage and crossreduce 
saveRDS(cp_list, "output/stage1_crosspred.rds")
saveRDS(stage1, "output/stage1_coef_vcov.rds")


###################################
#SECOND STAGE 
###################################

#Subset temperature to summer months
tempsum <- temp[lubridate::month(date) %in% 6:9,]

# add district numbers to temperature data
tempsum <- merge(tempsum, lookup[,.(canton, muncode, distcode)], 
                 by.x="muncode", by.y="muncode")

#Define meta predictors (ONLY FOR SUMMER MONTHS)
metapred <- tempsum[, .(avgtmean = mean(tmean, na.rm = TRUE),
                        rangetmean  = max(tmean, na.rm = TRUE) - min(tmean, na.rm = TRUE)),
                    by = .(distcode, canton)]

#Run meta-regression
metamod<- mixmeta::mixmeta(stage1$coefall ~ rangetmean + avgtmean, stage1$vcovall, metapred,
                          control=list(showiter=T), random=~1|canton/distcode, method="reml")
#Extract blups
blups <- mixmeta::blup(metamod, vcov=T)

#Save results
saveRDS(blups, 'output/stage2_blup.rds') #To send to other team

#Save data to plot pool predictions and blups
save(tempsum, metamod, blups, file = "output/stage2_datapred.Rdata") 

