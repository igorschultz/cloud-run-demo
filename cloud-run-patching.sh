#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 -r <location> -u <falcon-client-id> -s <falcon-client-secret>"
    echo "  -r: GCP region (required)"
    echo "  -u: CrowdStrike falcon client ID (required)"
    echo "  -s: CrowdStrike falcon client secret (required)"
    echo "  -t: CrowdStrike falcon tag (required)"
    exit 1
}

# Check if JQ is installed.
if ! command -v jq &> /dev/null; then
    echo "JQ could not be found."
    exit 1
fi

# Check if curl is installed.
if ! command -v curl &> /dev/null; then
    echo "curl could not be found."
    exit 1
fi

# Check if docker is installed.
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install Docker and try again."
    exit 1
fi

# Check if docker daemon is running
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Function to handle errors
handle_error() {
    local error_message="$1"
    echo "Error occurred: $error_message" >&2
    exit 1
}

# Function to check if a repository exists
check_repository_exists() {
    gcloud artifacts repositories list \
    --filter="name ~ ^$repository_name$" \
    --location=$region >/dev/null 2>&1
    return $?
}

# Function to create a repository for falcon container sensor
create_repository() {
    gcloud artifacts repositories create "$repository_name" \
    --repository-format=docker \
    --location=$region \
    --description="Falcon Container Sensor repository" \
    --mode=standard  >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Repository $1 created successfully."
    else
        echo "Failed to create repository $1."
        exit 1
    fi
}

# Parse command line arguments
while getopts ":r:u:s:t:" opt; do
    case $opt in
        r) region="$OPTARG" ;;
        u) falcon_client_id="$OPTARG" ;;
        s) falcon_client_secret="$OPTARG" ;;
        t) falcon_tag="$OPTARG" ;;
        \?) echo "Invalid option -$OPTARG" >&2; usage ;;
    esac
done

# Initialize variables
region="$region"

echo ""
echo "Listing Google Cloud Run services"
echo ""

