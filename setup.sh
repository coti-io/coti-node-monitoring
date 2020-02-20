#!/bin/sh

# For output readability
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
COLOR_RESET=$(tput sgr0)

# Install docker on Centos
install_docker_centos() {
  echo "${YELLOW}Starting to install Docker${COLOR_RESET}"

  yum update -y

  yum install -y yum-utils device-mapper-persistent-data lvm2

  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

  yum install -y docker-ce

  systemctl enable docker.service

  systemctl start docker.service

  echo "${GREEN}docker installed${COLOR_RESET}"
}

# Install docker on Ubuntu
install_docker_ubuntu() {
  echo "${YELLOW}Starting to install Docker${COLOR_RESET}"

  apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

  add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

  apt-get -y update

  apt-get -y install docker-ce docker-ce-cli containerd.io

  echo "${GREEN}docker installed${COLOR_RESET}"
}

# Install Compose on both centos and ubuntu
install_compose() {
  echo "${YELLOW}Starting to install compose${COLOR_RESET}"

  curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

  chmod +x /usr/local/bin/docker-compose
  docker-compose --version

  echo "${GREEN}compose installed${COLOR_RESET}"
}

# Install jq - Centos
install_jq_centos() {
  echo "${YELLOW}Starting to install jq${COLOR_RESET}"
  yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  yum install -y jq
  echo "${GREEN}jq installed${COLOR_RESET}"
}

#Install jq - Ubuntu
install_jq_ubuntu() {
  echo "${YELLOW}Starting to install jq${COLOR_RESET}"
  apt-get -y install jq
  echo "${GREEN}jq installed${COLOR_RESET}"
}

# Determine distro
. /etc/os-release
echo "${YELLOW}Running setup for... ${GREEN}${ID}${COLOR_RESET}"
setup_run=false
if [ "${ID}" = "centos" ]; then
  setup_run=true
  install_docker_centos
  install_compose
  install_jq_centos
fi

if [ "${ID}" = "ubuntu" ]; then
  setup_run=true
  install_docker_ubuntu
  install_compose
  install_jq_ubuntu
fi

if [ "${setup_run}" = false ]; then
  echo "${RED}${ID} is currently unsupported${COLOR_RESET}"
  exit 1
fi


echo "${GREEN}All dependencies installed${COLOR_RESET}"
echo "${YELLOW}If you wish to run docker as a non root user (and you probably want), execute this command:${COLOR_RESET}"
echo "sudo usermod -aG docker \$USER"
echo "${YELLOW}and logout (and login) from this session${COLOR_RESET}"
