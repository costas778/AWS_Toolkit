#!/bin/bash

# Function to backup and update monitor-route53-change-enh.sh
update_monitor_script() {
    local file="/home/costas778/abc/trading-platform/monitor-route53-change-enh.sh"
    local new_alb="$1"
    local new_zone_id="$2"
    local timestamp=$(date +%Y%m%d%H%M%S)
    
    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "❌ Error: monitor-route53-change-enh.sh not found at $file"
        return 1
    fi
    
    # Create backup
    cp "$file" "${file}.${timestamp}.bak"
    echo "✅ Created backup: ${file}.${timestamp}.bak"
    
    # Update the ALB hostname
    sed -i.tmp 's|"Value": "[^"]*\.elb\.amazonaws\.com"|"Value": "'"${new_alb}"'"|' "$file"
    
    # Update the hosted zone ID
    sed -i.tmp 's|--hosted-zone-id [A-Z0-9]\{12,\}|--hosted-zone-id '"${new_zone_id}"'|' "$file"
    
    rm -f "$file.tmp"
    
    # Verify the changes
    if grep -q "${new_alb}" "$file" && grep -q "${new_zone_id}" "$file"; then
        echo "✅ Successfully updated monitor-route53-change-enh.sh"
        return 0
    else
        echo "❌ Failed to verify changes"
        echo "Restoring from backup..."
        cp "${file}.${timestamp}.bak" "$file"
        return 1
    fi
}

# Main script
echo "Starting update process for monitor-route53-change-enh.sh..."

# Get current ALB hostname
echo "Fetching current ALB hostname..."
CURRENT_ALB=$(kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$CURRENT_ALB" ]; then
    echo "❌ Error: Could not fetch ALB hostname"
    exit 1
fi

echo "Found ALB hostname: $CURRENT_ALB"

# Get available hosted zones
echo -e "\nFetching available hosted zones..."
aws route53 list-hosted-zones --query 'HostedZones[*].[Id,Name]' --output table

# Prompt for hosted zone ID
echo -n "Please enter the hosted zone ID (without /hostedzone/ prefix): "
read HOSTED_ZONE_ID

# Validate hosted zone ID format
if [[ ! $HOSTED_ZONE_ID =~ ^Z[A-Z0-9]+$ ]]; then
    echo "❌ Invalid hosted zone ID format. It should start with 'Z' followed by alphanumeric characters."
    exit 1
fi

# Verify the hosted zone exists
if ! aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" >/dev/null 2>&1; then
    echo "❌ Error: Hosted zone ID $HOSTED_ZONE_ID does not exist or is not accessible"
    exit 1
fi

echo "✅ Verified hosted zone ID: $HOSTED_ZONE_ID"

# Confirm changes
echo -e "\nReady to make the following updates:"
echo "ALB Hostname: $CURRENT_ALB"
echo "Hosted Zone ID: $HOSTED_ZONE_ID"
echo -n "Proceed with these changes? (y/n): "
read CONFIRM

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

# Update the file
if update_monitor_script "$CURRENT_ALB" "$HOSTED_ZONE_ID"; then
    echo -e "\n=== Update Summary ==="
    echo "✅ Updated monitor-route53-change-enh.sh with:"
    echo "  - New ALB: $CURRENT_ALB"
    echo "  - New Hosted Zone ID: $HOSTED_ZONE_ID"
    echo -e "\nA backup was created with timestamp suffix."
    echo "To verify the changes, you can use:"
    echo "grep -A 5 'Value' /home/costas778/abc/trading-platform/monitor-route53-change-enh.sh"
else
    echo "❌ Update failed"
    exit 1
fi
