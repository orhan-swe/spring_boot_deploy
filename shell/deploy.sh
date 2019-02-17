#!/bin/bash -

# stop exit script with apprioriate exit code as soon as an error occurs
set -o errexit

# echo commands to output
#set -o xtrace

# Any subsequent(*) commands which fail will cause the shell script to exit immediately
set -e

################=-= START OF CUSTOM SERVICE CONFIGURATION =-#####################

# lets find out what path this file has:
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# lets load config variables (assume it is in same folder):
# NOTE: you need to create this file on the server (see config_deploy_generic.sh)
source "$DIR/config_deploy.sh";

#Config will give these variables:
#echo "$PORT, $RUNASUSER, $PROJ_DIR, $PROJ_NAME, $OPTIONS, $DB_NAME, $DB_USER, $DB_PASS, $DB_GENERATOR_FILE"

###################=-= END OF CUSTOM CONFIGURATION =-=###############################


# Where micro service war/jar file sits?
MS_HOME=/build/libs


DATE=`date +%Y-%m-%d--H%H-M%M-S%S`

SHUTDOWN_TRIES=4; # number of times to try kill.

# These options are used when micro service is starting
# Add whatever you want/need here... overrides application.properties
UTF_OPTION="-Dfile.encoding=UTF-8"
OPTIONS="${UTF_OPTION} -Dserver.port=${PORT} ${OPTIONS}"

FRONTEND_DIR=${PROJ_DIR}/${PROJ_NAME}_frontend
FRONTEND_DIR_MOBILE=${PROJ_DIR}/${PROJ_NAME}_mobile
BACKEND_DIR=${PROJ_DIR}/${PROJ_NAME}_backend
SCRIPT_DIR=${BACKEND_DIR}/script/shell
VERSION_UPDATED=false

_getPID() {
        echo `ps fax|grep java|grep "${PORT}"|awk '{print $1}'`
}

get_another_build_running_pid() {
        echo `ps fax|grep gradlew|grep "${PORT}"|awk '{print $1}'`
}


get_current_build_version() {
        local _FILE=$BACKEND_DIR/config/application.properties
        local _LINE_NUMBER=2;
        local _LINE="`sed -n ${_LINE_NUMBER}p $_FILE`"
        local _V_NUMBER=${_LINE//[!0-9]/}
        # we do not have return in bash so we have to echo and calling function picks it up
        echo "$_V_NUMBER"
}

stop() {
        local pid=$(get_another_build_running_pid)
        if [ -n "${pid}" ]; then {
                echo "Stoping another build, pid: $pid"
                _stopPID $pid
        } else {
                echo "No other buidls are running"
        } fi

        pid=$(_getPID)
        if [ -n "${pid}" ]; then {
                echo "Stoping another build, pid: $pid"
                _stopPID $pid
        } else {
                echo "No other buidls are running"
        } fi
}

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
        update_version
        cd $FRONTEND_DIR;
        #run_as ${RUNASUSER} npm install --production;
        run_as ${RUNASUSER} npm install;
        #you can pass an env variable to the frontend if needed:
        #[[ ! -z $ENV_VAR ]] && ENV_VAR="env ENV_VAR=${ENV_VAR}"
        run_as ${RUNASUSER} ${ENV_VAR} npm run build;
        echo "###########    the task build_frontend completed successfully     ########";
}

#build mobile application, should come between build_frontend and build_backend
build_mobile_app_android() {
        cd $FRONTEND_DIR_MOBILE/cordova;
        run_as ${RUNASUSER} cordova prepare;
        local _LINE="url:\"$SERVER_URL/android/index.html\","
        replace_line_in_file 3 $_LINE "./www/js/url_config.js";

        run_as ${RUNASUSER} env ANDROID_HOME=${ANDROID_HOME} cordova build android --release -- --keystore=${ANDROID_KEYSTORE} --storePassword=${ANDROID_PASSWORD} --alias=${PROJ_NAME}_key --password=${ANDROID_PASSWORD};
        #now lets copy the file to the server:
        cp ./platforms/android/build/outputs/apk/release/android-release.apk $BACKEND_DIR/src/main/resources/public/android/android-release.apk
        echo "##########    apk copied and can be found at: ${SERVER_URL}/android/android-release.apk           ########"
        echo "###########    the task build_mobile_app_android completed successfully, ANDROID_HOME=${ANDROID_HOME}     ########";
}

