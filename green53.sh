#!/bin/bash

# Get the ALB URL for green deployment
GREEN_ALB=$(kubectl get ingress -n freqtrade-prod-green freqtrade-ingress-green -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Verify ALB URL was obtained
if [ -z "$GREEN_ALB" ]; then
    echo "Error: Could not get ALB URL for green deployment"
    exit 1
fi

echo "Using Green ALB: $GREEN_ALB"

# Create Route53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z02460759K5K96ZILIR0 \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "freqtrade-prod.abc-trading-prod.42web.io",
          "Type": "CNAME",
          "SetIdentifier": "green",
          "Weight": 0,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$GREEN_ALB'"}
          ]
        }
      }
    ]
  }'

# Check if the command was successful
if [ $? -eq 0 ]; then
    echo "Route53 record created successfully"
else
    echo "Failed to create Route53 record"
    exit 1
fi
