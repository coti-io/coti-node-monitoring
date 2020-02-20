#!/bin/sh

# The goal of this script is to setup a monitoring server.
# Please note: a Linux machine with docker and docker-compose are required.

# For output readability
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
COLOR_RESET=`tput sgr0`


# Grafana API URLS
GRAFANA_API_BASE=localhost:3000
GRAFANA_API_PING="${GRAFANA_API_BASE}/api/login/ping"
GRAFANA_API_PASSWORD="${GRAFANA_API_BASE}/api/user/password"
GRAFANA_API_DATASOURCES="${GRAFANA_API_BASE}/api/datasources"
GRAFANA_API_DATASOURCES_GET_BY_NAME="${GRAFANA_API_BASE}/api/datasources/name"
GRAFANA_API_DASHBOARDS="${GRAFANA_API_BASE}/api/dashboards"

# Read args / input parameters
read_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip_setup=*)
        skip_setup="${1#*=}"
        ;;
      --logstash_image=*)
        logstash_image="${1#*=}"
        ;;
      --influxdb_admin_pwd=*)
        influxdb_admin_pwd="${1#*=}"
        ;;
      --influxdb_user_pwd=*)
        influxdb_user_pwd="${1#*=}"
        ;;
      --docker_network=*)
        docker_network="${1#*=}"
        ;;
      --es_java_opts=*)
        es_java_opts="${1#*=}"
        ;;
      --grafana_admin_pwd=*)
        grafana_admin_pwd="${1#*=}"
        ;;
      --grafana_admin_new_pwd=*)
        grafana_admin_new_pwd="${1#*=}"
        ;;*)

      # Exit with a message
      retval_checks 1 "***************************\n* Error: Invalid argument.*\n***************************\n"
    esac
    shift
  done

  # Default optional args
  skip_setup="${skip_setup:-"false"}"
  echo "skip_setup: ${skip_setup} "

}

# verify that a program is installed
is_program_installed() {
  if ! [ -x "$(command -v "${1}")" ]; then
    echo "${RED}${1} is not installed.${COLOR_RESET}" >&2
    retval=1
  else
    echo "${GREEN}${1} installed, we continue${COLOR_RESET}"
    retval=0
  fi
}

# Centralize checks and exit, for not repeating this
retval_checks() {
  exit_code="${1}"
  message="${2}"
  if [ "${exit_code}" != 0 ]; then
    echo "${message}"
    exit "${exit_code}"
  fi
}

# Check that all required software is installed
verify_env_ready() {
  # Check that docker-compose is installed
  is_program_installed docker-compose
  retval_checks "${retval}" "Please install docker-compose and re-run"
}

# Build the logstash conatiner, with the relevant configuration
build_logstash_container() {
  logstash_image_name="${1}"
  cd logstash

  docker build --no-cache -t "${logstash_image_name}" .
  retval_checks "${?}" "building the logstash image failed, please rebiew your scripts, or contact someone that knows...."
  cd ..
}

# Create a docker network, in case it does not already exists
create_network() {
  docker network inspect "${docker_network}" >/dev/null 2>&1 || \
    docker network create "${docker_network}"
}

