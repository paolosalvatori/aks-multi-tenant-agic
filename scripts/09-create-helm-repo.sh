#!/bin/bash
set -u

# Variables
resourceGroupName="HelmRG"
location="westeurope"
storageAccountName="babohelm"
storageAccountSku="Standard_LRS"
containerName="helm"
helmRepoName="babo"
subscriptionName=$(az account show --query name --output tsv)

# Functions
function azureUpload() {
    az storage blob upload --container-name $containerName --file index.yaml --name index.yaml
    az storage blob upload --container-name $containerName --file *.tgz --name *.tgz
}

function helmRepoSetup() {
    echo "Adding index.yaml now"
    helm repo index --url https://$storageAccountName.blob.core.windows.net/helm/ .
    echo "index.yaml added successfully"
    sleep 1
    echo "Now creating helm package for upload"
    helm package $chartPath
    echo "Helm package created successfully"
    sleep 1
    echo "Now uploading index.yaml and helm package to Azure Storage Containter $containerName"
    azureUpload
    echo "Index.yaml and helm package uploaded succesfully"
    echo "Now adding helm repo for local use"
    helm repo add $helmRepoName https://$storageAccountName.blob.core.windows.net/helm/
    sleep 1
    helm repo list | grep "$helmRepoName" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "helm repo added successfully"
    else
        echo "Could not add helm repo. Please check your Helm configuration and try again."
    fi
}

function helmSearch() {
    chart=$1
    echo "Running helm search"
    helm search repo "$helmRepoName/$chart" | grep "$helmRepoName/$chart"
    if [ $? -eq 0 ]; then
        echo "helm search completed successfully"
        echo "Your storage account has been created. Your blob store URL is: $storageAccountUrl"
        echo "You can now use your storage account and created container with Helm charts. Your full Helm chart url is: $helmChartStoreUrl"
    else
        echo "helm search did not complete successfully. please try again."
    fi
}

function helmCreate() {
    echo "Making chart directory"
    mkdir chart-test && cd chart-test
    echo "Creating helm chart"
    helm create myfirstchart
    echo "Linting helm chart"
    helm lint myfirstchart
    chartPath=myfirstchart
    helmRepoSetup
    helmSearch $chartPath
    exit
}

function newHelmChart() {
    while true; do
        read -p "Would you like to create a blank helm chart to get started? y/n " yn
        case $yn in
        [Yy]*) helmCreate ;;
        [Nn]*)
            echo "You will have to create your own helm chart and upload it before you can use your Azure Storage Container as a Helm repo. Your full Azure Storage Container URL is: $helmChartStoreUrl. This prompt will now exit."
            exit
            ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
}

function hasHelmChart() {
    echo "You selected you have a pre-existing Helm chart you would like to use to get started."
    read -p "Please enter the full path of where your Helm Chart is located: " chartPath
    while [ ! -f $chartPath/chart.yaml ]; do
        read -p "Valid Helm chart directory not found. Please enter the full path of where your Helm Chart is located: " chartPath
    done
    cd $chartPath
    echo "[$chartPath] Valid Helm chart directory found."
    cd ..
    helmRepoSetup
    chartName=$(echo $chartPath | sed 's:.*/::')
    helmSearch $chartName
    exit
}

createResourceGroup() {
    local resourceGroupName=$1
    local location=$2

    # Parameters validation
    if [[ -z $resourceGroupName ]]; then
        echo "The resource group name parameter cannot be null"
        exit
    fi

    if [[ -z $location ]]; then
        echo "The location parameter cannot be null"
        exit
    fi

    echo "Checking if [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription..."

    if ! az group show --name "$resourceGroupName" &>/dev/null; then
        echo "No [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription"
        echo "Creating [$resourceGroupName] resource group in the [$subscriptionName] subscription..."

        # Create the resource group
        if az group create --name "$resourceGroupName" --location "$location" 1>/dev/null; then
            echo "[$resourceGroupName] resource group successfully created in the [$subscriptionName] subscription"
        else
            echo "Failed to create [$resourceGroupName] resource group in the [$subscriptionName] subscription"
            exit
        fi
    else
        echo "[$resourceGroupName] resource group already exists in the [$subscriptionName] subscription"
    fi
}

