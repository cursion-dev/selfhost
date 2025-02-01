#!/bin/bash

### - Entry point for Self-Hosted Cursion - ###
# This script will download the self-hosted repo 
# from GitHub and spin up the application using Docker.




set -e  # Exit immediately on command failure
set -u  # Treat unset variables as errors



# Args definitions
# 1. sys_pass      ($1)
# 2. license_key   ($2)
# 3. admin_email   ($3)
# 4. admin_pass    ($4)
# 5. server_domain ($5)
# 6. client_domain ($6)
# 7. gpt_key       ($7) - optional



# --- 0. Setup environment --- #
echo 'Setting up host environment'

# Set default vars
USR="cursion"

# Check for root execution
if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root"
    exit 1
fi

# Install dialog if it's not installed
if ! command -v dialog &>/dev/null; then
    apt-get install -y dialog
fi

# Create password for cursion user using dialog
# if sys_pass was not give in args
if [ -z "$1" ]; then
    USER_PASS=$(dialog --title "Password" --clear --insecure --passwordbox "Create a password for the cursion user" 8 40 2>&1 >/dev/tty)
    USER_PASS_CONFIRM=$(dialog --title "Password Confirmation" --clear --insecure --passwordbox "Confirm the password" 8 40 2>&1 >/dev/tty)
else
    USER_PASS=$1
    USER_PASS_CONFIRM=$1
fi

# Match password
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    echo "Passwords do not match. Exiting..."
    exit 1
fi
echo "Cursion password created!"

# Create user and set password
if ! id -u $USR &>/dev/null; then
    useradd -m $USR
    echo "$USR:$USER_PASS" | chpasswd
    usermod -aG sudo $USR
else
    echo "User $USR already exists"
fi




# --- 1. Install system dependencies --- #
echo 'Installing system dependencies'

# Install dependencies
apt-get update && apt-get install -y ca-certificates python3 python3-pip python3-venv curl git

# Check and install Docker
if ! command -v docker &>/dev/null; then
    # Remove old Docker packages
    apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc

    # Add Docker repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Add the cursion user to the Docker group
usermod -aG docker $USR

# Reset default vars
USR="cursion"
REPOSITORY="https://github.com/cursion-dev/selfhost.git"




# --- 2. Get self-hosted repo --- #
echo 'Downloading Cursion Self-Hosted repo'

# Create cursion directory
mkdir -p /home/$USR
chown -R $USR:$USR /home/$USR
chmod -R 755 /home/$USR
cd /home/$USR

# Clone self-hosted repo
if [ -d "./selfhost" ]; then
    echo "Repo already exists, pulling the latest changes..."
    cd selfhost
    git pull
else
    echo "Cloning the repository..."
    git clone $REPOSITORY
    cd selfhost
fi




# --- 3. Run python installer to get user inputs --- #
echo 'Setting up installer'

# Install Python requirements (allow --break-system-packages if needed)
pip3 install --user --break-system-packages -r ./setup/installer/requirements.txt

echo 'Starting installer script'

# Run installer.py setup script explicitly with Python
python3 ./setup/installer/installer.py \
    --license-key="$2" \
    --admin-email="$3" \
    --admin-pass="$4" \
    --server-domain="$5" \
    --client-domain="$6" \
    --gpt-key="$7" -- </dev/tty




# --- 4. Spin up Cursion using Docker Compose --- #
echo 'Starting up services with Docker'

# Add extra permissions for Docker commands
echo "%docker ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers

# Start up services
sudo -u $USR docker compose -f docker-compose.yml up --build -d




# --- 5. Display access directions --- #
source ./env/.server.env
echo "Cursion should be up and running in a few minutes!"
echo "Access the Client App here -> ${CLIENT_URL_ROOT}/login"
echo "Access the Server Admin Dashboard here -> ${API_URL_ROOT}/admin"
echo "Use your admin credentials to login:  ${ADMIN_USER}  |  ${ADMIN_PASS}"

# Exit script
exit 0



