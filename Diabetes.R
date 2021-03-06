library(dplyr)
library(survey)
library(ggplot2)
library(plyr)
library(VIM)
library(mice)
library(AppliedPredictiveModeling)
library(caret)
library(subselect)
library(glmnet)
library(pROC)

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

load("Diabetes_data.Rdata")

diabetes<-diabetes %>% filter(a301=="no")
diabetes<-diabetes %>% mutate(diabetes=factor(ifelse(glucosa>=126,1,0),levels=c("1","0"),labels=c("Yes","No")))
diabetes<-diabetes %>% mutate(prediabetes=factor(ifelse(glucosa>=100,1,0),levels=c("1","0"),labels=c("Yes","No")))

diabetes<-diabetes %>% #select(a701a,a701b)
  mutate(diabetes_hist = factor(case_when(is.na(a701a) & is.na(a701b) & a701a==2 & a701b==2 ~ NA_real_,
                                   a701a=="no" & a701b=="no" ~ 0,
                                   a701a=="s\xed" | a701b=="s\xed" ~ 1),levels=c("0","1"),labels=c("No","Yes")),
         social_security=factor(ifelse(afilia2=="ninguna",0,1),levels=c("0","1"),labels=c("No","Yes")),
         smoker = factor(case_when(a1301=="s\xed" ~ 1,
                            a1301=="ns/nr" ~ NA_real_,
                            TRUE ~ 0),levels=c("0","1"),labels=c("No","Yes")),
         alcohol_hist = factor(case_when(a1310==999 ~ NA_real_,
                                  a1310==0 | a1311=="actualmente no toma" ~ 0,
                                  TRUE ~ 1),levels=c("0","1"),labels=c("No","Yes")),
         cardiovascular_hist=factor(ifelse(a502a=="s\xed" | a502b=="s\xed" | a502c=="s\xed" | a502d=="s\xed",1,0),levels=c("0","1"),labels=c("No","Yes"))) %>%
  select(-c(pondef,a301,a701a,a701b,a1310,a1311,a502a,a502b,a502c,a502d,a1301,afilia2))

diabetes$sexo<-recode(diabetes$sexo,hombres = "Men",mujeres="Women")
diabetes$ob_abd<-recode(diabetes$ob_abd,normal = "Normal",obesidad="Obesity")
diabetes$escolari<-recode(diabetes$escolari,ninguna = "None",`primaria o secundaria`="Elementary",`mas de secundaria`="Middle or more")
diabetes$a401<-recode(diabetes$a401,`s\xed` = "Yes",no="No")
diabetes$a604<-recode(diabetes$a604,`s\xed` = "Yes",no="No",`ns/nr`=NA_character_)
diabetes$area<-recode(diabetes$area,rural = "Rural",urbano="Urban")
diabetes$nse5f<-factor(diabetes$nse5f,levels=c("1","2","3","4","5"),labels=c("First","Second","Third","Fourth","Fifth"))
diabetes$whocat<-recode(diabetes$whocat,inactivos = "Inactive",`moderadamente activos`="Moderately active",activos="Active")


diabetes<-diabetes %>% dplyr::rename(glucose=glucosa,age=edad,sex=sexo,BMI=imc,waist_circum=ccintura,obesity=ob_abd,education_level=escolari,hypertension_hist=a401,
                    stroke=a604,physical_act=afmvms,income_q=nse5f,WHO_act=whocat)

myvars<-c("glucose", "age", "sex", "BMI", "waist_circum", 
          "obesity", "education_level", "income_q", "area", "hypertension_hist", 
          "stroke", "physical_act", "diabetes_hist", "social_security", 
          "smoker", "alcohol_hist", "cardiovascular_hist","WHO_act")

aggr(diabetes[,myvars], col=c('navyblue','red'), numbers=F, sortVars=TRUE, labels=names(data),cex.lab=.9, 
     cex.axis=.4, gap=.1, ylab=c("Histogram of missing data","Pattern"),bars=T,cex.numbers=.7)

diabetes$descode<-diabetes$est_var*10+as.numeric(as.factor(diabetes$code_upm))
init <- mice(diabetes, maxit=0) 
meth <- init$method
predM <- init$predictorMatrix

predM[, c("folio")]=0
predM[, c("intp")]=0
predM[, c("code_upm")]=0
predM[, c("est_urb")]=0
predM[, c("est_marg")]=0
predM[, c("est_var")]=0
predM[, c("waist_circum")]=0
predM[, c("obesity")]=0
predM[, c("nodiagn")]=0


#probablente cambiar
meth[c("age")]="norm" 
meth[c("sex")]="logreg" 
meth[c("BMI")]="norm"
meth[c("waist_circum")]="norm"
meth[c("obesity")]="logreg"
meth[c("area")]="logreg"
meth[c("diabetes_hist")]="logreg"
meth[c("education_level")]="polyreg"
meth[c("income_q")]="polr"
meth[c("physical_act")]="norm"
meth[c("WHO_act")]="polyreg"
meth[c("social_security")]="logreg"
meth[c("stroke")]="logreg"
meth[c("smoker")]="logreg"
meth[c("alcohol_hist")]="logreg"


imputed <- mice(diabetes, method=meth, predictorMatrix=predM, m=5)
imputed <- complete(imputed)
sapply(imputed, function(x) sum(is.na(x)))

trainingRows <- createDataPartition(imputed$prediabetes,p = .8,list= FALSE)
training <- imputed[trainingRows,]
test <- imputed[-trainingRows,]
reduced<- c("age", "sex", "BMI", 
            "education_level", "income_q", "area", "hypertension_hist", 
            "stroke", "physical_act",
            "diabetes_hist", "social_security", "smoker", "alcohol_hist", 
            "cardiovascular_hist")

ctrl <- trainControl(method = "LGOCV",
                     summaryFunction = twoClassSummary,
                     classProbs = TRUE,
                     index = list(TrainSet = trainingRows),
                     savePredictions = TRUE)

x <- model.matrix( ~ ., imputed[,reduced])

glmnGrid <- expand.grid(.alpha = c(0, .1, .2, .4, .6, .8, 1),.lambda = seq(.01, 1, length = 80))

glmnTuned <- train(x,
                   y = imputed$prediabetes,weights = imputed$PONDEV3/mean(imputed$PONDEV3),
                   method = "glmnet",
                   tuneGrid = glmnGrid,
                   metric = "ROC",
                   trControl = ctrl)

glmnTuned$bestTune

selected<-glmnTuned$pred

selected<-selected %>% filter(alpha==glmnTuned$bestTune$alpha,lambda==glmnTuned$bestTune$lambda)

ROC<-plot.roc(selected$obs,selected$Yes,print.auc=T)
