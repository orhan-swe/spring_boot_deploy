#!/bin/bash -

# stop exit script with apprioriate exit code as soon as an error occurs
set -o errexit

# echo commands to output
#set -o xtrace

PROJ_DIR=~/proj_dir
PROJ_NAME=proj_name
BRANCH_NAME=master

# if port number for spring boot is < 1024 it needs root perm.
PORT=8080
RUNASUSER=user_name

###########################################
#optional for Android app and jenkins:
SERVER_URL=http://hostname:${PORT}
JENKINS_DIR=~/jenkins
PROJ_GIT_URL=git@github....

ANDROID_KEYSTORE=~/keystores/android.jks
ANDROID_PASSWORD=password
ANDROID_HOME=~/.android-sdk
###########################################################

#update to production key:
SENTRY_DSN=https://<key>

#generate dummy date in the db, file to run:
DB_SEEDER=integration.dbGenerator.main.RunDbSeeder

#add JAVA VM options
PROFILE=production
OPTIONS="";
OPTIONS="-Dsentry.dsn=$SENTRY_DSN ${OPTIONS}";
OPTIONS="-Dsentry.environment=${profile} ${OPTIONS}";
OPTIONS="-Xms256m -Xmx3g ${OPTIONS}"
OPTIONS="-Dspring.profiles.active=${PROFILE} ${OPTIONS}"

#needed in case you would like to take backup of the db
DB_NAME=db_name;
DB_USER=db_user;
DB_PASS=db_pass;

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

