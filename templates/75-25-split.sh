#!/bin/bash

# Get ALB URLs
BLUE_ALB=$(kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
GREEN_ALB=$(kubectl get ingress -n freqtrade-prod-green freqtrade-ingress-green -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Verify ALB URLs were retrieved
if [ -z "$BLUE_ALB" ] || [ -z "$GREEN_ALB" ]; then
    echo "Error: Could not retrieve ALB URLs"
    exit 1
fi

echo "Creating 75/25 split..."
aws route53 change-resource-record-sets \
  --hosted-zone-id Z0083227W6H3R1LZEXIY \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.com",
          "Type": "CNAME",
          "SetIdentifier": "blue",
          "Weight": 75,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$BLUE_ALB'"}
          ]
        }
      },
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.com",
          "Type": "CNAME",
          "SetIdentifier": "green",
          "Weight": 25,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$GREEN_ALB'"}
          ]
        }
      }
    ]
  }'
