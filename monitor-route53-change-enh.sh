#!/bin/bash

# Set error handling
set -e

echo "Starting Route53 record update..."

# Execute the Route53 change
RESPONSE=$(aws route53 change-resource-record-sets \
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
            {"Value": "k8s-freqtradeprod-42931b6ddf-805261129.us-east-1.elb.amazonaws.com"}
          ]
        }
      }
    ]
  }')

# Extract the change ID
CHANGE_ID=$(echo $RESPONSE | jq -r '.ChangeInfo.Id')

# Check if we got a valid change ID
if [ -z "$CHANGE_ID" ] || [ "$CHANGE_ID" = "null" ]; then
    echo "Error: Failed to get Change ID"
    echo "Response: $RESPONSE"
    exit 1
fi

echo "Change ID: $CHANGE_ID"

# Monitor the change status
echo "Monitoring change status..."
while true; do
    STATUS=$(aws route53 get-change --id "$CHANGE_ID" --query 'ChangeInfo.Status' --output text)
    echo "Current status: $STATUS"
    
    if [ "$STATUS" = "INSYNC" ]; then
        echo "Change is complete!"
        break
    elif [ "$STATUS" = "PENDING" ]; then
        echo "Still pending... waiting 10 seconds"
        sleep 10
    else
        echo "Unknown status: $STATUS"
        exit 1
    fi
done

echo "Route53 update completed successfully!"
