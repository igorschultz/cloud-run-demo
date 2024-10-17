#!/bin/bash
set -e

while getopts f:c:s:r: args
do
  case "${args}" in
    f) FALCON_CLIENT_ID=${OPTARG};;
    c) FALCON_CLIENT_SECRET=${OPTARG};;
    s) SERVICE_NAME=${OPTARG};;
    r) SERVICE_GCP_REGION=${OPTARG};;
  esac
done

#FALCON_IMAGE_URI="$5"

# Download the script for pulling the Falcon container sensor.
echo "Pulling Falcon Container Sensor Image..."
curl -sSL -o falcon-container-sensor-pull.sh "https://github.com/CrowdStrike/falcon-scripts/releases/latest/download/falcon-container-sensor-pull.sh"
chmod +x falcon-container-sensor-pull.sh

# Generate an API key in the Falcon UI with "Read" scope for both Images Download API and Sensor Download API.
echo "Falcon Client ID: $FALCON_CLIENT_ID";
echo "Falcon Secret: $FALCON_CLIENT_SECRET";
echo "Service Name: $SERVICE_NAME";
echo "Region: $SERVICE_GCP_REGION";

# Log in to the private GCR repository using gcloud CLI.
echo "Authenticating at your GCP Artifact Registry"
gcloud auth configure-docker $SERVICE_GCP_REGION-docker.pkg.dev

# Use the downloaded script to get your CrowdStrike CID.
export FALCON_CLIENT_ID
export FALCON_CLIENT_SECRET
export FALCON_CID=$(./falcon-container-sensor-pull.sh -t falcon-container --get-cid)

# Specify the private GCR repository where the Falcon container sensor will be stored.
export PRIVATE_REPO=us-central1-docker.pkg.dev/igors-gke-demo/falcon-container-sensor-igors/falcon-sensor

# Get the latest sensor image version and tag it for pushing to the private ECR.
echo "Getting latest version of Falcon Container Sensor Image..."
export LATESTSENSOR=$(./falcon-container-sensor-pull.sh -t falcon-container | tail -1) && echo $LATESTSENSOR
echo "Falcon sensor downloaded on version $LATESTSENSOR"
docker tag "$LATESTSENSOR" "$PRIVATE_REPO":falcon-container-sensor-latest

# Push the tagged Falcon container sensor image to your GCR repository.
export FALCON_IMAGE_URI="$PRIVATE_REPO":falcon-container-sensor-latest
echo "Pushing Falcon Container Sensor Image to your Registry.."
docker push $FALCON_IMAGE_URI

# Grab container image from service 
echo "Assessing service $SERVICE_NAME"
export APP_SOURCE_IMAGE=$(gcloud run services describe $SERVICE_NAME --region $SERVICE_GCP_REGION --format="yaml" | grep 'image:' | awk '{print $3}')
export CONTAINER_NAME=$(gcloud run services describe $SERVICE_NAME --region us-central1 --format="json" | jq '.spec.template.spec.containers[0].name')

# The task definition should be stored locally before patching. Here, the patched version is saved alongside the unpatched one.

OS=$(uname -s)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then ARCH=arm64; fi
ARCHITECTURE="${OS}_${ARCH}"
echo "Patching container $APP_SOURCE_IMAGE"
export PACTHED_IMAGE="${APP_SOURCE_IMAGE%@*}:patched"
if [ "$OS" == "Linux" ] || [ "$OS" == "Darwin" ]; then 
  docker run --platform linux/amd64 --user 0:0 -v ${HOME}/.docker/config.json:/root/.docker/config.json -v /var/run/docker.sock:/var/run/docker.sock --rm $FALCON_IMAGE_URI falconutil patch-image cloudrun --source-image-uri $APP_SOURCE_IMAGE --target-image-uri $PACTHED_IMAGE --falcon-image-uri $FALCON_IMAGE_URI --cid $FALCON_CID --image-pull-policy IfNotPresent --container $CONTAINER_NAME
else
  docker run --platform linux --user 0:0 -v ${HOME}/.docker/config.json:/root/.docker/config.json -v /var/run/docker.sock:/var/run/docker.sock --rm $FALCON_IMAGE_URI falconutil patch-image cloudrun --source-image-uri $APP_SOURCE_IMAGE --target-image-uri $PACTHED_IMAGE --falcon-image-uri $FALCON_IMAGE_URI --cid $FALCON_CID --image-pull-policy IfNotPresent --container $CONTAINER_NAME
# Push the new image to application repository
docker push $PACTHED_IMAGE

# Update the Cloud Run Service with the new image 
# gcloud run services update $SERVICE_NAME --image=$PACTHED_IMAGE --region=$SERVICE_GCP_REGION --execution-environment=gen2
# gcloud run deploy todoimg --container todoimg-1 --image=$PACTHED_IMAGE --port='8080' --container falcon-container-sensor --image=$FALCON_IMAGE_URI --execution-environment=gen2 --region=$SERVICE_GCP_REGION
