#!/bin/sh

# For eliminating warnings when putting docker-compose down. Seeting to other than a defult empty string is harmless
export es_java_opts=""

# Read args / input parameters
read_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --logstash_image=*)
        logstash_image="${1#*=}"
        ;;
     *)

      # Exit with a message
      retval_checks 1 "***************************\n* Error: Invalid argument.*\n***************************\n"
    esac
    shift
  done
}

# Check that grafana was started in compose as a service. If yes, do compose down
# for removing all services
do_docker_compose_down() {
  if [ -z `docker-compose ps -q grafana` ] || [ -z `docker ps -q --no-trunc | grep $(docker-compose ps -q grafana)` ]; then
    echo "Service container is NOT running."
  else
    echo "Service container IS running, doing compose down"
    docker-compose down --rmi all
  fi
}


do_volumes_prune() {
  if [ -z `docker volume ls -q | grep grafana` ] ; then
    echo "Volume NOT exists"
  else
    echo "Volume EXISTS, prune volumes"
    docker volume prune --force
  fi
}

# This is a naiv check, but good enough to start with
# In case no coti logstash image (incl. tag) can be found, it means that
# we have a problem (typo or another user mistake, or an unexpected state of docker)
#
# This should be done as a first check before anything gets actually executed
check_logstash_image_exists() {
  if [ -z `docker images -q "${logstash_image}"` ] ; then
    echo "Error: Logstash image not exists"
    echo "No execution took place"
    echo "Exit"
    exit 1
  fi
}

echo '
 _______              _               _____
|__   __|            (_)             |  __ \
   | | ___  __ _ _ __ _ _ __   __ _  | |  | | _____      ___ __
   | |/ _ \/ _` | `__| | `_ \ / _` | | |  | |/ _ \ \ /\ / / `_ \
   | |  __/ (_| | |  | | | | | (_| | | |__| | (_) \ V  V /| | | |
   |_|\___|\__,_|_|  |_|_| |_|\__, | |_____/ \___/ \_/\_/ |_| |_|
                               __/ |
                              |___/

          '

# Read the command line arguments
read_args "$@"

# Before we do anything, check user input
check_logstash_image_exists

# Is used by compose and referred to in docker-compose.yml
export logstash_image_name="${logstash_image}"

# compose down
do_docker_compose_down

# Prune volumes
do_volumes_prune

# Finish with system prune
echo "Starting docker system prune"
docker system prune --all --force


echo '
 _______                 _                        _____                      _      _           _
|__   __|               | |                      / ____|                    | |    | |         | |
   | | ___  __ _ _ __ __| | _____      ___ __   | |     ___  _ __ ___  _ __ | | ___| |_ ___  __| |
   | |/ _ \/ _` | `__/ _` |/ _ \ \ /\ / / `_ \  | |    / _ \| `_ ` _ \| `_ \| |/ _ \ __/ _ \/ _` |
   | |  __/ (_| | | | (_| | (_) \ V  V /| | | | | |___| (_) | | | | | | |_) | |  __/ ||  __/ (_| |
   |_|\___|\__,_|_|  \__,_|\___/ \_/\_/ |_| |_|  \_____\___/|_| |_| |_| .__/|_|\___|\__\___|\__,_|
                                                                      | |
                                                                      |_|
          '