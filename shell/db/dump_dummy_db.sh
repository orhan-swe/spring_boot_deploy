#!/bin/bash


#DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#source "$DIR/../config_deploy.sh";

DB_NAME=<db_name>;
DB_USER=<db_user>;
DB_PASS=<db_pass>;

date=$(date +"%Y-%m-%d_%H")
MFILE="temp_db_$date.sql"

# Detect paths
MYSQLDUMP=$(which mysqldump)


SCRIPT_PATH="$DIR/backup_db.sh";
DB_FILE="./src/main/resources/db/data/dev/generated.sql";
IGNORE_SCHEMA_TABLE="true";
EACH_INSERT_NEW_LINE="true";
ONLY_TABLE_NAME="";

#optional parameter:

#OPT1=" --default-character-set=latin1"
OPT1=" --default-character-set=utf8" 
OPT2=" --no-create-info"
OPT3=" --no-create-db"
OPT5=" --result-file=$MFILE"
OPT6=" --complete-insert" #include column names
OPT7=" --compact --compatible=no_field_options,no_table_options,no_key_options,mysql323"
OPT8=" --ignore-table=$DB_NAME.schema_version"
OPT9=" --extended-insert=FALSE" #each insert new row
OPT10=" --tables <some_table>"


ALL_OPTS="$OPT1 $OPT2 $OPT3 $OPT5 $OPT6 $OPT7 $OPT8 $OPT9 $OPT10";

printf "\n STARTING...  Will dump database: $DB_NAME to file: $MFILE , options: \n";
printf "$ALL_OPTS \n";

"$MYSQLDUMP" -u$MUSER -p$MPASS $MDB $ALL_OPTS;

#at start of the file:
sed -i '1iset foreign_key_checks=0;' $MFILE

#at end of the file:
echo "set foreign_key_checks=1;" >> $MFILE;

printf "\n DONE...  have dumped database: $MDB to file: $MFILE \n";
