#!/bin/bash

# Get the ALB URL for blue deployment
BLUE_ALB=$(kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Verify ALB URL was obtained
if [ -z "$BLUE_ALB" ]; then
    echo "Error: Could not get ALB URL for blue deployment"
    exit 1
fi

echo "Using Blue ALB: $BLUE_ALB"

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
          "SetIdentifier": "blue",
          "Weight": 100,
          "TTL": 60,
          "ResourceRecords": [
            {"Value": "'$BLUE_ALB'"}
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
