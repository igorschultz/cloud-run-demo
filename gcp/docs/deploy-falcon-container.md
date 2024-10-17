# Falcon Container Sensor

# Configure GCP Credentials to Conformity Bot Access

## Overview

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

This tutorial will guide you to the process of deploying Falcon Container Security on a sample Cloud Run Service App. You can use the Dockerfile present on this repo to create your demo Cloud Run Service App or using on of your own services
--------------------------------

## Step 1: Project setup

1. Select the project from the drop-down list.
2. Copy and execute the script below in the Cloud Shell to complete the project setup.

<walkthrough-project-setup></walkthrough-project-setup>

```sh
gcloud config set project <walkthrough-project-id/>
```

--------------------------------

### Step 2 (OPTIONAL): Create a new Cloud Run Service app using the sample vulapp image

In order to create the sample app you have to create a new Artifact Registry, pull the image, push it to the new registry and set up the cloud run to use this new image for your new service.

1. Create an Artifact Repository replacing the value of REPOSITORY_NAME and LOCATION

```sh
gcloud artifacts repositories create "<REPOSITORY_NAME>" \
    --repository-format=docker \
    --location="<LOCATION>" \
    --description="My Demo repository" \
    --mode=standard
```

2. Authenticating to your repository

Replace the name LOCATION by your registry location

```sh
export PROJECT_ID=$(gcloud config get-value project)
export REPOSITORY=$(gcloud artifacts repositories list --sort-by=creationTime --limit=1 --format="value(name)")
export LOCATION=$(gcloud artifacts repositories list --sort-by=creationTime --limit=1 --format="value(LOCATION)")
gcloud auth configure-docker $LOCATION-docker.pkg.dev
```

Pull the vulapp container image

```sh
docker pull quay.io/crowdstrike/vulnapp
```

Tag your local image with the values of your Artifact Registry

```sh
docker tag quay.io/crowdstrike/vulnapp $LOCATION-docker.pkg.dev/$PROJECT_ID/$REPOSITORY/vulapp:unpatched
```

Push the image to your new repository

```sh
docker push $LOCATION-docker.pkg.dev/$PROJECT_ID/$REPOSITORY/vulapp:unpatched
```

--------------------------------

### Step 3: Choose of your current services to deploy Falcon Container Sensor

1. Select of your running Cloud Run services. To check your running Cloud Run services run the following command:

```sh
gcloud run services list
```

2. Specify the following fields and execute the deployment script in the Cloud Shell:

1. **Falcon Client ID:** Specify the CrowdStrike API Key ID.
1. **Falcon Cliente Secret** Specify the CrowdStrike API Secret.
1. **Service Name:** Specify the existing cloud run service name that you wish to protect.
1. **Location:** Specify the location of your service.

Specify the following fields and execute the deployment script in the Cloud Shell:

```sh
./cloud-run-patching.sh -f <FALCON_CLIENT_ID> -c <FALCON_CLIENTE_SECRET> -s <SERVICE_NAME> -r <LOCATION>
```

--------------------------------

### Step 4: Re-deploy your application with the new image

The new "patched" image has been created and sent to your registry


## Cleanup Environment

# List Cloud One Conformity Service Accounts

gcloud iam service-accounts list --filter=cloud-one-conformity-bot
