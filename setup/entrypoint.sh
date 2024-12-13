#!/bin/bash

### - Entry point for Self-Hosted Cursion - ###
# This script will download the self-hosted repo 
# from GitHub and spin up the application using Docker.



set -e  # Exit immediately on command failure
set -u  # Treat unset variables as errors



# --- 0. Setup environment --- #
echo 'setting up host environment'

# set default vars
USR="cursion"
USER_PASS=""
DIR="cursion"
REPOSITORY="https://github.com/cursion-dev/selfhost.git"

# check for 
if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root"
    exit 1
fi

# created password for cursion user
read -s -p "please create a password for the cursion user: " USER_PASS
echo
read -s -p "please confirm the password: " USER_PASS_CONFIRM
echo
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    echo "passwords do not match. Exiting..."
    exit 1
fi
echo "cursion password created!"

# Create user and set password
if ! id -u $USR &>/dev/null; then
    useradd -m $USR
    echo "$USR:$USER_PASS" | chpasswd
    usermod -aG sudo $USR
else
    echo "User $USR already exists"
fi

# running remaining script as $USR
if [ "$(id -u)" -eq 0 ]; then
    sudo -u $USR bash "$0" "$@"
    exit
fi




# --- 1. Install sys dependencies --- #

echo 'installing system dependencies'
 
# install dependencies
apt-get updaten && apt-get install -y ca-certificates python3 python3-pip python3-venv

# check and install docker
set +e
docker --version || { 
    # uninstall old pkgs
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg -y; done
    
    # download new
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    
    # install new docker
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
}
set -e

# setting docker permissions
sudo usermod -aG docker $USR
newgrp docker




# --- 2. Get self-hosted repo --- #
echo 'downloading Cursion Self-Hosted repo'

# create cursion dir
mkdir -p $DIR && cd $DIR

# clone self-hosted repo
if [ -d "./selfhost" ]; then
    echo "Repository already exists. Pulling the latest changes..."
    cd selfhost
    git pull
else
    echo "Cloning the repository..."
    git clone $REPOSITORY
    cd selfhost
fi




# --- 3. Run python installer to get User inputs --- #
echo 'setting up installer'

# setup & activate python venv
python3 -m venv appenv
source appenv/bin/activate

# install requirements
pip3 install -r ./setup/installer/requirements.txt

echo 'starting installer script'

# init installer.py setup script
PYTHONUNBUFFERED=1 python3 -i ./setup/installer/installer.py </dev/tty

# deactivate venv
deactivate




# --- 4. Spin up Cursion using docker compose --- #
echo 'starting up services with docker'

# start up services
sudo docker compose -f docker-compose.yml up -d

# wait 60 seconds for services to initialize
echo 'waiting for services to finish initializing...'

i=0
progress='####################' # 20 long
while [[ $i -le 10 ]]; do
    echo -ne "${progress:0:$((i*2))}  ($((i*10))%)\r"
    sleep 6
    ((i++))
done
echo -e "\n"




# end script and display access directions
export $(grep -v '^#' ./env/.server.env | xargs)
echo "Cursion should be up and running!" && 
echo "Access the Client App here -> ${CLIENT_URL_ROOT}/login" 
echo "Access the Server Admin Dashboard here -> ${API_URL_ROOT}/admin" 
echo "Use your admin credentials to login:  ${ADMIN_USER}  |  ${ADMIN_PASS}"

# exit scipt
exit 0




