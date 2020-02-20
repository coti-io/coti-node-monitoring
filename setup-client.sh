#!/bin/sh

# The goal of this script is to setup a monitoring server.
# Please note: a Linux machine with docker and docker-compose are required.

# For output readability
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
COLOR_RESET=$(tput sgr0)

# Read args / input parameters
read_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip_setup=*)
        skip_setup="${1#*=}"
        ;;
      --influxdb_server_address=*)
        influxdb_server_address="${1#*=}"
        ;;
      --influxdb_password=*)
        influxdb_password="${1#*=}"
        ;;
      --logstash_server_address=*)
        logstash_server_address="${1#*=}"
        ;;
      --filebeat_logs_paths=*)
        filebeat_logs_paths="${1#*=}"
        ;;
      *)

      # Exit with a message
      retval_checks 1 "***************************\n* Error: Invalid argument.*\n***************************\n"
    esac
    shift
  done

  # Default optional args
  skip_setup="${skip_setup:-"false"}"
  echo "skip_setup: ${skip_setup} "

  influxdb_server_address="${influxdb_server_address:-"http://localhost:8086"}"
  echo "influxdb_server_address: ${influxdb_server_address} "

  logstash_server_address="${logstash_server_address:-"localhost:5044"}"
  echo "logstash_server_ip: ${logstash_server_address} "

  # Mandatory missing
  if [ "${influxdb_password}" = "" ]; then
    echo "${RED}influxdb password is mandatory.${COLOR_RESET}"
    echo "for example: --influxdb_password=my_password"
    echo "${RED}Exit, no changes made${COLOR_RESET}"
    exit 1
  fi

  if [ "${filebeat_logs_paths}" = "" ]; then
    echo "${RED}filebeat_logs_pathsis mandatory.${COLOR_RESET}"
    echo "for example: --filebeat_logs_paths=/opt/http/testnet-staging-fullnode1/logs/FullNode1*.log"
    echo "${RED}Exit, no changes made${COLOR_RESET}"
    exit 1
fi

}

# Telegraf - centos
setup_telegraf_centos() {

  echo "${GREEN}Setting up telegraf${COLOR_RESET}"

  # Not skipping setup
  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}Installing telegraf${COLOR_RESET}"

    yum -y update

    # Add repo
    cat <<EOF | sudo tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL \$releasever
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF

    # Install
    yum install -y telegraf
  fi

  # Configure
  echo "${GREEN}Configuring telegraf${COLOR_RESET}"

  mv /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.bckup
  sed -e 's~http://localhost:8086~'"${influxdb_server_address}"'~g
          s~influxdb_password~'"${influxdb_password}"'~g' telegraf/telegraf.conf > /etc/telegraf/telegraf.conf

  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}telegraf post install steps${COLOR_RESET}"

    # Enable and start service
    systemctl start telegraf && systemctl enable telegraf
  fi
}

# Filebeat - centos
setup_filebeat_centos() {

  echo "${GREEN}Setting up telegraf${COLOR_RESET}"

  ## Download
  curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.4.0-x86_64.rpm

  ## Install
  rpm -vi filebeat-7.4.0-x86_64.rpm

  echo "${GREEN}Configuring filebeat${COLOR_RESET}"

  ## Configure
  mv /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bckup
  sed -e 's~localhost:5044~'"${logstash_server_address}"'~g
        s~logs_path~'"${filebeat_logs_paths}"'~g' filebeat/filebeat.yml > /etc/filebeat/filebeat.yml

  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}Filebeat post install steps${COLOR_RESET}"
    systemctl start filebeat && systemctl enable filebeat
  fi
}

# Telegraf - ubuntu
setup_telegraf_ubuntu() {

  echo "${GREEN}Setting up telegraf${COLOR_RESET}"

  # Not skipping setup
  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}Installing telegraf${COLOR_RESET}"

    local distro=$(echo ${ID} | tr '[:upper:]' '[:lower:]')

    #  Add the InfluxData repository
    curl -sL https://repos.influxdata.com/influxdb.key | sudo apt-key add -
    . /etc/lsb-release
    echo 'deb https://repos.influxdata.com/'"${distro}" ${DISTRIB_CODENAME}' stable' | tee /etc/apt/sources.list.d/influxdb.list

    # Install
    apt-get update && apt-get install telegraf
  fi

  # Configure
  echo "${GREEN}Configuring telegraf${COLOR_RESET}"

  mv /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.bckup
  sed -e 's~http://localhost:8086~'"${influxdb_server_address}"'~g
          s~influxdb_password~'"${influxdb_password}"'~g' telegraf/telegraf.conf > /etc/telegraf/telegraf.conf

  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}telegraf post install steps${COLOR_RESET}"
    systemctl start telegraf && systemctl enable telegraf  && systemctl restart telegraf
  fi
}

# Filebeat - ubuntu
setup_filebeat_ubuntu() {

  echo "${GREEN}Setting up filebeat${COLOR_RESET}"

  ## Download
  curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.4.0-amd64.deb
  ## Install
  sudo dpkg -i filebeat-7.4.0-amd64.deb

  echo "${GREEN}Configuring filebeat${COLOR_RESET}"

  ## Configure
  mv /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bckup
  sed -e 's~localhost:5044~'"${logstash_server_address}"'~g
        s~logs_path~'"${filebeat_logs_paths}"'~g' filebeat/filebeat.yml > /etc/filebeat/filebeat.yml

  if [ "${skip_setup}" != "true" ]; then
    echo "${GREEN}Filebeat post install steps${COLOR_RESET}"
    systemctl start filebeat && systemctl enable filebeat  && systemctl restart filebeat
  fi
}

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

# Determine distro
. /etc/os-release
echo "${YELLOW}Running setup for... ${GREEN}${ID}${COLOR_RESET}"
setup_run=false
if [ "${ID}" = "centos" ]; then
  setup_run=true
  setup_telegraf_centos
  setup_filebeat_centos
fi

if [ "${ID}" = "ubuntu" ]; then
  setup_run=true
  setup_telegraf_ubuntu
  setup_filebeat_ubuntu
fi

if [ "${setup_run}" = false ]; then
  echo "${RED}${ID} is currently unsupported${COLOR_RESET}"
  exit 1
fi


echo "${GREEN}All dependencies installed${COLOR_RESET}"

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