# Wait for InfluxDB to start, and then create a retention policy
setup_influxdb_retention_policy() {
  printf 'Waiting for InfluxDB to start, for setting retention policy...'

  until $(curl --output /dev/null --silent --head --fail http://localhost:8086/ping); do
      printf '.'
      sleep 5
  done

  echo ""
  curl -i -XPOST localhost:8086/query --data-urlencode "q=CREATE RETENTION POLICY "one_week" ON "telegraf" DURATION 1w REPLICATION 1 DEFAULT"
  echo ""
  echo "${GREEN}InfluxDB started to serve, and retention policy set${COLOR_RESET}"
}

wait_for_es_up_and_serve() {
  printf 'Waiting for elasticsearch to start and serve...'

  until $(curl --output /dev/null --silent --head --fail localhost:9200); do
      printf '.'
      sleep 5
  done

  echo ""
  echo "${GREEN}Elasticsearch started to serve${COLOR_RESET}"
}

do_export() {
  export logstash_image_name="${logstash_image_name}"
  export es_java_opts="${es_java_opts}"
}

grafana_change_admin_pwd() {

  echo "Changing grafana admin pwd"

  # Chenge admin pwd
  message=$(curl -s -X PUT \
    "${GRAFANA_API_PASSWORD}" \
    -u admin:"${grafana_admin_pwd}" \
    -H "Accept:application\/json" \
    -H "Content-Type:application\/json" \
    -d "{
      \"oldPassword\": \""${grafana_admin_pwd}"\",
      \"newPassword\": \""${grafana_admin_new_pwd}"\",
      \"confirmNew\": \""${grafana_admin_new_pwd}"\"
    }" | jq '.message')

  if [ "${message}" = "\"User password changed\"" ]; then
    echo "${GREEN}Admin pwd changed:${COLOR_RESET} ${message}"
  else
    echo "${RED}Admin pwd change failed:${COLOR_RESET} ${message}"
    echo "${RED}Terminating, no point in continue...${COLOR_RESET}"
    exit 1
  fi
}

grafana_create_datasources() {

  echo "Creating grafana data sources"

  # Set up InfluxDB data source  in grafana
  setup_grafana_datasource "InfluxDB" "{
        \"name\": \"InfluxDB\",
        \"type\": \"influxdb\",
        \"access\": \"proxy\",
        \"url\": \"http://influxdb:8086\",
        \"user\": \"telegraf\",
        \"database\": \"telegraf\",
        \"basicAuth\": false,
        \"withCredentials\": false,
        \"isDefault\": true,
        \"version\": 1,
        \"readOnly\": false,
        \"secureJsonData\": {
          \"password\": \""${influxdb_user_pwd}"\"
        }
      }"

  # Set up Elasticsearch data source in grafana
  setup_grafana_datasource "Elasticsearch" "{
        \"name\": \"Elasticsearch\",
        \"type\": \"elasticsearch\",
        \"access\": \"proxy\",
        \"url\": \"http://elasticsearch:9200\",
        \"database\": \"[filebeat-7.4.0-]YYYY.MM.DD\",
        \"basicAuth\": false,
        \"withCredentials\": false,
        \"isDefault\": false,
        \"jsonData\": {
          \"timeField\": \"@timestamp\",
          \"esVersion\": 70,
          \"maxConcurrentShardRequests\": \"5\",
          \"logMessageField\": \"\",
          \"logLevelField\": \"\",
          \"keepCookies\": [],
          \"interval\": \"Daily\"
        },
        \"version\": 1,
        \"readOnly\": false
      }"
}

grafana_create_dashboards() {
  echo "Creating grafana dashboards"

  setup_grafana_dashboard "kjTPHcTZk" "@grafana/dashboards/logs_elastic.json"
  setup_grafana_dashboard "3GkPHbtWz" "@grafana/dashboards/processes_top.json"
  setup_grafana_dashboard "000000127" "@grafana/dashboards/telegraf_system_dashboard.json"

}

# Setup grafana:
# - Change admin pwd
# - Data sources
# -- InfluxDB
# -- Elasticsearch
# - Dashboards
setup_grafana() {
  echo "${YELLOW}Setting up Grafana${COLOR_RESET}"

  # Ping to verify that we have access to grafana
  ping=$(curl -s -u admin:"${grafana_admin_pwd}" "${GRAFANA_API_PING}")

  # When ping returns something other than "Logged in", we would like to read the message returned from Grafana
  if [ ! "${ping}" = "Logged in" ]; then
    ping="${ping}" | jq ".message"
  fi

  if [ "${ping}" = "\"Invalid username or password\"" ]; then
    echo "${RED}Login to grafana failed: \"Invalid username or password\"${COLOR_RESET}"
    echo "${RED}Terminating, no point in continue...${COLOR_RESET}"
    exit 1
  else
    echo "DEBUG: ${ping}"
    if ! [ "${grafana_admin_pwd}" = "${grafana_admin_new_pwd}" ]; then
      # Chenge admin pwd only if there's a reason to
      grafana_change_admin_pwd
    fi
  fi

  grafana_create_datasources

  grafana_create_dashboards

  echo "Finish setting up grafana"
}

