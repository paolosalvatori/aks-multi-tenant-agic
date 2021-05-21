#!/bin/bash

# Variables
tenants=("mars" "jupiter" "saturn")
dnsZoneName="babosbird.com"
dnsZoneResourceGroupName="DnsResourceGroup"

for tenant in ${tenants[@]}; do
    # Check if the tenant namespace exists
    echo "Checking whether the [$tenant] namespace exists in the cluster"
    result=$(kubectl get namespace -o jsonpath="{.items[?(@.metadata.name=='$tenant')].metadata.name}")

    if [[ -z $result ]]; then
        echo "[$tenant] namespace does not exist in the cluster"
    else
        echo "[$tenant] namespace exists in the cluster"
        echo "Deleting [$tenant] namespace..."
        # Delete tenant namespace
        kubectl delete namespace $tenant
    fi

    # Check if an A record for todolist subdomain exists in the DNS Zone
    echo "Retrieving the A record for the [$tenant] subdomain from the [$dnsZoneName] DNS zone..."
    ipv4Address=$(az network dns record-set a list \
        --zone-name $dnsZoneName \
        --resource-group $dnsZoneResourceGroupName \
        --query "[?name=='$tenant'].aRecords[].ipv4Address" \
        --output tsv)

    if [[ -n $ipv4Address ]]; then
        echo "An A record exists in [$dnsZoneName] DNS zone for the [$tenant] subdomain with [$ipv4Address] IP address"

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
done