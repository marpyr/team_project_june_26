
################################################################################
# Create plot of blups predictions
################################################################################

#Load packages, function and other specifications
source('scripts/00.pkg.R')

#Load summer temperature, second stage model object and blups
load("output/stage2_datapred.Rdata")

#Define meta predictors (ONLY FOR SUMMER MONTHS)
metapred <- tempsum[, .(avgtmean = mean(tmean, na.rm = TRUE),
                        rangetmean  = max(tmean, na.rm = TRUE) - min(tmean, na.rm = TRUE)),
                    by = .(distcode, canton)]

#Define quantiles of temperature distribution per district
predperc <- c(seq(0,1,0.1),2:98,seq(99,100,0.1))
quantmean <- tempsum[, .(perc = predperc, 
                       qt   = quantile(tmean, probs = predperc / 100)), 
                       by = .(distcode)] |> dcast(perc ~ distcode, value.var = "qt")
quantmean <- quantmean[,-1]
qtmean <- rowMeans(quantmean)

#Create basis values
bvar <- onebasis(qtmean, fun="ns", knots=qtmean[predperc %in% c(50,90)])

#Define overall (summer) average and range of temperature and create predictions
predfit <- predict(metamod, 
                   newdata=data.frame(avgtmean=mean(metapred$avgtmean), 
                                      rangetmean=mean(metapred$rangetmean)), 
                   vcov=T)

#Define total pooled effect
predpool <- crosspred(bvar, coef=predfit$fit, vcov=predfit$vcov,
                      model.link="log", at=qtmean, cen=15)


#################################
#PLOTS
#################################

#Plot pooled effect
pdf("output/stage2_pool.pdf",width=13,height=9)
plot(predpool)
dev.off()

#Plot the blups predictions
pdf("output/stage2_blup.pdf",width=9,height=13)
layout(matrix(seq(5*3),nrow=5,byrow=T))
par(mar=c(4,3.8,3,2.4),mgp=c(2.5,1,0),las=1)

#Loop over districts to create blups plots
i<-1
for(i in 1:nrow(metapred)) {
  
  #Define temperature distribution
  predvar <- quantmean[[i]]
  
  #Redefine bases
  argvar <- list(x=predvar,fun="ns",
                 knots=quantmean[predperc %in% c(50,90),i, with = FALSE][[1]],
                 Bound=quantmean[c(1,length(predperc)),i, with = FALSE][[1]])
  bvar <- do.call(dlnm::onebasis,argvar)
  
  ### Erc plots
  minpercdist <- (50:90)[which.min((bvar %*% blups[[i]]$blup)[50:90])]
  mintmeandist <- quantmean[predperc == minpercdist, i, with = FALSE]
  predblup <- crosspred(bvar,coef=blups[[i]]$blup,vcov=blups[[i]]$vcov,
                        model.link="log",by=0.1,cen = mintmeandist)
  
  plot(predblup,ylim=c(0,2.5),lab=c(6,5,7),xlab="Mean Temperature",
       ylab="Relative Risk", main = metapred$distcode[i], col="red",
       ci.arg=list(col=alpha("red",0.1)),lwd=1.5)
  
}
dev.off()
