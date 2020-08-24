# drop empty species and sites
dropEmpty <- function(live, dead) {
	# drop empty species
	temp1 <- colSums(live)
	temp2 <- colSums(dead)
	live <- live[, temp1 > 0 | temp2 > 0]
	dead <- dead[, temp1 > 0 | temp2 > 0]
	
	# drop empty sites
	temp1 <- rowSums(live)
	temp2 <- rowSums(dead)
	live <- live[temp1 > 0 | temp2 > 0, ]
	dead <- dead[temp1 > 0 | temp2 > 0, ]
	
	return(list('live'=live, 'dead'=dead))
}

# Parse Data -- live dead	
parseDataLiveDead <- function(x, taxon, env, species, environments) {
	if(env == "subtidal eel grass") {
		myEnv <- "sub_eelgrass"
	} else if(env == "intertidal sand flat") {
		myEnv <- "inter_barren"
	}
	
	# select taxa
	if(taxon != "all") {
		xReduced <- x[,is.element(colnames(x), species$colName[species$Class == taxon])]
	} else {
		xReduced <- x
	}
	
	# select environment
	if(env != "all") {
		xReduced <- xReduced[environments[2,] == myEnv,]
	}
	
	return(xReduced)
}

simCalc <- function(live, dead) {
	if(is.element(class(live), c("integer","numeric"))) {
		n <- 1
	} else {
		n <- nrow(live)
	}
	sim <- data.frame("bray.curtis2" = rep(NA, n), "bray.curtis" = rep(NA, n), "pctSim" = rep(NA, n),"jaccard" = rep(NA, n),"chao.jaccard" = rep(NA, n))

	for(i in 1:n) {
		if(n == 1) {
			x <- live
			y <- dead
		} else {
			x <- live[i,] 
			y <- dead[i,]
		}
		comm <- rbind(x[x > 0 | y > 0], y[x > 0 | y > 0])
		common <- comm[,comm[1,] > 0 & comm[2,] > 0]
		commonPct <- (comm/rowSums(comm))[,comm[1,] > 0 & comm[2,] > 0]
		
		# bray-curtis
		sim$bray.curtis[i] <- sum(abs(x-y))/sum(comm)
		if(class(common)[1] == "integer") {
			U <- commonPct[1]
			V <- commonPct[2]
			sim$bray.curtis2[i] <- 1 - 2*min(common)/sum(comm)
		} else {
			U <- sum(commonPct[1,])
			V <- sum(commonPct[2,])
			sim$bray.curtis2[i] <- 2*sum(apply(common, 2, min))/sum(comm)
		}
		
		# pct Sim
		sim$pctSim[i] <- 2*sum(apply(comm, 2, min)) / (sum(comm[1,]) + sum(comm[2,]))
		nCommon <- ncol(data.frame(comm[,comm[1,] > 0 & comm[2,] > 0])) # common
		nTotal <- ncol(comm) # all present
		
		#jaccard
		sim$jaccard[i] <- nCommon / nTotal
		
		# Chao–Jaccard for two assemblages = UV/(U + V − UV)
		sim$chao.jaccard[i] <- U*V / (U+V-U*V)
	}
	return(sim)
}

# Parse Data--time averaging
parseDataTimeAvg <- function(x, region) {	
	if(region == "all") {
		ages <- x
	} else if(region == "all but San Diego") {
		ages <- subset(x, Region != "San Diego")
	} else {
		ages <- subset(x, Region == region)
	}
	return(ages)
}

topLabel <- function(region) {	
	if(region == "all") {
		topLabel <- "Viewing specimens from all regions."
	} else if(region == "all but San Diego") {
		topLabel <- "Viewing specimens from all regions, except San Diego."
	} else {
		topLabel <- paste0("Viewing specimens from the ", region, " region.")
	}
	return(topLabel)
}