setup_grafana_datasource() {

  ds_name="${1}"
  ds_payload="${2}"

  echo "Setting up Grafana datasource: ${YELLOW}${ds_name}${COLOR_RESET}"

  # Check if InfluxDB data source exists
  message=$(curl -s -X GET \
    "${GRAFANA_API_DATASOURCES_GET_BY_NAME}/${ds_name}" \
    -u admin:"${grafana_admin_new_pwd}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json"| jq ".message")

  if [ "${message}" = "\"Data source not found\"" ]; then
    # Datasource does not exist, create it
    echo "Setting up InfluxDB datasource"

    message=$(curl -s -X POST \
      "${GRAFANA_API_DATASOURCES}" \
      -u admin:"${grafana_admin_new_pwd}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "${ds_payload}" | jq ".message")

    # Datasource create response message
    if [ "${message}" = "\"Datasource added\"" ]; then
      echo "${GREEN}Data source created:${COLOR_RESET} ${message}"
    else
      echo "${RED}Data source creation failed:${COLOR_RESET} ${message}"
    fi
  else
    echo "${YELLOW}Data source not set - already exists${COLOR_RESET}"
  fi

}

setup_grafana_dashboard() {
  local dashboard_uid="${1}"
  local dashboard_json_path="${2}"
  echo "Setting up Grafana dashboard: ${YELLOW}${dashboard_json_path}${COLOR_RESET}"

  echo "${GRAFANA_API_DASHBOARDS}/uid/${dashboard_uid}"

  message=$(curl -s -X GET \
    "${GRAFANA_API_DASHBOARDS}/uid/${dashboard_uid}" \
    -u admin:"${grafana_admin_new_pwd}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" | jq ".message")

  if [ "${message}" = "\"Dashboard not found\"" ]; then
    message=$(curl -s -X POST \
      "${GRAFANA_API_DASHBOARDS}/db" \
      -u admin:"${grafana_admin_new_pwd}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "${dashboard_json_path}" | jq ".status")

    echo "${GREEN}Dashboard create status: ${message}${COLOR_RESET}"
  else
    echo "${RED}Dashboard already exists. If you wish to modify it, use grafana directly (UI or API)${COLOR_RESET}"
  fi
}

# Execute

echo '
  _____      _   _   _   _           _        __  __             _ _             _
 / ____|    | | (_) | \ | |         | |      |  \/  |           (_) |           (_)
| |     ___ | |_ _  |  \| | ___   __| | ___  | \  / | ___  _ __  _| |_ ___  _ __ _ _ __   __ _
| |    / _ \| __| | | . ` |/ _ \ / _` |/ _ \ | |\/| |/ _ \| `_ \| | __/ _ \| `__| | `_ \ / _` |
| |___| (_) | |_| | | |\  | (_) | (_| |  __/ | |  | | (_) | | | | | || (_) | |  | | | | | (_| |
 \_____\___/ \__|_| |_| \_|\___/ \__,_|\___| |_|  |_|\___/|_| |_|_|\__\___/|_|  |_|_| |_|\__, |
                                                                                          __/ |
                                                                                         |___/
          '


# Read the command line arguments
read_args "$@"

# Based on the args read, export what needs to get exported
do_export

# Make sure that we have all needed SW installed, in order to execute
verify_env_ready

# In case of --skip_setup=true passed as an argument, do NOT run any setup commands,
# and proceed sirectly to config parts in this script
if [ "${skip_setup}" != "true" ]; then

  echo "Executing setup:"

  # Network - create or ignore error if exists
  create_network

   # Volumes
  echo "${YELLOW}Creating volumes${COLOR_RESET}"
  docker volume create grafana-volume && docker volume create influxdb-volume && docker volume create es-volume && docker volume create logstash-volume

  # Setup InfluxDB.
  # Please note:
  # 1. After this command, the container is not running!!!
  # 2. We need to execute this command BEFORE compose up
  echo "${YELLOW}Init (setting up) InfluxDB${COLOR_RESET}"
  docker run --rm -e INFLUXDB_DB=telegraf -e INFLUXDB_ADMIN_ENABLED=true -e INFLUXDB_ADMIN_USER=admin -e INFLUXDB_ADMIN_PASSWORD="${influxdb_admin_pwd}" -e INFLUXDB_USER=telegraf -e INFLUXDB_USER_PASSWORD="${influxdb_user_pwd}" -v influxdb-volume:/var/lib/influxdb influxdb /init-influxdb.sh

  # Build Coti's logstash image
  echo "${YELLOW}Building Coti's Logstash container${COLOR_RESET}"
  build_logstash_container "${logstash_image}"

  # Helps ES to run :(
  sysctl -w vm.max_map_count=262144

  # Up...
  echo "Up..."
  docker-compose up -d

  # Setup the retention policy of InfluxDB
  setup_influxdb_retention_policy

  # Wait for ES to start
  wait_for_es_up_and_serve
else
  echo "In a skip setup mode, verify"

  # If servers not up, user can't skip setup.
  # TBD - this is an extremely naive implementation, need to improve it
  if curl -s --head --request GET localhost:9200 | grep "200 OK" > /dev/null; then
    echo "${GREEN}Skip mode verified, continue to system configuration${COLOR_RESET}"
  else
    echo "${RED}Syste, is up, cannot skip setup. Exit now${COLOR_RESET}"
    exit 1
  fi
fi

# Setup grafana
setup_grafana

# We arrived this far, we are amazing ;)
echo '
 _____                _         _           _____       _ _ _
|  __ \              | |       | |         / ____|     | | | |
| |__) |___  __ _  __| |_   _  | |_ ___   | |  __  ___ | | | |
|  _  // _ \/ _` |/ _` | | | | | __/ _ \  | | |_ |/ _ \| | | |
| | \ \  __/ (_| | (_| | |_| | | || (_) | | |__| | (_) |_|_|_|
|_|  \_\___|\__,_|\__,_|\__, |  \__\___/   \_____|\___/(_|_|_)
                         __/ |
                        |___/

          '
