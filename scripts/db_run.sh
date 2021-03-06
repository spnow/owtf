#!/usr/bin/env sh
# This script runs postgres server in very stupid ways, this script is tested
# extensively on Kali

get_config_value(){

    parameter=$1
    file=$2

    echo "$(grep -i $parameter $file | sed  "s|$parameter: ||g;s|~|$HOME|g")"
}

get_db_config_file(){

    config_file=$1
    db_config_file=$2

    default_db_config_file="$(get_config_value DATABASE_SETTINGS_FILE $config_file)"
    if [ -f "$default_db_config_file" ]; then
        echo "$default_db_config_file"
        return 0
    fi
    if [ -f "$db_config_file" ]; then
        echo "$db_config_file"
        return 0
    fi
    echo "Default file "$default_db_config_file" does not exist" >&2
    echo "Rerun script with path parameter. Usage : $0 [db_config_file_path]" >&2
    return 1
}

get_postgres_server_ip() {
    echo "$(sudo netstat -lptn | grep "^tcp " | grep postgres | sed 's/\s\+/ /g' | cut -d ' ' -f4 | cut -d ':' -f1)"
}

get_postgres_server_port() {
    echo "$(sudo netstat -lptn | grep "^tcp " | grep postgres | sed 's/\s\+/ /g' | cut -d ' ' -f4 | cut -d ':' -f2)"
}

FILE_PATH=$(readlink -f "$0")
SCRIPTS_DIR=$(dirname "$FILE_PATH")
RootDir=$(dirname "$SCRIPTS_DIR")

config_file="$RootDir/framework/config/framework_config.cfg"
db_config_file="$(get_db_config_file $config_file $1)"

if [ ! -f "$db_config_file" ]; then
    exit 1
fi

# Saved postgres settings
saved_server_ip="$(get_config_value DATABASE_IP $db_config_file)"
saved_server_port="$(get_config_value DATABASE_PORT $db_config_file)"
saved_server_dbname="$(get_config_value DATABASE_NAME $db_config_file)"
saved_server_user="$(get_config_value DATABASE_USER $db_config_file)"
saved_server_pass="$(get_config_value DATABASE_PASS $db_config_file)"

# Check if postgres is running
postgres_server_ip=$(get_postgres_server_ip)
postgres_server_port=$(get_postgres_server_port)

# PostgreSQL version
postgres_version="$(psql --version 2>&1 | tail -1 | awk '{print $3}' | sed 's/\./ /g' | awk '{print $1 "." $2}')"

if [ -z "$postgres_server_ip" ]; then
    echo "[+] PostgreSQL server is not running."
    echo "[+] Can I start db server for you? [Y/n]"
    read choice
    if [ "$choice" != "n" ]; then
        sudo which service  >> /dev/null 2>&1
        service_bin=$?
        sudo which systemctl  >> /dev/null 2>&1
        systemctl_bin=$?
        if [ "$service_bin" = "0" ]; then
            sudo service postgresql start
            sudo service postgresql status | grep -q "Active: active"
            status_exitcode="$?"
        elif [ "$systemctl_bin" = "0" ]; then
            sudo systemctl start postgresql
            sudo systemctl status postgresql | grep -q "Active: active"
            status_exitcode="$?"
        elif [ "$systemctl_bin" != "0" ] && [ "$service_bin" != "0" ]; then
            echo "[+] Using pg_ctlcluster to start the server."
            sudo pg_ctlcluster ${postgres_version} main start
        else
            echo "[+] We couldn't determine how to start the postgres server, please start it and rerun this script"
            exit 1
        fi
        if [ "$status_exitcode" != "0" ]; then
            echo "[+] Starting failed because postgreSQL service is not available!"
            echo "[+] Run # sh scripts/start_postgres.sh and rerun this script"
            exit 1
        fi
    else
        echo "[+] On DEBIAN based distro [i.e Kali, Ubuntu etc..]"
        echo "          sudo service postgresql start"
        echo "[+] On RPM based distro [i.e Fedora etc..]"
        echo "          sudo systemctl start postgresql"
        exit 1
    fi
fi

# Refresh postgres settings
postgres_server_ips=$(get_postgres_server_ip)
postgres_server_ports=$(get_postgres_server_port)

if test "${postgres_server_ips#*$saved_server_ip}" = "$postgres_server_ips" || test "${postgres_server_ports#*$saved_server_port}" = "$postgres_server_ports"; then
    postgres_server_ip=$(echo $postgres_server_ips | sed 's/ .*//')
    postgres_server_port=$(echo $postgres_server_ports | sed 's/ .*//')
    echo "[+] Postgres running on $postgres_server_ip:$postgres_server_port"
    echo "[+] OWTF db config points towards $saved_server_ip:$saved_server_port"
    echo "[+] Do you want us to save the new settings for OWTF? [Y/n]"
    read choice
    if [ "$choice" != "n" ]; then
        sed -i "/DATABASE_IP/s/$saved_server_ip/$postgres_server_ip/" $db_config_file
        sed -i "/DATABASE_PORT/s/$saved_server_port/$postgres_server_port/" $db_config_file
        echo "[+] New database configuration saved"
    fi
fi

check_owtf_db=$(sudo su - postgres -c "psql -l | grep -w $saved_server_dbname | grep -w $saved_server_user | wc -l")
if [ "$check_owtf_db" = "0" ]; then
    echo "[+] The problem seems to be the user role and db mentioned in $db_config_file. Do you want us to create them? [Y/n]"
    read choice
    if [ "$choice" != "n" ]; then
        sh $RootDir/scripts/db_setup.sh init
    fi
fi