db_backup() {

        date=$(date +"%Y-%m-%d_%H")
        local _MYSQLDUMP=$(which mysqldump)
        local _FOLDER_PATH=$BACKEND_DIR/db_backup_prod

        if [[ ! $1 ]]; then {
                echo "Nothing was done due to missing parameter"
                exit 0;
        } fi

        echo "Doing a db backup: $1";

        if [ "$1" = "daily" ]; then {
                local _FILE_BACKUP=$_FOLDER_PATH/_daily_backup.sql
        }
        elif [ "$1" = "weekly" ]; then {
                local _FILE_BACKUP=$_FOLDER_PATH/$date.sql
        }
        else {
                echo "you can only use daily and weekly as first argument"
                exit 0;
        } fi
        "$_MYSQLDUMP" -u$DB_USER -p$DB_PASS $DB_NAME > $_FILE_BACKUP
        echo "File writen to $_FILE_BACKUP";
}


db_restore() {

        local _MYSQL=$(which mysql)
        local _FOLDER_PATH=$BACKEND_DIR/db_backup_prod

        read -p "Are you sure you want to restore db? [ y/n ]" -n 1 -r
        echo    # (optional) move to a new line
        if [[ $REPLY =~ ^[Yy]$ ]]; then {
                read -p "What is the name of database?"
                local _DB_NAME_RESTORE=$REPLY
                read -p "What is the name of file (will look in to db_backup_production?"
                local _DB_FILE_RESTORE=$_FOLDER_PATH/$REPLY
                #this should not be automated, we will ask for password..
                _COMMAND='"$_MYSQL" -uroot -p $_DB_NAME_RESTORE < $_DB_FILE_RESTORE'
                echo "command: $_COMMAND"
                echo "Restoring db...:"
                eval $_COMMAND
                echo "Restoration done.."
        } fi
}

# Function: start instance (will not rebuild nor restart)
start() {
        stop
        # Start screener ms
        echo "Starting micro service";
        cd ${BACKEND_DIR}
        #lets remove old screenlog.0 if it exists (new one will be created by screen)
        [ -e screenlog.0 ] && rm screenlog.0
        local MS_JAR="$PROJ_NAME"_backend-$(get_current_build_version)_"${PORT}"-SNAPSHOT.jar
        run_as ${RUNASUSER} screen -m -d -L java -jar ${OPTIONS} .${MS_HOME}/${MS_JAR};
        #if jenkins is runnin we will not tail
        echo "###########    WE ARE TAILING, YOU CAN PRESS CTRL-C TO STOP TAIL, IT WILL NOT STOP THE APPLICATION ########"
        #wait for a hafl of sec for process to start
        sleep 1
        set -x # this is needed so tial works below
        tail -f screenlog.0 | while read LOGLINE
        do
                [[ "${LOGLINE}" == *"JVM running for"* ]] && pkill -P $$ tail
                if [[ "${LOGLINE}" == *" Error"* ]]; then {
                        pkill -P $$ tail;
                        exit 1;
                } fi
        done
}

db_seed() {
        cd ${BACKEND_DIR}
        #--tests specify the file to run, --rerun-tasks rerun test even when no code change..
        run_as ${RUNASUSER} ./gradlew test --stacktrace --tests --rerun-tasks ${DB_SEEDER} ${UTF_OPTION}
}


_stopPID() {

        # parent function must check for pid is empty..
        local pid=$1;
        run_as ${RUNASUSER} kill -TERM $pid;

        echo -ne "Stopping micro service module running on port: ${PORT}";

        ktries=${SHUTDOWN_TRIES};

        count=0;
        while kill -0 ${pid} 2>/dev/null && [ ${count} -le ${ktries} ]; do {
                printf ".";
                sleep 1;
                count=$((count+1));
        } done;

        echo;

        if [ ${count} -gt ${ktries} ]; then {
                printf "process is still running after %d seconds, killing process" \
                        ${pid};
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
        } fi;
}

