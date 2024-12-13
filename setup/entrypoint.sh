#!/bin/bash

### - Entry point for Self-Hosted Cursion - ###
# This script will download the self-hosted repo 
# from GitHub and spin up the application using Docker.




# --- 0. Setup dependencies and environment --- #
echo 'setting up host environment' &&

# update system
apt update &&

# set default vars
USER="cursion"
USER_PASS="cursion1234!"
DIR="cursion"
REPOSITORY="https://github.com/cursion-dev/selfhost.git"

# update password if requested
if [[ $1 != $USER_PASS ]]
    then
        USER_PASS=$1 &&
        echo 'updated USER_PASS'
fi

# create new user 
useradd -m $USER && echo $USER_PASS | passwd --stdin $USER &&
usermod -aG sudo $USER &&
su $USER &&

# check and install git
git --version || apt-get install git -y &&

# check and install python3
python3 --version || apt-get install python3 python3-venv -y &&

# check and install python3-venv
python3-venv --version || apt-get install python3-venv -y &&

# check and install docker
docker --version || { 
    # uninstall old pkgs
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg; done &&
    
    # download new
    apt-get install ca-certificates && 
    install -m 0755 -d /etc/apt/keyrings && 
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
} &&

# switch to cursion user
echo $USER_PASS | sudo -S usermod -aG docker $USER && 
newgrp docker &&




# --- 1. Get self-hosted repo --- #
echo 'downloading Cursion Self-Hosted repo' &&

# create cursion dir
mkdir $DIR && cd $DIR &&

# clone self-hosted repo
git clone $REPOSITORY &&

# setup & activate python venv
python3 -m venv appenv && source appenv/bin/activate &&

# install requirements
python3 -m pip install -r ./setup/installer/requirements.txt &&




# --- 2. Run python installer to get User inputs --- #
echo 'starting up installer' &&

# init installer.py setup script
python3 ./setup/installer/installer.py &&

# deactivate venv
deactivate && 




# --- 3. Spin up Cursion using docker compose --- #
echo 'starting up services with docker' &&

# start up services
docker compose -f docker-compose.yml up -d &&

# wait 60 seconds for services to initialize
echo 'waiting for services to finish initializing...' &&

i=0
progress='####################' # 20 long
while [[ $i -le 10 ]]; do
    echo -ne "${progress:0:$((i*2))}  ($((i*10))%)\r"
    sleep 6
    ((i++))
done
echo -e "\n"





# end script and display access directions
source ./env/.server.env && 
echo 'Cursion should be up and running!' && 
echo 'Access the Client App here -> ${CLIENT_URL_ROOT}/login' && 
echo 'Access the Server Admin Dashboard here -> ${API_URL_ROOT}/admin' && 
echo 'Use your admin credentials to login:  ${ADMIN_USER}  |  ${ADMIN_PASS}' &&

# exit scipt
exit 0




