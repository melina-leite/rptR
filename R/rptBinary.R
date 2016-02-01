#' GLMM-based Repeatability Using REML
#' 
#' Calculates repeatability from a general linear mixed-effects models fitted by REML (restricted maximum likelihood).
#' 
#' @param formula Formula as used e.g. by \link{glmer}. The grouping factor(s) of
#'        interest needs to be included as a random effect, e.g. '(1|groups)'.
#'        Covariates and additional random effects can be included to estimate adjusted repeatabilities.
#' @param grname A character string or vector of character strings giving the
#'        name(s) of the grouping factor(s), for which the repeatability should
#'        be estimated. Spelling needs to match the random effect names as given in \code{formula}.
#' @param data A dataframe that contains the variables included in the \code{formula}
#'        and \code{grname} arguments.
#' @param link Link function. \code{log} and \code{sqrt} are allowed, defaults to \code{log}.
#' @param CI Width of the confidence interval (defaults to 0.95).
#' @param nboot Number of parametric bootstraps for interval estimation.
#'        Defaults to 1000. Larger numbers of permutations give a better
#'        asymtotic CI, but may be very time-consuming.
#' @param npermut Number of permutations used when calculating 
#'        asymptotic \emph{P} values (defaults to 1000). 
#' @param parallel If TRUE, bootstraps will be distributed. 
#' @param ncores Specify number of cores to use for parallelization. On default,
#'        all cores but one are used.
#' 
#' @return 
#' Returns an object of class rpt that is a a list with the following elements: 
#' \item{call}{function call}
#' \item{datatype}{Response distribution (here: 'Binomial').}
#' \item{method}{Method used to calculate repeatability (here: 'REML').}
#' \item{CI}{Width of the confidence interval.}
#' \item{R}{Point estimates for repeatabilities on the link and original scale.}
#' \item{se}{Approximate standard errors (\emph{se}) for repeatabilitieson the link and original scale.
#'            Note that the distribution might not be symmetrical, in which case the \emph{se} is less informative.}
#' \item{CI_emp}{Confidence intervals for repeatabilities on the link and original scale.}
#' \item{P}{Approximate \emph{P} data frame with p-values from a significance test based on likelihood-ratio
#' and significance test based on permutation of residuals for both the original and link scale.}
#' \item{R_boot_link}{Parametric bootstrap samples for \emph{R} on the link scale.}
#' \item{R_boot_org}{Parametric bootstrap samples for \emph{R} on the original scale.}
#' \item{R_permut_link}{Permutation samples for \emph{R} on the link scale.}
#' \item{R_permut_org}{Permutation samples for \emph{R} on the original scale.}
#' \item{LRT}{List of Likelihood-ratios for the model(s) and the reduced model(s), 
#' and \emph{P} value(s) and degrees of freedom for the Likelihood-ratio test} 
#' \item{ngroups}{Number of groups.}
#' \item{nobs}{Number of observations.}
#' \item{overdisp}{Overdispersion parameter. Equals the variance in the observational factor random effect}
#' \item{mod}{Fitted model.}
#'
#' @references 
#' Carrasco, J. L. and Jover, L.  (2003). \emph{Estimating the generalized 
#' concordance correlation coefficient through variance components}. Biometrics 59: 849-858.
#'
#' Faraway, J. J. (2006). \emph{Extending the linear model with R}. Boca Raton, FL, Chapman & Hall/CRC.
#' 
#' Nakagawa, S. and Schielzeth, H. (2010) \emph{Repeatability for Gaussian and 
#' non-Gaussian data: a practical guide for biologists}. Biological Reviews 85: 935-956
#' 
#' @author Holger Schielzeth  (holger.schielzeth@@ebc.uu.se),
#'         Shinichi Nakagawa (shinichi.nakagawa@@otago.ac.nz) &
#'         Martin Stoffel (martin.adam.stoffel@@gmail.com)
#'      
#' @seealso \link{rpt}
#' 
#' @examples  
#' # repeatability estimations for egg dumping (binary data)
#' data(BroodParasitism)
#' (rpt.BroodPar <- rptBinary(formula = cbpYN ~ (1|FemaleID), grname = c("FemaleID"), data = BroodParasitism))
#' 
#' 
#' 
#' 
#' nind = 80
#' nrep = 30 # a bit higher
#' latmu = 0
#' latbv = 0.3
#' latgv = 0.1
#' latrv = 0.2
#' indid = factor(rep(1:nind, each=nrep))
#' groid = factor(rep(1:nrep, nind))
#' obsid = factor(rep(1:I(nind*nrep)))
#' latim = rep(rnorm(nind, 0, sqrt(latbv)), each=nrep)
#' latgm = rep(rnorm(nrep, 0, sqrt(latgv)), nind)
#' latvals = latmu + latim + latgm + rnorm(nind*nrep, 0, sqrt(latrv))
#' expvals = VGAM::logit(latvals, inverse = TRUE)
#' obsvals = rbinom(nind*nrep, 1, expvals)
#' beta0 = latmu
#' beta0 = VGAM::logit(mean(obsvals))
#' md = data.frame(obsvals, indid, obsid, groid)
#'
#' R_est <- rptBinary(formula = obsvals ~ (1|indid) + (1|groid), grname = c("indid", "groid"), 
#'                     data = md, nboot = 3, link = "logit", npermut = 3, parallel = FALSE)
#' R_est2 <- rptBinary(formula = obsvals ~ (1|indid), grname = "indid", 
#'                     data = md, nboot = 10, link = "logit", npermut = 10, parallel = FALSE)
#'                     
#' @export
#' 

