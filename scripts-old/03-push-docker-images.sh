#!/bin/bash

# Variables
acrName="<acr-name>"
imageName="syntheticapi"
tag="latest"

# Login to ACR
az acr login --name ${acrName,,} 

# Retrieve ACR login server. Each container image needs to be tagged with the loginServer name of the registry. 
echo "Logging to [$acrName] Azure Container Registry..."
loginServer=$(az acr show --name $acrName --query loginServer --output tsv)

# Tag the local image with the loginServer of ACR
docker tag $imageName:$tag $loginServer/$imageName:$tag

# Push local container image to ACR
docker push $loginServer/$imageName:$tag

# Show the repository
echo "This is the [$imageName:$tag] container image in the [$acrName] Azure Container Registry:"
az acr repository show --name $acrName \
                       --image $imageName:$tag 