# Main code
{

  # Get list of Google Cloud services
  services=$(gcloud run services list --platform managed --region=$region --filter="spec.template.metadata.annotations['run.googleapis.com/execution-environment']=gen2" --format="value(SERVICE)")


  # Display list of services
  echo "Available Cloud Run services:"
  echo ""
  for service in $services; do
      service_name=$(basename "$service")
      echo "- $service_name"
  done

  echo ""

  # Prompt user for service selection
  read -p "Enter the name of the service you want to patch: " selected_service

  # Grab container image from service 
  echo "Assessing service $service_name"
  export images=$(gcloud run services describe $service_name --region $region --format="yaml" | grep 'image:' | awk '{print $3}')
  #export container=$(gcloud run services describe $service_name --region $region --format="json" | jq '.spec.template.spec.containers[].name')

  # Variables
  export FALCON_TAG=$falcon_tag
  export FALCON_CLIENT_ID=$falcon_client_id
  export FALCON_CLIENT_SECRET=$falcon_client_secret
  export FALCON_CID=$(bash <(curl -Ls https://github.com/CrowdStrike/falcon-scripts/releases/latest/download/falcon-container-sensor-pull.sh) -t falcon-container --get-cid)
  export LATESTSENSOR=$(bash <(curl -Ls https://github.com/CrowdStrike/falcon-scripts/releases/latest/download/falcon-container-sensor-pull.sh) -t falcon-container | tail -1)
  export FALCON_IMAGE_TAG=$(echo $LATESTSENSOR | cut -d':' -f 2)
  export PROJECT_ID=$(gcloud config get-value project)

  
  echo ""
  read -p "Do you have an existing GCP GAR repository for Falcon Container Sensor (yes/no)? " has_repo

  if [ "$has_repo" = "yes" ] || [ "$has_repo" = "y" ]|| [ "$has_repo" = "Yes" ] || [ "$has_repo" = "Y" ]; then

    # Describe repository
    gar_repositories_list=$(gcloud artifacts repositories list --location=$region --format="value(REPOSITORY)")


    # Get the latest version of each task definition family
    for repo in $gar_repositories_list; do
        gar_repositories+=("$repo")
    done

    # Display task definitions with numbers, one per line
    echo "Available GAR repositories:"
    for i in "${!gar_repositories[@]}"; do
        echo "$((i+1)). ${gar_repositories[$i]}"
    done
    echo ""
    # Ask user to select falcon container sensor GAR repo
    read -p "Enter the number of the GAR repository used for Falcon Container Sensor: " selection

    # Validate user input
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#gar_repositories[@]}" ]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    # Get selected task definition
    repo_name="${gar_repositories[$((selection-1))]}"  

  else
    repo_name="falcon-sensor/falcon-container"
    echo "Checking if repository $repo_name exists..."
    if check_repository_exists "$repo_name"; then
        echo "Repository $repo_name already exists."
    else
        echo "Creating repository $repo_name..."
        create_repository "$repo_name"
    fi
  fi


  REPO_URI=$(gcloud artifacts repositories describe $repo_name --location=$region --format="value(registryUri)")
  REPO_PACKAGE=$(gcloud artifacts packages list --repository=$repo_name --location=$region --format="value(PACKAGE)")
  FALCON_URI=$REPO_URI/$REPO_PACKAGE

  # Log in to the private GCR repository using gcloud CLI.
  echo "Authenticating at your GCP Artifact Registry"
  gcloud auth configure-docker $region-docker.pkg.dev


  # tag and push container sensor to your falcon registry
  echo "Pushing latest falcon container sensor image to $repo_name"
  docker tag "$LATESTSENSOR" "$FALCON_URI":"$FALCON_IMAGE_TAG"
  docker push "$FALCON_URI":"$FALCON_IMAGE_TAG"

  ARCH=$(uname -m)
  for image in $images; do
    echo "Pulling image $image locally to start the patching process"
    pull_image=$(docker pull $image)
    IMAGE_REPO=$(echo $image | cut -d'@' -f1 )
    IMAGE_TAG=$(echo $image | cut -d':' -f 2 )
    if [ "$ARCH" == "arm64" ]; then
        docker run --platform linux/amd64 --user 0:0 \
          -v ${HOME}/.docker/config.json:/root/.docker/config.json \
          -v /var/run/docker.sock:/var/run/docker.sock \
          --rm "$FALCON_URI":"$FALCON_IMAGE_TAG" \
          falconutil patch-image \
          --cid $FALCON_CID \
          --falcon-image-uri "$FALCON_URI":"$FALCON_IMAGE_TAG" \
          --source-image-uri "$image" \
          --target-image-uri "$IMAGE_REPO":patched \
          --image-pull-policy IfNotPresent \
          --falconctl-opts "--tags=$FALCON_TAG" \
          --cloud-service CLOUDRUN
    else
        docker run --platform linux --user 0:0 \
          -v ${HOME}/.docker/config.json:/root/.docker/config.json \
          -v /var/run/docker.sock:/var/run/docker.sock \
          --rm "$FALCON_URI":"$FALCON_IMAGE_TAG" \
          falconutil patch-image \
          --cid $FALCON_CID \
          --falcon-image-uri "$FALCON_URI":"$FALCON_IMAGE_TAG" \
          --source-image-uri "$image" \
          --target-image-uri "$IMAGE_REPO":patched \
          --image-pull-policy IfNotPresent \
          --falconctl-opts "--tags=$FALCON_TAG" \
          --cloud-service CLOUDRUN
    fi

    echo ""
    echo "Pushing patched image "$IMAGE_REPO":patched to GCP"

    # Push new patched image to registry
    PATCHED_IMAGE="$IMAGE_REPO":patched
    push_images=$(docker push "$PATCHED_IMAGE")

  done

  # Update the Cloud Run Service with the new image 
  # gcloud run services update $SERVICE_NAME --image=$PACTHED_IMAGE --region=$SERVICE_GCP_REGION --execution-environment=gen2
  # gcloud run deploy todoimg --container todoimg-1 --image=$PACTHED_IMAGE --port='8080' --container falcon-container-sensor --image=$FALCON_IMAGE_URI --execution-environment=gen2 --region=$SERVICE_GCP_REGION

} 