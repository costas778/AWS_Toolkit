#!/bin/bash

# Get ALB URLs
BLUE_ALB=$(kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
GREEN_ALB=$(kubectl get ingress -n freqtrade-prod-green freqtrade-ingress-green -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Verify ALB URLs were retrieved
if [ -z "$BLUE_ALB" ] || [ -z "$GREEN_ALB" ]; then
    echo "Error: Could not retrieve ALB URLs"
    exit 1
fi

echo "Creating 90/10 split..."
aws route53 change-resource-record-sets \
  --hosted-zone-id Z02414181STCEEEBOMJSA \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.42web.io",
          "Type": "CNAME",
          "SetIdentifier": "blue",
          "Weight": 90,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$BLUE_ALB'"}
          ]
        }
      },
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.42web.io",
          "Type": "CNAME",
          "SetIdentifier": "green",
          "Weight": 10,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$GREEN_ALB'"}
          ]
        }
      }
    ]
  }'