createStorageAccount() {
    local storageAccountName=$1
    local resourceGroupName=$2
    local location=$3
    local storageAccountSku=$4

    # Parameters validation
    if [[ -z $storageAccountName ]]; then
        echo "The storage account name parameter cannot be null"
        exit
    fi

    if [[ -z $resourceGroupName ]]; then
        echo "The resource group name parameter cannot be null"
        exit
    fi

    if [[ -z $location ]]; then
        echo "The location parameter cannot be null"
        exit
    fi

    if [[ -z $storageAccountSku ]]; then
        echo "The storage account sku parameter cannot be null"
        exit
    fi

    echo "Checking if [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription..."
    az storage account show --name $storageAccountName &>/dev/null

    if [[ $? != 0 ]]; then
        echo "No [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription"
        echo "Creating [$storageAccountName] storage account in the [$subscriptionName] subscription..."

        az storage account create \
            --resource-group $resourceGroupName \
            --name $storageAccountName \
            --location $location \
            --sku $storageAccountSku \
            --access-tier Hot \
            --kind BlobStorage \
            --encryption-services blob 1>/dev/null

        # Create the storage account
        if [[ $? == 0 ]]; then
            echo "[$storageAccountName] storage account successfully created in the [$subscriptionName] subscription"
        else
            echo "Failed to create [$storageAccountName] storage account in the [$subscriptionName] subscription"
            exit
        fi
    else
        echo "[$storageAccountName] storage account already exists in the [$subscriptionName] subscription"
    fi
}

getStorageAccountKey() {
    local storageAccountName=$1
    local resourceGroupName=$2

    echo $(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv)
}

createStorageContainer() {
    local containerName=$1
    local storageAccountName=$2
    local resourceGroupName=$3

    # Parameters validation
    if [[ -z $containerName ]]; then
        echo "The container name parameter cannot be null"
        exit
    fi

    if [[ -z $storageAccountName ]]; then
        echo "The storage account name parameter cannot be null"
        exit
    fi

    if [[ -z $resourceGroupName ]]; then
        echo "The resource group name parameter cannot be null"
        exit
    fi

    echo "Retrieving the primary key of the [$storageAccountName] storage account..."
    storageAccountKey=$(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv)

    if [[ -n $storageAccountKey ]]; then
        echo "Primary key of the [$storageAccountName] storage account successfully retrieved"
    else
        echo "Failed to retrieve the primary key of the [$storageAccountName] storage account"
        exit
    fi

    echo "Checking if [$containerName] container actually exists in the [$storageAccountName] storage account..."
    az storage container show \
        --name $containerName \
        --account-name $storageAccountName \
        --account-key $storageAccountKey &>/dev/null

    if [[ $? != 0 ]]; then
        echo "No [$containerName] container actually exists in the [$storageAccountName] storage account"
        echo "Creating [$containerName] container in the [$storageAccountName] storage account..."

        # Create the container
        az storage container create \
            --name $containerName \
            --account-name $storageAccountName \
            --account-key $storageAccountKey \
            --public-access blob 1>/dev/null

        if [[ $? == 0 ]]; then
            echo "[$containerName] container successfully created in the [$storageAccountName] storage account"
        else
            echo "Failed to create [$containerName] container in the [$storageAccountName] storage account"
            exit
        fi
    else
        echo "[$containerName] container already exists in the [$storageAccountName] storage account"
    fi
}

getStorageAccountUrl() {
    local storageAccountName=$1
    local resourceGroupName=$2

    # Parameters validation
    if [[ -z $storageAccountName ]]; then
        echo "The storage account name parameter cannot be null"
        exit
    fi

    if [[ -z $resourceGroupName ]]; then
        echo "The resource group name parameter cannot be null"
        exit
    fi

    echo $(az storage account show \
        --name $storageAccountName \
        --resource-group $resourceGroupName \
        --query "primaryEndpoints.blob" \
        --output tsv)
}

# Create resource group
createResourceGroup $resourceGroupName $location

# Create storage account
createStorageAccount $storageAccountName $resourceGroupName $location $storageAccountSku

# Create container
createStorageContainer $containerName $storageAccountName $resourceGroupName

# provide blob url to user
storageAccountUrl=$(getStorageAccountUrl $storageAccountName $resourceGroupName)
helmChartStoreUrl="${storageAccountUrl}${containerName}"

# Export storage account name and key
export AZURE_STORAGE_ACCOUNT=$storageAccountName
export AZURE_STORAGE_KEY=$(getStorageAccountKey $storageAccountName $resourceGroupName)

# Create Helm repo
echo "Now setting up your Azure Storage account for Helm chart repo use..."

while true; do
    read -p "Do you have a Helm chart you would like to upload? (y/n) " yn
    case $yn in
    [Yy]*) hasHelmChart ;;
    [Nn]*) newHelmChart ;;
    *) echo "Please answer yes or no." ;;
    esac
done