#!/bin/bash

# Get Green ALB URL
GREEN_ALB=$(kubectl get ingress -n freqtrade-prod-green freqtrade-ingress-green -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Verify ALB URL was retrieved
if [ -z "$GREEN_ALB" ]; then
    echo "Error: Could not retrieve Green ALB URL"
    exit 1
fi

echo "Setting 100% traffic to green..."
aws route53 change-resource-record-sets \
  --hosted-zone-id Z0083227W6H3R1LZEXIY \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.com",
          "Type": "CNAME",
          "SetIdentifier": "green",
          "Weight": 100,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$GREEN_ALB'"}
          ]
        }
      }
    ]
  }'
