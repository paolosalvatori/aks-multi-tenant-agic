#!/bin/bash

# Variables
tenants=("mars" "jupiter" "saturn")
acrName="<your-azure-container-registry>"
imageName="${acrName,,}.azurecr.io/syntheticapi:latest"
deploymentName="syntheticapi"
deploymentTemplate="deployment.yml"
serviceName="syntheticapi"
serviceTemplate="service.yml"
ingressName="syntheticapi"
ingressTemplate="ingress.yml"
dnsZoneName="<your-domain>" #e.g. contoso.com
dnsZoneResourceGroupName="DnsResourceGroup"
retries=150
sleepInterval=2

for tenant in ${tenants[@]}; do

    # Create the namespace for the tenant if it doesn't already exists in the cluster
    #result=$(kubectl get namespace | grep $tenant | awk '{print $1}')
    result=$(kubectl get namespace -o jsonpath="{.items[?(@.metadata.name=='$tenant')].metadata.name}")

    if [[ -n $result ]]; then
        echo "[$tenant] namespace already exists in the cluster"
    else
        echo "[$tenant] namespace does not exist in the cluster"
        echo "creating [$tenant] namespace in the cluster..."
        kubectl create namespace $tenant
    fi

    # Create the deployment for the tenant if it doesn't already exists in the cluster
    result=$(kubectl get deployment -n $tenant -o jsonpath="{.items[?(@.metadata.name=='$deploymentName')].metadata.name}")


    if [[ -n $result ]]; then
        echo "[$deploymentName] deployment already exists in the [$tenant] namespace"
    else
        echo "[$deploymentName] deployment does not exist in the [$tenant] namespace"
        echo "creating [$deploymentName] deployment in the [$tenant] namespace..."
        cat $deploymentTemplate |
            yq "(.spec.template.spec.containers[0].image)|="\""$imageName"\" |
            kubectl apply -n $tenant -f -
    fi

    # Create the service for the tenant if it doesn't already exists in the cluster
    result=$(kubectl get service -n $tenant -o jsonpath="{.items[?(@.metadata.name=='$serviceName')].metadata.name}")

    if [[ -n $result ]]; then
        echo "[$serviceName] service already exists in the [$tenant] namespace"
    else
        echo "[$serviceName] service does not exist in the [$tenant] namespace"
        echo "creating [$serviceName] service in the [$tenant] namespace..."
        kubectl apply -n $tenant -f $serviceTemplate
    fi

    # Check if the ingress already exists
    result=$(kubectl get ingress -n $tenant -o jsonpath="{.items[?(@.metadata.name=='$ingressName')].metadata.name}")

    if [[ -n $result ]]; then
        echo "[$ingressName] ingress already exists in the [$tenant] namespace"
    else
        # Create the ingress
        echo "[$ingressName] ingress does not exist in the [$tenant] namespace"
        host="$tenant.$dnsZoneName"
        echo "Creating [$ingressName] ingress in the [$tenant] namespace with [$host] host..."
        cat $ingressTemplate |
            yq "(.metadata.name)|="\""$ingressName"\" |
            yq "(.metadata.namespace)|="\""$tenant"\" |
            yq "(.spec.tls[0].hosts[0])|="\""$host"\" |
            yq "(.spec.rules[0].host)|="\""$host"\" |
            kubectl apply -n $tenant -f -
    fi

    # Retrieve the public IP address from the ingress
    echo "Retrieving the external IP address from the [$ingressName] ingress..."
    for ((i = 0; i < $retries; i++)); do
        sleep $sleepInterval
        publicIpAddress=$(kubectl get ingress $ingressName -n $tenant -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

        if [[ -n $publicIpAddress ]]; then
            if [[ $i > 0 ]]; then
                echo ''
            fi
            echo "[$publicIpAddress] external IP address successfully retrieved from the [$ingressName] ingress in the [$tenant] namespace"
            break
        else
            echo -n "."
        fi
    done

    if [[ -z $publicIpAddress ]]; then
        echo "Failed to retrieve the external IP address from the [$ingressName] ingress in the [$tenant] namespace"
        exit
    fi

    # Check if an A record for todolist subdomain exists in the DNS Zone
    echo "Retrieving the A record for the [$tenant] subdomain from the [$dnsZoneName] DNS zone..."
    ipv4Address=$(az network dns record-set a list \
        --zone-name $dnsZoneName \
        --resource-group $dnsZoneResourceGroupName \
        --query "[?name=='$tenant'].aRecords[].ipv4Address" \
        --output tsv)

    if [[ -n $ipv4Address ]]; then
        echo "An A record already exists in [$dnsZoneName] DNS zone for the [$tenant] subdomain with [$ipv4Address] IP address"

        if [[ $ipv4Address == $publicIpAddress ]]; then
            echo "The [$ipv4Address] ip address of the existing A record is equal to the ip address of the [$ingressName] ingress"
            echo "No additional step is required"
            continue
        else
            echo "The [$ipv4Address] ip address of the existing A record is different than the ip address of the [$ingressName] ingress"
        fi

        # Retrieving name of the record set relative to the zone
        echo "Retrieving the name of the record set relative to the [$dnsZoneName] zone..."

        recordSetName=$(az network dns record-set a list \
            --zone-name $dnsZoneName \
            --resource-group $dnsZoneResourceGroupName \
            --query "[?name=='$tenant'].name" \
            --output tsv 2>/dev/null)

        if [[ -n $recordSetName ]]; then
            echo "[$recordSetName] record set name successfully retrieved"
        else
            echo "Failed to retrieve the name of the record set relative to the [$dnsZoneName] zone"
            exit
        fi

        # Remove the A record
        echo "Removing the A record from the record set relative to the [$dnsZoneName] zone..."

        az network dns record-set a remove-record \
            --ipv4-address $ipv4Address \
            --record-set-name $recordSetName \
            --zone-name $dnsZoneName \
            --resource-group $dnsZoneResourceGroupName

        if [[ $? == 0 ]]; then
            echo "[$ipv4Address] ip address successfully removed from the [$recordSetName] record set"
        else
            echo "Failed to remove the [$ipv4Address] ip address from the [$recordSetName] record set"
            exit
        fi
    fi

    # Create the A record
    echo "Creating an A record in [$dnsZoneName] DNS zone for the [$tenant] subdomain with [$publicIpAddress] IP address..."
    az network dns record-set a add-record \
        --zone-name $dnsZoneName \
        --resource-group $dnsZoneResourceGroupName \
        --record-set-name $tenant \
        --ipv4-address $publicIpAddress 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "A record for the [$tenant] subdomain with [$publicIpAddress] IP address successfully created in [$dnsZoneName] DNS zone"
    else
        echo "Failed to create an A record for the $tenant subdomain with [$publicIpAddress] IP address in [$dnsZoneName] DNS zone"
    fi

done
