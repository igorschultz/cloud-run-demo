# Deploy Falcon Container sensor for Linux to Google Cloud Run - How to inject Falcon Container Sensor into your running services

## Prerequisites

1. **Install supporting tools**
   - [Google Cloud SDK](https://cloud.google.com/sdk/docs/install-sdk)
   - CrowdStrike API client ID with the following Scopes: [US-1](https://falcon.crowdstrike.com/api-clients-and-keys), [US-2](https://falcon.us-2.crowdstrike.com/api-clients-and-keys), [EU-1](https://falcon.eu-1.crowdstrike.com/api-clients-and-keys)
     - Falcon Images Download: Read
     - Sensor Download: Read

## Installation

### Patch a running service with Falcon Container Sensor

1. Visit [![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Figorschultz%2Fcloud-run-demo.git&cloudshell_workspace=gcp&cloudshell_tutorial=docs/deploy-falcon-container.md)
