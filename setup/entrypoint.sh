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

# check for root execution
if [ "$(id -u)" -ne 0 ]; then
    echo "you must run this script as root"
    exit 1
fi

# install dialog if it's not installed
if ! command -v dialog &>/dev/null; then
    apt-get install -y dialog
fi

# created password for cursion user using dialog
USER_PASS=$(dialog --title "Password" --clear --insecure --passwordbox "create a password for the cursion user" 8 40 2>&1 >/dev/tty)
USER_PASS_CONFIRM=$(dialog --title "Password Confirmation" --clear --insecure --passwordbox "confirm the password" 8 40 2>&1 >/dev/tty)

# matching password
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    echo "passwords do not match. exiting..."
    exit 1
fi
echo "cursion password created!"

# Create user and set password
if ! id -u $USR &>/dev/null; then
    useradd -m $USR
    echo "$USR:$USER_PASS" | chpasswd
    usermod -aG sudo $USR
else
    echo "user $USR already exists"
fi




# --- 1. Install sys dependencies --- #
echo 'installing system dependencies'
 
# install dependencies
apt-get update && apt-get install -y ca-certificates python3 python3-pip python3-venv

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
sudo -u $USR newgrp docker

# reset default vars after `newgrp`
USR="cursion"
DIR="app"
REPOSITORY="https://github.com/cursion-dev/selfhost.git"




# --- 2. Get self-hosted repo --- #
echo 'downloading Cursion Self-Hosted repo'

# create cursion dir
mkdir -p /home/$USR/$DIR
chown -R $USR:$USR /home/$USR/$DIR
chmod -R 755 /home/$USR/$DIR
cd /home/$USR/$DIR

# clone self-hosted repo
if [ -d "./selfhost" ]; then
    echo "repo already exists, pulling the latest changes..."
    cd selfhost
    git pull
else
    echo "Cloning the repository..."
    git clone $REPOSITORY
    cd selfhost
fi




# --- 3. Run python installer to get User inputs --- #
echo 'setting up installer'

# Setup & activate python venv
python3 -m venv /home/$USR/app/selfhost/appenv
source /home/$USR/app/selfhost/appenv/bin/activate

# Install requirements (allow --break-system-packages if needed)
pip3 install -r ./setup/installer/requirements.txt --break-system-packages

echo 'starting installer script'

# Run installer.py setup script
PYTHONUNBUFFERED=1 /home/$USR/app/selfhost/appenv/bin/python ./setup/installer/installer.py </dev/tty

# Deactivate venv if active
if [[ "$VIRTUAL_ENV" != "" ]]; then
    deactivate
fi




# --- 4. Spin up Cursion using docker compose --- #
echo 'starting up services with docker'

# adding extra permissions for docker cmds
echo "%docker ALL=(ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers

# start up services
sudo -u $USR docker compose -f docker-compose.yml up -d

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




