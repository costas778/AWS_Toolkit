#!/bin/bash

# Function to update subnets in setup-argocd-ingress.sh
update_argocd_ingress_subnets() {
    local file_path="/home/costas778/abc/trading-platform/setup-argocd-ingress.sh"
    local subnet_1a="$1"
    local subnet_1b="$2"
    local subnet_1c="$3"

    if [ ! -f "$file_path" ]; then
        echo "❌ Error: setup-argocd-ingress.sh not found at $file_path"
        return 1
    fi

    echo "Updating subnets in setup-argocd-ingress.sh..."
    
    # Create backup
    cp "$file_path" "${file_path}.bak"
    echo "✅ Created backup at ${file_path}.bak"

    # Create new subnet array content
    local new_subnet_block="SUBNETS=(
    \"${subnet_1a}\"  # us-east-1a
    \"${subnet_1b}\"  # us-east-1b
    \"${subnet_1c}\"  # us-east-1c
    )"

    # Replace the subnet block using awk
    awk -v new_subnets="$new_subnet_block" '
    /^SUBNETS=\(/{
        print new_subnets
        in_subnet_block=1
        next
    }
    in_subnet_block && /^    \)/{
        in_subnet_block=0
        next
    }
    !in_subnet_block {
        print
    }
    ' "${file_path}.bak" > "$file_path"

    # Verify the changes
    if grep -q "${subnet_1a}" "$file_path" && \
       grep -q "${subnet_1b}" "$file_path" && \
       grep -q "${subnet_1c}" "$file_path"; then
        echo "✅ Successfully updated subnets in setup-argocd-ingress.sh"
        echo "New subnet configuration:"
        echo "  us-east-1a: ${subnet_1a}"
        echo "  us-east-1b: ${subnet_1b}"
        echo "  us-east-1c: ${subnet_1c}"
    else
        echo "❌ Error: Failed to update subnets"
        echo "Restoring backup..."
        cp "${file_path}.bak" "$file_path"
        return 1
    fi

    # Make the file executable
    chmod +x "$file_path"
}

# Main execution
echo "Starting subnet update process..."

# Fetch subnet IDs from AWS
echo "Fetching subnet IDs from AWS..."

# Get subnet for us-east-1a
SUBNET_1A=$(aws ec2 describe-subnets \
    --filters "Name=availability-zone,Values=us-east-1a" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Get subnet for us-east-1b
SUBNET_1B=$(aws ec2 describe-subnets \
    --filters "Name=availability-zone,Values=us-east-1b" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Get subnet for us-east-1c
SUBNET_1C=$(aws ec2 describe-subnets \
    --filters "Name=availability-zone,Values=us-east-1c" \
    --query 'Subnets[0].SubnetId' \
    --output text)

# Check if we got all subnets
if [ "$SUBNET_1A" = "None" ] || [ "$SUBNET_1B" = "None" ] || [ "$SUBNET_1C" = "None" ] || \
   [ -z "$SUBNET_1A" ] || [ -z "$SUBNET_1B" ] || [ -z "$SUBNET_1C" ]; then
    echo "❌ Error: Could not find all required subnets"
    echo "Found subnets:"
    echo "  us-east-1a: ${SUBNET_1A:-Not found}"
    echo "  us-east-1b: ${SUBNET_1B:-Not found}"
    echo "  us-east-1c: ${SUBNET_1C:-Not found}"
    exit 1
fi

echo "Found subnets:"
echo "  us-east-1a: $SUBNET_1A"
echo "  us-east-1b: $SUBNET_1B"
echo "  us-east-1c: $SUBNET_1C"

# Update the subnets in the file
if update_argocd_ingress_subnets "$SUBNET_1A" "$SUBNET_1B" "$SUBNET_1C"; then
    echo "✅ Subnet update completed successfully"
else
    echo "❌ Error: Failed to update subnets"
    exit 1
fi

echo "
Next steps:
1. Review the changes in setup-argocd-ingress.sh
2. Run ./setup-argocd-ingress.sh to apply the changes
3. Verify the ArgoCD ingress is working with the new subnet configuration

To verify the current subnet configuration, run:
aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone,CidrBlock]' --output table
"
