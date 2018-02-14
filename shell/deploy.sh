#!/bin/bash -
# Any subsequent(*) commands which fail will cause the shell script to exit immediately
#set -e

################=-= START OF CUSTOM SERVICE CONFIGURATION =-#####################

# lets find out what path this file has:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# lets load config variables (assume it is in same folder):
# NOTE: you need to create this file on the server (see config_deploy_generic.sh)
source "$DIR/config_deploy.sh";

#Config will give these variables: 
#echo "$PORT, $RUNASUSER, $PROJ_DIR, $PROJ_NAME, $OPTIONS, $DB_NAME, $DB_USER, $DB_PASS"

###################=-= END OF CUSTOM CONFIGURATION =-=###############################

MS_JAR=$PROJ_NAME_backend-0.0.1_${PORT}-SNAPSHOT.jar 

# Where micro service war/jar file sits?
MS_HOME=/build/libs 


DATE=`date +%Y-%m-%d--H%H-M%M-S%S`

SHUTDOWN_WAIT=20; # before issuing kill -9 on process.

# These options are used when micro service is starting 
# Add whatever you want/need here... overrides application.properties
UTF_OPTION="-Dfile.encoding=UTF-8" 
OPTIONS="${UTF_OPTION} -Dserver.port=${PORT} ${OPTIONS}"
# Try to get PID of spring jar/war
MS_PID=`ps fax|grep java|grep "${MS_JAR}"|awk '{print $1}'`
export MS_PID;

FRONTEND_DIR=${PROJ_DIR}/${PROJ_NAME}_frontend
BACKEND_DIR=${PROJ_DIR}/${PROJ_NAME}_backend
SCRIPT_DIR=${BACKEND_DIR}/script/shell

# Function: run_as
run_as() {
	local iam iwant;

	iam=$(id -nu);
	iwant="$1";
	shift;
	

	if [ "${iam}" = "${iwant}" ]; then {
		eval $*;
	}
	else {
		/bin/su -p -s /bin/sh ${iwant} $*;
	} fi;
}
#build frontend part of application
build_frontend() {
	cd $FRONTEND_DIR;
	run_as ${RUNASUSER} npm install;
	ENV_URL=
	[[ ! -z $API_URL ]] && ENV_URL="env API_URL=${API_URL}"
	run_as ${RUNASUSER} ${ENV_URL} npm run build;
	echo "###########    the task build_frontend completed successfully, API_URL=${API_URL}     ########";
}

#build mobile application, should come between build_frontend and build_backend
build_mobile_app() {
	cd $FRONTEND_DIR;
	run_as ${RUNASUSER} cordova platform add android;
	run_as ${RUNASUSER} env ANDROID_HOME=${ANDROID_HOME} cordova build android --release -- --keystore=${ANDROID_KEYSTORE} --storePassword=${ANDROID_PASSWORD} --alias=${PROJ_NAME}_key --password=${ANDROID_PASSWORD};
	#now lets copy the file to the server:
	cp ./platforms/android/build/outputs/apk/android-release.apk $BACKEND_DIR/src/main/resources/public/android-release.apk
	echo "##########    apk copied and can be found at: http://<ip>:<port>/android-release.apk 		########"
	echo "###########    the task build_mobile_app completed successfully, ANDROID_HOME=${ANDROID_HOME}     ########";
}

db_backup() {

	date=$(date +"%Y-%m-%d_%H")
	MYSQLDUMP=$(which mysqldump)
	FOLDER_PATH=$BACKEND_DIR/db_backup_prod

	if [[ ! $1 ]]; then {
		echo "Nothing was done due to missing parameter"
		exit 0;
	} fi

	echo "Doing a db backup: $1";

	if [ "$1" = "daily" ]; then {
		FILE_BACKUP=$FOLDER_PATH/_daily_backup.sql
	} 
	elif [ "$1" = "weekly" ]; then {
		FILE_BACKUP=$FOLDER_PATH/$date.sql
	}
	else {
		echo "you can only use daily and weekly as first argument"
		exit 0;
	} fi
	"$MYSQLDUMP" -u$DB_USER -p$DB_PASS $DB_NAME > $FILE_BACKUP
	echo "File writen to $FILE_BACKUP";
}


db_restore() {

	MYSQL=$(which mysql)
	FOLDER_PATH=$BACKEND_DIR/db_backup_prod

	read -p "Are you sure you want to restore db? [ y/n ]" -n 1 -r
	echo    # (optional) move to a new line
	if [[ $REPLY =~ ^[Yy]$ ]]; then {
		read -p "What is the name of database?"
		DB_NAME_RESTORE=$REPLY
		read -p "What is the name of file (will look in to db_backup_production?"
		DB_FILE_RESTORE=$FOLDER_PATH/$REPLY
		#this should not be automated, we will ask for password..
		COMMAND='"$MYSQL" -uroot -p $DB_NAME_RESTORE < $DB_FILE_RESTORE'
		echo "command: $COMMAND"
		echo "Restoring db...:"
		eval $COMMAND
		echo "Restoration done.."
	} fi
}


