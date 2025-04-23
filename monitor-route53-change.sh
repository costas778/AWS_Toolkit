#!/bin/bash

CHANGE_ID="/change/C08458461IW63TXXIGEXI"  # Your change ID
echo "Monitoring Route53 change status..."

while true; do
    STATUS=$(aws route53 get-change --id $CHANGE_ID --query 'ChangeInfo.Status' --output text)
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