build_backend() {
        stop
        update_version
        local BUILD_VERSION=$(get_current_build_version)
        cd ${BACKEND_DIR}
        # sometimes we may get errors if we do not do clean first
        #run_as ${RUNASUSER} ./gradlew clean
        #port is injected in to build.gradle
        run_as ${RUNASUSER} ./gradlew bootRepackage -Pport=${PORT} -Pbuild_version=${BUILD_VERSION};
        echo "###########    the task build_backend completed successfully     ########";
}


set_deploy_date() {
        local _FILE=${FRONTEND_DIR}/src/services/deployDate.js
        #in case file does not exist create:
        touch $_FILE
        echo "export const deployDate = \"${DATE}\"; " > $_FILE
}


pull() {
        #clone/pull the prject
        if [ -d ${PROJ_DIR} ]; then {
            echo "Starting git pull $PROJ_GIT_URL"
            run_as ${RUNASUSER} cd ${PROJ_DIR} && yes | run_as ${RUNASUSER} git pull origin ${BRANCH_NAME};
        } else {
            echo "Starting git clone $PROJ_GIT_URL ${PROJ_DIR}"
            yes | run_as ${RUNASUSER} git clone ${PROJ_GIT_URL} ${PROJ_DIR} && run_as ${RUNASUSER} cd ${PROJ_DIR};
            run_as ${RUNASUSER} git checkout ${BRANCH_NAME}
        } fi;
        echo "git pull done"
}

#if new commits in remote repo we will redeploy..
git_check_status_and_redeploy() {
        cd $PROJ_DIR
        echo "Doing git fetch.."
        run_as ${RUNASUSER} git fetch;
        if [ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]; then {
                echo "There are updates on servier, doing git pull"
                run_as ${RUNASUSER} git pull;
                echo "Will do redeploy.."
                restart;
        } fi;
}


#called from parent script, used for refreshing js filese on a new build
update_version() {
        if [ $VERSION_UPDATED == "false" ]; then {
                local _V_NUMBER=$(get_current_build_version)
                _V_NUMBER=$((_V_NUMBER+1))
                #will update version number in file below..
                local _FILE=$BACKEND_DIR/config/application.properties
                local _LINE_NUMBER=2;
                replace_line_in_file $_LINE_NUMBER "${PROJ_NAME}.build-version=v$_V_NUMBER" $_FILE
                echo "build numer updated, number: $_V_NUMBER"
        } fi
        VERSION_UPDATED=true;
}

#will replace the line with the new line in sepcified file
#NOTE: the new line can not have spaces!!

replace_line_in_file() {
        local _LINE_NUMBER=$1;
        local _NEW_LINE=$2;
        file=$3;
        sed -i "${_LINE_NUMBER}s|.*|$_NEW_LINE|" $file
}

create_dir() {
        if [[ ! -d $1 ]]; then {
                mkdir "$1" 2> /dev/null || { echo "Cannot make directory $1" 1>&2; exit 1; }
        } fi
}

status() {
        local pid=$(get_another_build_running_pid)
        if [ -n "${pid}" ]; then {
                echo "Another build running"
        } fi
        pid=$(_getPID)
        if [ -n "${pid}" ]; then {
                echo "Another instance running"
        } fi
}

test() {
    echo "Testing..";
    local _WORK_DIR=$(pwd)
    cd ${_BACKEND_DIR}
    #ADD yout test scipt here:

    echo "...."
    cd ${_WORK_DIR}
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
db_seed_reset_all, db_seed_update_values, build_mobile_app_android";
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
        db_seed)
                db_seed;
                ;;
        build_mobile_app_android)
                build_mobile_app_android;
                ;;
        git_check_status_and_redeploy)
                git_check_status_and_redeploy;
                ;;
esac

exit 0;