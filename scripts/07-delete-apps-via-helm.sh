#!/bin/bash

# Variables
tenants=("red" "blue" "green")
dnsZoneName="<your-domain>" #e.g. contoso.com
dnsZoneResourceGroupName="DnsResourceGroup"

for tenant in ${tenants[@]}; do
    
     # Check if the Helm release already exists
    echo "Checking if a [$tenant] Helm release exists in the [$tenant] namespace..."
    release=$(helm list -n $tenant | awk '{print $1}' | grep -Fx $tenant)
    hostname="$tenant.$dnsZoneName"

    if [[ -n $release ]]; then
        # Install the Helm chart for the tenant to a dedicated namespace
        echo "A [$tenant] Helm release exists in the [$tenant] namespace"

        # Delete Helm release 
        echo "Deleting [$tenant] Helm release in the [$tenant] namespace..."
        helm delete $tenant -n $tenant
    else
        echo "No [$tenant] Helm release exists in the [$tenant] namespace"
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