#!/bin/bash
# migrate_terraform_backend.sh - Script to handle Terraform backend migration

echo "This script will help migrate your Terraform state to the new backend configuration."
echo "It should be run after config_first.sh if you encounter backend configuration errors."
echo ""

# Get environment from parameter, default to dev if not specified
ENV=${1:-dev}
TERRAFORM_DIR="/home/costas778/abc/trading-platform/infrastructure/terraform/environments/${ENV}"

echo "Current directory: ${TERRAFORM_DIR}"
cd "${TERRAFORM_DIR}" || exit 1
echo ""


echo "Options:"
echo "1. Migrate existing state to the new backend (terraform init -migrate-state)"
echo "2. Use new backend without migrating state (terraform init -reconfigure)"
echo ""

read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        echo "Running: terraform init -migrate-state"
        terraform init -migrate-state
        ;;
    2)
        echo "Running: terraform init -reconfigure"
        terraform init -reconfigure
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

if [ $? -eq 0 ]; then
    echo "Terraform backend configuration updated successfully."
    echo "You can now proceed with your deployment."
else
    echo "Error updating Terraform backend configuration."
    echo "You may need to manually resolve the backend configuration issues."
fi
