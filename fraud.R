setwd('/Users/zhanghanduo/Desktop/data/fraud')
rm(list = ls())
library(dplyr)
library(ggplot2)
library(PRROC)
library(tidyverse)
library(randomForest)
library(caret)
############################################################################################################
### import data

df_ip = read.csv('IpAddress_to_Country.csv')
df_fraud = read.csv('Fraud_Data.csv')
attach(df_ip)
attach(df_fraud)

#############################merge two data frame using sqldf


#df = sqldf('select user_id, country 
#         from df_fraud join df_ip
#           on (df_fraud.ip_address <= df_ip.upper_bound_ip_address 
#           and df_fraud.ip_address >=df_ip.lower_bound_ip_address)')

data_country = rep(NA, nrow(df_fraud))
for (i in 1: nrow(df_fraud)){
  tmp = as.character(df_ip[df_fraud$ip_address[i] >= df_ip$lower_bound_ip_address & df_fraud$ip_address[i] <= df_ip$upper_bound_ip_address,"country"])
  if(length(tmp) == 1){data_country[i] = tmp}
  print(i)
}
df_fraud$country = data_country
df_fraud$country[is.na(df_fraud$country)] = 'Not_Found'

#############################EDA

df_fraud$signup_time=as.POSIXct(df_fraud$signup_time,tz= 'GMT')
df_fraud$purchase_time=as.POSIXct(df_fraud$purchase_time,tz= 'GMT')

mean(df_fraud$class) #0.09364577

plot(df_fraud$purchase_value,main = 'purchase_value',ylab = 'purchase_value')
identify(df_fraud$purchase_value,n = 2,labels = purchase_value) #17669 116311

plot(df_fraud$age,main = 'age',ylab = 'age')
identify(df_fraud$age,n = 5,labels = age) #6755  26244  99759 137431 148918

temp = df_fraud[c(6755,26244,99759,137431,148918,17669,116311),]
mean(temp$class) #0, so they can be removed as outliers

df = df_fraud[-c(6755,26244,99759,137431,148918,17669,116311),-c(5,10)]

fraud_country = df %>% 
  group_by(country) %>%
  summarise(avg_fraud = mean(class)) %>%
  arrange(desc(avg_fraud))%>%
  filter(avg_fraud>0.2)
fraud_country #Turkmenistan: 1

fraud_age= df %>% 
  group_by(age) %>%
  summarise(avg_fraud = mean(class)) %>%
  arrange(desc(avg_fraud))
fraud_age #63: 0.286

fraud_sex= df %>% 
  group_by(sex) %>%
  summarise(avg_fraud = mean(class)) %>%
  arrange(desc(avg_fraud))
fraud_sex

fraud_sex_age= df %>% 
  group_by(sex,age) %>%
  summarise(avg_fraud = mean(class)) %>%
  arrange(desc(avg_fraud))
fraud_sex_age #M, 63: 0.366

fraud_browser= df %>% 
  group_by(browser) %>%
  summarise(avg_fraud = mean(class)) %>%
  arrange(desc(avg_fraud))
fraud_browser

df$time_interval = as.numeric(difftime(df$purchase_time,df$signup_time,
                                       units = c('secs')))
#calculate the time intervals between a user's signup and purchase time, units=sec
temp1 = df[(as.numeric(strftime(df$purchase_time,format = '%H'))>23)|
             (as.numeric(strftime(df$purchase_time,format = '%H'))<7),]
mean(temp1$class) #0.09680127, similar with the original data, so maybe  
#not necessarily related with purchase time
rm(temp1)

time_fraud = df %>% 
  group_by(class) %>%
  summarise(avg_time = mean(time_interval))
time_fraud

p <- ggplot(df, aes(x=class, y=time_interval,group = class,fill = class)) + 
  geom_boxplot(outlier.colour="red", outlier.shape=16,
               outlier.size=4)+
  ggtitle("time_intervals_of_2_classes")
p#frauds tend to have much shorter time interval between signup and purchase

sum(df$time_interval==1)/sum(df$class==1) #0.5370645
#over 50% of frauds have time intervals of t1 sec

########################################Random Forest

df$class = as.factor(df$class)
df$country = as.factor(df$country)
df$source = as.factor(df$source)
df$sex = as.factor(df$sex) 
df$browser = as.factor(df$browser)

temp = df[,-c(1:3,10)]#remove user id, signup & purchase time and country
set.seed(1)
train = sample(1:nrow(df),nrow(df)*2/3)

rf.fraud = randomForest(class~.,data = temp,subset = train,
                       mtry = 4,importance = TRUE)
rf.fraud #OOB error rate 4.35%, pretty decent

varImpPlot(rf.fraud) #time intervals have the biggest marginal influence

rf.fraud$confusion
#false negative 0.0004928806(perfect)
#false positive 0.4601526070(too high)

#we want false negative, which is more impactful than 
#false positive, to be as small as possible, but we still
#want users get a satisfying experience during use. 

fraud_pred_rf = predict(rf.fraud,temp[-train,],type = 'prob')
#prediction result(score for each classification)

###################################ROC & PR CURVE

rf_scores = data.frame(class = temp[train,]$class,score = rf.fraud$votes[,2])
               
roc = roc.curve(scores.class0=rf_scores[rf_scores$class=="1",]$score,
         scores.class1=rf_scores[rf_scores$class=="0",]$score,
         curve=T)
plot(roc)
#auc 77% pretty decent, although we might want to try Precision-Recall curve
#since in the typical fraud problem, the data is usually inbalanced, which is 
#effectively resolved in the PR curve, since it didn't include the class 'negative'

pr = pr.curve(scores.class0=rf_scores[rf_scores$class=="1",]$score,
               scores.class1=rf_scores[rf_scores$class=="0",]$score,
               curve=T)
plot(pr)
#The visualized classifier reaches a recall of roughly 50% 
#without any false posiive predictions.
