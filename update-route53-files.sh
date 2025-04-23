#!/bin/bash

# Function to backup and update a file
update_hosted_zone_id() {
    local file="$1"
    local new_zone_id="$2"
    local timestamp=$(date +%Y%m%d%H%M%S)
    
    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "❌ File not found: $file"
        return 1
    fi
    
    # Create backup
    cp "$file" "${file}.${timestamp}.bak"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to create backup of $file"
        return 1
    fi
    echo "✅ Created backup: ${file}.${timestamp}.bak"
    
    # Update the hosted zone ID
    sed -i.tmp "s/--hosted-zone-id [A-Z0-9]\{12,\}/--hosted-zone-id ${new_zone_id}/" "$file"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to update hosted zone ID in $file"
        # Restore from backup
        cp "${file}.${timestamp}.bak" "$file"
        rm -f "$file.tmp"
        return 1
    fi
    rm -f "$file.tmp"
    
    # Verify the change
    if grep -q "${new_zone_id}" "$file"; then
        echo "✅ Successfully updated hosted zone ID in $(basename "$file")"
        return 0
    else
        echo "❌ Failed to verify change in $file"
        # Restore from backup
        cp "${file}.${timestamp}.bak" "$file"
        return 1
    fi
}

# Main script
echo "Starting hosted zone ID update process..."

# List of files to update
FILES=(
    "/home/costas778/abc/trading-platform/blue53.sh"
    "/home/costas778/abc/trading-platform/green53.sh"
    "/home/costas778/abc/trading-platform/90-10-split.sh"
    "/home/costas778/abc/trading-platform/75-25-split.sh"
    "/home/costas778/abc/trading-platform/green100.sh"
)

# Get the hosted zone ID
echo "Fetching available hosted zones..."
aws route53 list-hosted-zones --query 'HostedZones[*].[Id,Name]' --output table

echo -n "Please enter the hosted zone ID (without /hostedzone/ prefix): "
read HOSTED_ZONE_ID

# Validate hosted zone ID format (updated to match actual format)
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

# Process each file
echo -e "\nUpdating files..."
for file in "${FILES[@]}"; do
    echo -e "\nProcessing $(basename "$file")..."
    if update_hosted_zone_id "$file" "$HOSTED_ZONE_ID"; then
        echo "  ✅ Update successful"
    else
        echo "  ❌ Update failed"
    fi
done

# Print summary
echo -e "\n=== Update Summary ==="
echo "Hosted Zone ID: $HOSTED_ZONE_ID"
echo "Files processed:"
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "$HOSTED_ZONE_ID" "$file"; then
            echo "  ✅ $(basename "$file") - Updated successfully"
        else
            echo "  ❌ $(basename "$file") - Update failed"
        fi
    else
        echo "  ⚠️ $(basename "$file") - File not found"
    fi
done

echo -e "\nBackups were created with timestamp suffix for all processed files."
echo "To verify the changes, you can use: grep -r \"$HOSTED_ZONE_ID\" /home/costas778/abc/trading-platform/"
