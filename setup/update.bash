#!/bin/bash

### - Update Script for Self-Hosted Cursion - ###
# This script will stop, update, re-deploy, and perform 
# cleanup for the Cursion application using Docker.




set -u # Treat unset variables as errors



# Args definitions
# 1. sys_pass  ($1)



# --- 0. Request or use system password --- #
echo "Requesting system password (for sudo operations)..."

USR="cursion"
SYS_PASS="${1:-}"

if [ -z "$SYS_PASS" ]; then
    SYS_PASS=$(dialog --title "Password" --clear --insecure --passwordbox "Enter the system password for the cursion user" 8 40 2>&1 >/dev/tty)
fi




# --- 1. Stop running containers --- #
echo "Stopping running containers..."

# Navigate to home/user/selfhost directory
cd /home/$USR/selfhost

# Stop all running containers in the docker-compose stack
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml down




# --- 2. Remove outdated images --- #
echo 'Removing outdated Docker images...'

# Remove the cursiondev client and server images & volumes
echo "$SYS_PASS" | sudo -u $USR -S docker rmi -f cursiondev/client:latest cursiondev/server:latest
echo "$SYS_PASS" | sudo -u $USR -S docker rm -f cursion_celery cursion_beat cursion_server




# --- 3. Re-pull and spin up the containers again --- #
echo "Pulling latest images and spinning up the deployment..."

# Re-pull the latest images and start the containers
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml pull
echo "$SYS_PASS" | sudo -u $USR -S docker compose -f docker-compose.yml up -d




# --- 4. Wait until containers are fully up and running --- #

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
        echo -e "\n[!] Timeout reached. Proceeding anyway."
        break
    fi

    # Sleep for 1 second before retrying
    sleep 1
done




# --- 5. Garbage collection --- #
echo "Performing cleanup..."

# Remove dangling/unused resources
docker image prune -f
docker network prune -f
docker container prune -f
docker volume prune -f

echo "[✓] Cleanup finished!"




# --- 6. Final message --- #
echo "[✓] Update finished!"
echo "Cursion is now running with the latest stable version."

# Exit script
exit 0