taModel <- function(nT, pDest, pImmig, pDeath) {
	#nT <- 100
	#pDest <- 0.02
	#pImmig <- 0.25
	#pDeath <- 0.1
	
	species <- read.delim(file="warmeSpecies.tsv")
	species <- subset(species, Phylum == 'Mollusca') # include only mollusca
	
	deadIn <- read.delim(file="warmeDead.tsv")
	# drop non-molluscan taxa and those not identified to species
	deadIn[,species$Class == 'Bivalvia'] <- floor(deadIn[,species$Class == 'Bivalvia']/2)
	deadIn <- deadIn[,is.element(colnames(deadIn), species$colName) & !grepl("_sp", colnames(deadIn))]
	
	metaComm <- rep(names(colSums(deadIn)), colSums(deadIn))

	liveCom <- table(factor(sample(metaComm, 200, replace=TRUE), levels=unique(metaComm)))
	deadCom <- table(factor(sample(metaComm, 2000, replace=TRUE), levels=unique(metaComm)))
	initAssemb <- rbind(liveCom, deadCom)

	initLive <- rep(names(liveCom), liveCom)
	initDead <- rep(names(deadCom), deadCom)
	
	# initial conditions	
	initSim <- simCalc(initAssemb[1,initAssemb[1,]>0 | initAssemb[2,]>0], initAssemb[2,initAssemb[1,]>0 | initAssemb[2,]>0])
	
	initStats <- data.frame("deadS_liveS"=length(unique(sample(initDead,100)))/length(unique(sample(initLive,100))),"jaccard"=initSim$jaccard,"chao.jaccard"=initSim$chao.jaccard,"bray.curtis"=initSim$bray.curtis)
	
	liveCom <- rep(names(liveCom), liveCom)
	deadCom <- rep(names(deadCom), deadCom)
	
	livingAssemb <- sample(liveCom, length(liveCom))
	deathAssemb <- sample(deadCom, length(deadCom))
	
	output <- data.frame(matrix(NA, nrow=nT, ncol=4, dimnames=(list(1:nT, c("deadS_liveS","jaccard","chao.jaccard","bray.curtis")))))
	
	for(i in 1:nT) {
		# decay death assemblage
		deathCount <- table(deathAssemb)
		pTemp <- runif(length(deathAssemb))
		destroyed <- table(factor(deathAssemb[pTemp < pDest], levels=names(deathCount)))
		deathAssemb <- rep(names(deathCount - destroyed), deathCount - destroyed)
		
		# add new dead individuals to death assemblage
		pTemp <- runif(length(livingAssemb))
		died <- livingAssemb[pTemp < pDeath]
		deathAssemb <- c(deathAssemb, died)
		deathAssemb <- sample(deathAssemb, length(deathAssemb))
		
		#remove dead individuals from living assemblage
		livingCount <- table(livingAssemb)
		diedCount <- table(factor(died, levels=names(livingCount)))
		livingAssemb <- rep(names(livingCount - diedCount), livingCount - diedCount)
		
		# add new births and immigrations
		birth_immig <- runif(length(died))
		born <- sample(livingAssemb, length(birth_immig[birth_immig < 1-pImmig]), replace=TRUE) 
		immigrants <- sample(metaComm, length(died)-length(born))
		if(length(born) > 0) {
			livingAssemb <- c(livingAssemb, born)
		}
		if(length(immigrants) > 0) {
			livingAssemb <- c(livingAssemb, immigrants)
		}
		livingAssemb <- sample(livingAssemb, length(livingAssemb))
		
		# get stats
		finalLive <- as.numeric(table(factor(livingAssemb, levels=unique(metaComm))))
		finalDead <- as.numeric(table(factor(deathAssemb, levels=unique(metaComm))))
			
		simStats <- simCalc(finalLive, finalDead)
		output$deadS_liveS[i] <- length(unique(sample(deathAssemb,100)))/length(unique(sample(livingAssemb,100)))
		output$jaccard[i] <- simStats$jaccard
		output$chao.jaccard[i] <- simStats$chao.jaccard
		output$bray.curtis[i] <- simStats$bray.curtis
	}
	output <- rbind(initStats, output)
	return(output)
}