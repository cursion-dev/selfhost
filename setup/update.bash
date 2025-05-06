#!/bin/bash

### - Update Script for Self-Hosted Cursion - ###
# This script will stop, update, re-deploy, and preform 
# cleanup for the Cursion application using Docker.




set -e # Exit immediately on command failure
set -u # Treat unset variables as errors



# Args definitions
# 1. sys_pass  ($1)



# --- 0. Request or use system password --- #
echo 'Requesting system password (for sudo operations)...'

USR="cursion"
SYS_PASS="${1:-}"

if [ -z "$SYS_PASS" ]; then
    SYS_PASS=$(dialog --title "Password" --clear --insecure --passwordbox "Enter system password for sudo user $USR" 8 40 2>&1 >/dev/tty)
fi




# --- 1. Stop running containers --- #
echo 'Stopping running containers...'

# Navigate to home/user/selfhost directory
cd /home/$USR/selfhost

# Stop all running containers in the docker-compose stack
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml down




# --- 2. Remove outdated images --- #
echo 'Removing outdated Docker images...'

# Remove the cursiondev client and server images
echo "$SYS_PASS" | sudo -u $USR -S docker rmi -f cursiondev/client:latest cursiondev/server:latest




# --- 3. Re-pull and spin up the containers again --- #
echo 'Re-pulling latest images and spinning up the deployment...'

# Re-pull the latest images and start the containers
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml pull
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml up -d




# --- 4. Wait until containers are fully up and running --- #
echo "Waiting for API endpoint to be ready..."

# Set a timeout limit to prevent hanging indefinitely (e.g., 10 minutes)
TIMEOUT=600
START_TIME=$(date +%s)

# Wait for API to return status 200
source ./env/.server.env

while true; do
    # Send a GET request to the /celery endpoint
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL_ROOT}/v1/ops/metrics/celery")

    # If the response is 200, the containers are up and running
    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "\nAPI is up and containers are running!"
        break
    fi

    # Check if we've exceeded the timeout
    ELAPSED_TIME=$(($(date +%s) - $START_TIME))
    PERCENTAGE=$((ELAPSED_TIME * 100 / TIMEOUT))

    # Display progress bar
    PROGRESS_BAR=$(printf "%-${PERCENTAGE}s" "#" | tr ' ' '#')
    SPACES=$(printf "%-$((100 - PERCENTAGE))s")
    echo -ne "\r[${PROGRESS_BAR}${SPACES}] ${PERCENTAGE}%"

    # Check if the timeout has been reached
    if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
        echo -e "\nTimeout reached. Proceeding anyway."
        break
    fi

    # Sleep for 10 seconds before retrying
    sleep 10
done




# --- 5. Garbage collection --- #
echo 'Performing cleanup...'

# Remove dangling/unused resources
docker image prune -f
docker network prune -f
docker container prune -f
docker volume prune -f

echo 'Cleanup finished!'




# --- Final message --- #
echo 'Update completed! Cursion is now running with the latest images.'

# Exit script
exit 0