# Function: start instance (will not rebuild nor restart)
start() {
	pid=${MS_PID}
	if [ -n "${pid}" ]; then {
		echo "Micro service is already running (port: ${PORT})";
	}
	else {
		# Start screener ms
		echo "Starting micro service";
		cd ${BACKEND_DIR}
		#lets remove old screenlog.0 if it exists (new one will be created by screen)
		[ -e screenlog.0 ] && rm screenlog.0 
		run_as ${RUNASUSER} screen -m -d -L java -jar ${OPTIONS} ./${MS_HOME}/${MS_JAR};
		#if jenkins is runnin we will not tail
		echo "###########    WE ARE TAILING, YOU CAN PRESS CTRL-C TO STOP TAIL, IT WILL NOT STOP THE APPLICATION ########"
		#wait for a hafl of sec for process to start
		sleep .5
		#we will tail for 90 sec then tail will be killed (needed for jenkins)
		timeout --foreground 90s tail -f screenlog.0;
	} fi;
	# return 0;
}

generate_dummy() {
	cd ${BACKEND_DIR}
	#--tests specify the file to run, --rerun-tasks rerun test even when no code change..
	run_as ${RUNASUSER} ./gradlew test --tests --rerun-tasks integration.dbGenerator.init.Main ${UTF_OPTION}
}

build_backend() {
	cd ${BACKEND_DIR}
	#port is injected in to build.gradle
	run_as ${RUNASUSER} ./gradlew bootRepackage -Pport=${PORT};
	echo "###########    the task build_backend completed successfully     ########";
}

# Function: stop
stop() {
	pid=${MS_PID}
	if [ -n "${pid}" ]; then {

		run_as ${RUNASUSER} kill -TERM $pid;

		echo -ne "Stopping micro service module running on port: ${PORT}";

		kwait=${SHUTDOWN_WAIT};

		count=0;
		while kill -0 ${pid} 2>/dev/null && [ ${count} -le ${kwait} ]; do {
			printf ".";
			sleep 1;
			(( count++ ));
		} done;

		echo;

		if [ ${count} -gt ${kwait} ]; then {
			printf "process is still running after %d seconds, killing process" \
				${SHUTDOWN_WAIT};
			kill ${pid};
			sleep 3;

			# if it's still running use kill -9
			#
			if kill -0 ${pid} 2>/dev/null; then {
				echo "process is still running, using kill -9";
				kill -9 ${pid}
				sleep 3;
			} fi;
		} fi;

		if kill -0 ${pid} 2>/dev/null; then {
			echo "process is still running, I give up";
		} 
		else {
			# success, delete PID file, if you have used it with spring boot
			# rm -f ${SPRING_BOOT_APP_PID};
			echo "Service is stopped";
			unset MS_PID;
		} fi;
	} 
	else {
	echo "Micro service is not running (port: ${PORT}";
	} fi;

}
set_deploy_date() {
	echo "export const deployDate = \"${DATE}\"; " > ${FRONTEND_DIR}/src/services/deployDate.js
}

pull() {
	#clone/pull the prject
	if [ -d ${PROJ_DIR} ]; then {
	    echo "Starting git pull $PROJ_GIT_URL"
	    run_as ${RUNASUSER} cd ${PROJ_DIR} && yes | run_as ${RUNASUSER} git pull ${PROJ_GIT_URL};
	} else {
	    echo "Starting git clone $PROJ_GIT_URL ${PROJ_DIR}"
	    yes | run_as ${RUNASUSER} git clone ${PROJ_GIT_URL} ${PROJ_DIR} && run_as ${RUNASUSER} cd ${PROJ_DIR};
	} fi;
	echo "git pull done"
}

update_version() {
	#will update version number in file below..
	file=$BACKEND_DIR/config/application.properties
	line_number=2
	line="`sed -n ${line_number}p $file`"
	v_number=${line//[!0-9]/}
	v_number=$((v_number+1))
	sed -i "${line_number}s/.*/${PROJ_NAME}.build-version=v$v_number/" $file
	echo "build numer updated, number: $v_number"
}

create_dir() {
	if [[ ! -d $1 ]]; then
		mkdir "$1" 2> /dev/null || { echo "Cannot make directory $1" 1>&2; exit 1; }
	fi
}

status() {
	pid=$MS_PID
		if [ "${pid}" ]; then {
			echo "Micro service module is running with pid: ${pid}";
		}
		else {
			echo "Micro service module is not running";
		} fi;
}

test() {
    echo "Testing..";
    WORK_DIR=$(pwd)
    cd ${BACKEND_DIR}
    #ADD yout test scipt here: 

    echo "...."
    cd ${WORK_DIR}
}

restart() {
	#This function needs to be defined in config_deploy.sh (same folder as this file)
	config_deploy_restart;
}



# Main Code

case $1 in
	help)
		echo "options: 
start, build_backend, build_frontend, stop, restart, restart_backend, status, 
set_deploy_date, pull, auto_deploy, db_backup, db_restore, 
generate_dummy, build_mobile_app";
		;;
	set_deploy_date)
		set_deploy_date;
		;;
	start)
		start;
		;;
	build_frontend)
		set_deploy_date;
		build_frontend;
		;;
	build_backend)
		build_backend;
		;;
	pull)
		pull;
		;;
	stop)
		stop;
		;;
	restart_backend)
		stop;
		build_backend;
		start;
		;;
	restart)
		restart;
		;;
	status)
		status;
		;;
	db_backup)
		db_backup $2;
		;;
	db_restore)
		db_restore;
		;;
	auto_deploy)
		auto_deploy;
		;;
	generate_dummy)
		generate_dummy;
		;;
	update_version)
		update_version;
		;;
	build_mobile_app)
		build_mobile_app;
		;;
esac

exit 0;
