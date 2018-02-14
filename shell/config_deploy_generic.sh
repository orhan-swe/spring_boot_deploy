#!/bin/bash -

PROJ_DIR=~/vala
PROJ_NAME=vala 

# if port number for spring boot is < 1024 it needs root perm.
PORT=8080 
RUNASUSER=<user_name> 

###########################################
#optional for Android app and jenkins:
API_URL=http://<ip>:${PORT}/api/v1
JENKINS_DIR=~/jenkins
PROJ_GIT_URL=git@github....

ANDROID_KEYSTORE=~/keystores/android.jks
ANDROID_PASSWORD=<password>
ANDROID_HOME=~/.android-sdk
###########################################################

#update to production key:
SENTRY_DSN=https://<key>

#add JAVA VM options
OPTIONS="";
OPTIONS="-Dsentry.dsn=$SENTRY_DSN ${OPTIONS}";
OPTIONS="-Xms256m -Xmx3g ${OPTIONS}"
#OPTIONS="-Dspring.profiles.active=dev ${OPTIONS}"

#needed in case you would like to take backup of the db 
DB_NAME=<db_name>;
DB_USER=<db_user>;
DB_PASS=<db_pass>;

#set java if not set on system or to use custom java
#JAVA_HOME=/usr/local/jdk1.8.0_60; 
#PATH=${JAVA_HOME}/bin:${PATH};
#export PATH JAVA_HOME


################### IMPORTANT #############################################
##functions that will be run on restart command, uncomment only what you need..
config_deploy_restart() {
	#db_backup_production;
	stop;
	#pull;
	#set_deploy_date;
	#update_version;
	#build_frontend;
	#build_mobile_app;
	#build_backend;
	start;
}
#####################################################################

