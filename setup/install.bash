#!/bin/bash

### - Install Script for Self-Hosted Cursion - ###
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
# 7. gpt_key       ($7)



# --- 0. Setup environment --- #
echo 'Setting up host environment'

# Set default vars
USR="cursion"
SYS_PASS="${1:-}"
LICENSE_KEY="${2:-}"
ADMIN_EMAIL="${3:-}"
ADMIN_PASS="${4:-}"
SERVER_DOMAIN="${5:-}"
CLIENT_DOMAIN="${6:-}"
GPT_KEY="${7:-}"

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
if [ -z "$SYS_PASS" ]; then
    SYS_PASS=$(dialog --title "Password" --clear --insecure --passwordbox "Create a password for the cursion user" 8 40 2>&1 >/dev/tty)
    SYS_PASS_CONFIRM=$(dialog --title "Password Confirmation" --clear --insecure --passwordbox "Confirm the password" 8 40 2>&1 >/dev/tty)
else
    SYS_PASS_CONFIRM=$SYS_PASS
fi

# Match password
if [[ "$SYS_PASS" != "$SYS_PASS_CONFIRM" ]]; then
    echo "Passwords do not match. Exiting..."
    exit 1
fi
echo "Cursion password created!"

# Create user and set password
if ! id -u $USR &>/dev/null; then
    useradd -m $USR
    echo "$USR:$SYS_PASS" | chpasswd
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
LICENSE_KEY="${2:-}"
ADMIN_EMAIL="${3:-}"
ADMIN_PASS="${4:-}"
SERVER_DOMAIN="${5:-}"
CLIENT_DOMAIN="${6:-}"
GPT_KEY="${7:-}"




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

# Install Python requirements 
pip3 install \
    --user \
    --break-system-packages \
    --no-warn-script-location \
    --root-user-action=ignore \
    -r ./setup/installer/requirements.txt

echo 'Starting installer script'

# Run installer.py setup script explicitly with Python
python3 ./setup/installer/installer.py \
    --license-key="$LICENSE_KEY" \
    --admin-email="$ADMIN_EMAIL" \
    --admin-pass="$ADMIN_PASS" \
    --server-domain="$SERVER_DOMAIN" \
    --client-domain="$CLIENT_DOMAIN" \
    --gpt-key="$GPT_KEY" -- </dev/tty




# --- 4. Spin up Cursion using Docker Compose --- #
echo 'Starting up services with Docker'

# Add extra permissions for Docker commands
echo "%docker ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers

# pulling images and starting containers
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml pull
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml up -d 




# --- 5. Wait until containers are fully up and running --- #

# Set timeout limit
TIMEOUT=600
START_TIME=$(date +%s)

# Spinner animation setup
SPINNER=('|' '/' '-' '\\')
SPINNER_INDEX=0

# Wait for API to return status 200
source ./env/.server.env

while true; do
    # Send a GET request to the /celery endpoint
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL_ROOT}/v1/ops/metrics/celery")

    # If the response is 200, the containers are up and running
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "\n[✓] API is up and containers are running!"
        break
    fi

    # Check if we've exceeded the timeout
    ELAPSED_TIME=$(($(date +%s) - $START_TIME))

    # Display the spinner and wait for 1 second
    echo -ne "\rWaiting for Cursion to initialize... ${SPINNER[$SPINNER_INDEX]}"

    # Update spinner index
    SPINNER_INDEX=$(( (SPINNER_INDEX + 1) % 4 ))

    # Check if the timeout has been reached
    if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
        echo -e "\nTimeout reached. Proceeding anyway."
        break
    fi

    # Sleep for 1 second before retrying
    sleep 1
done





# --- 6. Garbage collection --- #
echo 'Performing cleanup...'

# Remove dangling/unused resources
docker image prune -f
docker network prune -f
docker container prune -f
docker volume prune -f

echo '[✓] Cleanup finished!'




# --- 7. Display access directions --- #
source ./env/.server.env
echo "[✓] Cursion should now be up and running!"
echo " - Access the Client App here                ➔ ${CLIENT_URL_ROOT}/login"
echo " - Access the Server Admin Dashboard here    ➔ ${API_URL_ROOT}/admin"
echo " - Use your admin credentials to login       ➔ ${ADMIN_USER} | ${ADMIN_PASS}"

# Exit script
exit 0