rptBinary <- function(formula, grname, data, link = c("logit", "probit"), CI = 0.95, nboot = 1000, 
        npermut = 1000, parallel = FALSE, ncores = NULL) {
        
        # to do: missing values
        # no bootstrapping case
        
        # link
        if (length(link) > 1) link <- link[1]
        if (!(link %in% c("logit", "probit"))) stop("Link function has to be 'logit' or 'probit'")
        # observational level random effect
        obsid <- factor(1:nrow(data))
        
        formula <- update(formula,  ~ . + (1|obsid))
        mod <- lme4::glmer(formula, data = data, family = binomial(link = link))
        VarComps <- lme4::VarCorr(mod)
        obsind_id <- which(as.data.frame(VarComps)[["grp"]] == "obsid")
        overdisp <- as.numeric(lme4::VarCorr(mod)$obsid)^2
        
#         if((as.data.frame(VarComps)[obsind_id, "sdcor"] == 0)) {
#                 formula <- update(formula, eval(paste(". ~ . ", "- (1 | obsid)")))
#                 mod <-  lme4::glmer(formula, data = data, family = binomial(link = link))
#                 VarComps <- lme4::VarCorr(mod)
#                 overdisp <- 0
#         }
   
        if (nboot < 0) nboot <- 0
        if (npermut < 1) npermut <- 1
        e1 <- environment()
        # point estimates of R
        R_pe <- function(formula, data, grname, peYN = FALSE) {
                
                mod <- lme4::glmer(formula = formula, data = data, family = binomial(link = link))
                
                VarComps <- lme4::VarCorr(mod)
                # find groups
                row_group <- which(as.data.frame(VarComps)[["grp"]] %in% grname)
                # 
                var_a <- as.data.frame(VarComps)[["vcov"]][row_group]
                names(var_a) <- as.data.frame(VarComps)[["grp"]][row_group]
                
                var_e = as.numeric(VarComps$obsid)^2
                # if(length(var_e) == 0) var_e <- 0
                # intercept on link scale
                beta0 <- unname(lme4::fixef(mod)[1])
                
                # varComps shouldn�t contain obsind here
                VarCompsDf <- as.data.frame(VarComps)
                VarCompsGr <- VarCompsDf[which(VarCompsDf[["grp"]] %in% grname), ]
                
                if (peYN & any(VarCompsGr$vcov == 0)) {
                        if (nboot > 0){
                                assign("nboot", 0, envir = e1)
                                warning("(One of) the point estimate(s) for the repeatability was exactly 
                                        zero; parametric bootstrapping has been skipped.")
                        }
                }
                
                if (link == "logit") {
                        R_link <- var_a/(var_a + var_e + (pi^2)/3)
                        P <- exp(beta0) / (1 + exp(beta0))
                        R_org <- ( (var_a * P^2) / ((1 + exp(beta0))^2)) / (((var_a + var_e) * P^2) / ((1 + exp(beta0))^2) + (P * (1-P)))
                }
                
                if (link == "probit") {
                        R_link <- var_a/(var_a + var_e + 1)
                        R_org <- NA
                
                }
                # check whether that works for any number of var
                R <- as.data.frame(rbind(R_org, R_link))
                return(R)
        }
        
        R <- R_pe(formula, data, grname, peYN = TRUE)
        
        # confidence interval estimation by parametric bootstrapping
        if (nboot > 0)  Ysim <- as.matrix(stats::simulate(mod, nsim = nboot))
        
        bootstr <- function(y, mod, formula, data, grname) {
                data[, names(model.frame(mod))[1]] <- as.vector(y)
                R_pe(formula, data, grname)
        }
        
        # to do: preallocate R_boot
        if (nboot > 0 & parallel == TRUE) {
                if (is.null(ncores)) {
                        ncores <- parallel::detectCores() - 1
                        warning("No core number specified: detectCores() is used to detect the number of \n cores on the local machine")
                }
                # start cluster
                cl <- parallel::makeCluster(ncores)
                parallel::clusterExport(cl, "R_pe")
                R_boot <- unname(parallel::parApply(cl, Ysim, 2, bootstr, mod = mod, formula = formula, 
                        data = data, grname = grname))
                parallel::stopCluster(cl)
        }
        if (nboot > 0 & parallel == FALSE) {
                R_boot <- unname(apply(Ysim, 2, bootstr, mod = mod, formula = formula, data = data, 
                        grname = grname))
        }
        if (nboot == 0) {
                # R_boot <- matrix(rep(NA, length(grname)), nrow = length(grname))
                R_boot <- NA
        }
        
        # transform bootstrapping repeatabilities into vectors
        boot_org <- list()
        boot_link <- list()
        if (length(R_boot) == 1) {
                if (is.na(R_boot)) {
                for(i in c("CI_org", "CI_link", "se_org", "se_link")) assign(i, NA)
                }
        } else {
        for (i in 1:length(grname)) {
                boot_org[[i]] <- unlist(lapply(R_boot, function(x) x["R_org", grname[i]]))
                boot_link[[i]] <- unlist(lapply(R_boot, function(x) x["R_link", grname[i]]))
        }
        names(boot_org) <- grname
        names(boot_link) <- grname
        
        calc_CI <- function(x) {
                out <- quantile(x, c((1 - CI)/2, 1 - (1 - CI)/2), na.rm = TRUE)
        }
        
        # CI into data.frame and transpose to have grname in rows
        CI_org <- as.data.frame(t(as.data.frame(lapply(boot_org, calc_CI))))
        CI_link <- as.data.frame(t(as.data.frame(lapply(boot_link, calc_CI))))
        
        # se
        se_org <- as.data.frame(t(as.data.frame(lapply(boot_org, sd))))
        se_link <- as.data.frame(t(as.data.frame(lapply(boot_link, sd))))
        names(se_org) <- "se_org"
        names(se_link) <- "se_link"
        }
        
        # significance test by permutation of residuals
        P_permut <- rep(NA, length(grname))
        
        # significance test by likelihood-ratio-test
        terms <- attr(terms(formula), "term.labels")
        randterms <- terms[which(regexpr(" | ", terms, perl = TRUE) > 0)]
        
        # no permutation test
        if (npermut == 1) {
                R_permut <- R
                P_permut <- NA
        }
        
        # significance test by permutation of residuals
        # nperm argument just used for parallisation
        
        if (link == "logit") trans_fun <- VGAM::logit
        if (link == "probit") trans_fun <- VGAM::probit
        
        permut <- function(nperm, formula, mod, dep_var, grname, data) {
                # for binom it will be logit 
                y_perm <- rbinom(nrow(data), 1, prob = VGAM::logit((trans_fun(fitted(mod)) + sample(resid(mod))), inverse = TRUE))
                # y_perm <- rbinom(nrow(data), 1, prob = (predict(mod, type = "response") + sample(resid(mod))))
                data_perm <- data
                data_perm[dep_var] <- y_perm
                out <- R_pe(formula, data_perm, grname)
                out
        }
        # response variable
        dep_var <- as.character(formula)[2]
        
        # R_permut <- matrix(rep(NA, length(grname) * npermut), nrow = length(grname))
        P_permut <- data.frame(matrix(NA, nrow = 2, ncol = length(grname)),
                row.names = c("P_permut_org", "P_permut_link")) 
        
        if(parallel == TRUE) {
                if (is.null(ncores)) {
                        ncores <- parallel::detectCores()
                        warning("No core number specified: detectCores() is used to detect the number of \n cores on the local machine")
                }
                # start cluster
                cl <- parallel::makeCluster(ncores)
                parallel::clusterExport(cl, "R_pe")
                R_permut <- parallel::parLapply(cl, 1:(npermut-1), permut, formula=formula, 
                        mod=mod, dep_var=dep_var, grname=grname, data = data)
                parallel::stopCluster(cl)
                
        } else if (parallel == FALSE) {
                R_permut <- lapply(1:(npermut - 1), permut, formula, mod, dep_var, grname, data)
                
        }
        
        # adding empirical rpt 
        R_permut <- c(list(R), R_permut)
        
        # equal to boot
        permut_org <- list()
        permut_link <- list()
        for (i in 1:length(grname)) {
                permut_org[[i]] <- unlist(lapply(R_permut, function(x) x["R_org", grname[i]]))
                permut_link[[i]] <- unlist(lapply(R_permut, function(x) x["R_link", grname[i]]))
        }
        names(permut_org) <- grname
        names(permut_link) <- grname
        
        
        #         # reshaping and calculating P_permut
        #         R_permut_org <- lapply(R_permut, function(x) x["R_org",])
        #         R_permut_link <- lapply(R_permut, function(x) x["R_link",])
        #         R_permut_org <- do.call(rbind, R_permut_org)
        #         R_permut_link <- do.call(rbind, R_permut_link)
        
        P_permut["P_permut_org", ] <- unlist(lapply(permut_org, function(x) sum(x >= x[1])))/npermut
        P_permut["P_permut_link", ] <- unlist(lapply(permut_link, function(x) sum(x >= x[1])))/npermut
        names(P_permut) <- names(permut_link)
        
        
        ## likelihood-ratio-test
        LRT_mod <- as.numeric(logLik(mod))
        LRT_df <- 1
        #         if (length(randterms) == 1) {
        #                 formula_red <- update(formula, eval(paste(". ~ . ", paste("- (", randterms, ")"))))
        #                 LRT.red <- as.numeric(logLik(lm(formula_red, data = data)))
        #                 LRT.D <- as.numeric(-2 * (LRT.red - LRT.mod))
        #                 LRT.P <- ifelse(LRT.D <= 0, LRT.df, pchisq(LRT.D, 1, lower.tail = FALSE)/2)
        #                 # LR <- as.numeric(-2*(logLik(lm(update(formula, eval(paste('. ~ . ', paste('- (',
        #                 # randterms, ')') ))), data=data))-logLik(mod))) P.LRT <- ifelse(LR<=0, 1,
        #                 # pchisq(LR,1,lower.tail=FALSE)/2)
        #         }
        
        
        for (i in c("LRT_P", "LRT_D", "LRT_red")) assign(i, rep(NA, length(grname)))
        
        for (i in 1:length(grname)) {
                formula_red <- update(formula, eval(paste(". ~ . ", paste("- (1 | ", grname[i], 
                        ")"))))
                LRT_red[i] <- as.numeric(logLik(lme4::glmer(formula = formula_red, data = data, 
                        family = binomial(link = link))))
                LRT_D[i] <- as.numeric(-2 * (LRT_red[i] - LRT_mod))
                LRT_P[i] <- ifelse(LRT_D[i] <= 0, 1, pchisq(LRT_D[i], 1, lower.tail = FALSE)/2)
                # LR <- as.numeric(-2*(logLik(lme4::lmer(update(formula, eval(paste('. ~ . ',
                # paste('- (1 | ', grname[i], ')') ))), data=data))-logLik(mod))) P.LRT[i] <-
                # ifelse(LR<=0, 1, pchisq(LR,1,lower.tail=FALSE)/2)
        }
        
        P <- cbind(LRT_P, t(P_permut))
        
        #Function to calculate a point estimate of overdispersion from a mixed model object
        # from Harrison (2014): Using observation-level random effects to
        # model overdispersion in count data in ecology and evolution, PeerJ
        #     od.point<-function(modelobject){
        #             x<-sum(resid(modelobject,type="pearson")^2)
        #             rdf<-summary(modelobject)$AICtab[5]
        #             return(x/rdf)
        #     }
        
        res <- list(call = match.call(), 
                datatype = "Binary", 
                link = link,
                CI = CI, 
                R = R, 
                se = cbind(se_org,se_link), 
                CI_emp = list(CI_org = CI_org, CI_link = CI_link), 
                P = P,
                R_boot_link = boot_link, 
                R_boot_org = boot_org,
                R_permut_link = permut_link, 
                R_permut_org = permut_org,
                LRT = list(LRT_mod = LRT_mod, LRT_red = LRT_red, LRT_D = LRT_D, LRT_df = LRT_df, 
                        LRT_P = LRT_P), 
                ngroups = unlist(lapply(data[grname], function(x) length(unique(x)))), 
                nobs = nrow(data), overdisp = overdisp, mod = mod)
        class(res) <- "rpt"
        return(res)
} 