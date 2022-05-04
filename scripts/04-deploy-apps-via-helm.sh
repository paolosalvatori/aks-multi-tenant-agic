#!/bin/bash

# Variables
tenants=("mars" "jupiter" "saturn")
acrName="<your-azure-container-registry>"
chart="../syntheticapi"
imageName="${acrName,,}.azurecr.io/syntheticapi"
imageTag="latest"
dnsZoneName="babosbird.com" #e.g. contoso.com
dnsZoneResourceGroupName="DnsResourceGroup"
retries=150
sleepInterval=2

for tenant in ${tenants[@]}; do

    # Check if the Helm release already exists
    echo "Checking if a [$tenant] Helm release exists in the [$tenant] namespace..."
    release=$(helm list -n $tenant | awk '{print $1}' | grep -Fx $tenant)
    hostname="$tenant.$dnsZoneName"

    if [[ -n $release ]]; then
        # Install the Helm chart for the tenant to a dedicated namespace
        echo "A [$tenant] Helm release already exists in the [$tenant] namespace"
        echo "Upgrading the [$tenant] Helm release to the [$tenant] namespace via Helm..."
        helm upgrade $tenant $chart \
        --namespace $tenant \
        --set image.repository=$imageName \
        --set image.tag=$imageTag \
        --set nameOverride=$tenant \
        --set ingress.hosts[0].host=$hostname \
        --set ingress.tls[0].hosts[0]=$hostname

        if [[ $? == 0 ]]; then
            echo "[$tenant] Helm release successfully upgraded to the [$tenant] namespace via Helm"
        else
            echo "Failed to upgrade [$tenant] Helm release to the [$tenant] namespace via Helm"
            exit
        fi
    else
        # Install the Helm chart for the tenant to a dedicated namespace
        echo "The [$tenant] Helm release does not exist in the [$tenant] namespace"
        echo "Deploying the [$tenant] Helm release to the [$tenant] namespace via Helm..."
        helm install $tenant $chart \
        --create-namespace \
        --namespace $tenant \
        --set image.repository=$imageName \
        --set image.tag=$imageTag \
        --set nameOverride=$tenant \
        --set ingress.hosts[0].host=$hostname \
        --set ingress.tls[0].hosts[0]=$hostname

        if [[ $? == 0 ]]; then
            echo "[$tenant] Helm release successfully deployed to the [$tenant] namespace via Helm"
        else
            echo "Failed to install [$tenant] Helm release to the [$tenant] namespace via Helm"
            exit
        fi
    fi

    # Retrieve the public IP address from the ingress
    ingressName=$tenant
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