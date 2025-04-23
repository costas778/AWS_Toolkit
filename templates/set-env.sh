#!/bin/bash
# AWS credentials
export AWS_ACCESS_KEY_ID="AKIAYS2NWACMYFH34VK2"
export AWS_SECRET_ACCESS_KEY="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"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS Account ID. Please check AWS credentials."
    exit 1
fi
echo "Using AWS Account: ${AWS_ACCOUNT_ID}"
echo "Using Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using Secret Access Key: ${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}"
echo "Using Default Region: ${AWS_DEFAULT_REGION}"
echo "Your good to go! First ./main.sh prod, then ./Post_main.sh finally services.sh for a NON production provisioning"
echo "Then your ready to deploy the application"
echo "For a production deployment, first please use the backup_secrets_config.sh followed by the setup_secrets_configuration.sh"

# Sensitive variables
export TF_VAR_database_password="Harvee777"

# Application runtime configuration
export BUILD_VERSION="1.0.0"
export DOMAIN_NAME="abc-trading-prod.42web.io"
export HOSTED_ZONE_ID="Z0166283G0GVVNFUS165"

# Infrastructure configuration
export TF_STATE_BUCKET="bucket590184054937"
export TF_LOCK_TABLE="terraform-state-lock"
export CLUSTER_NAME="abc-trading-prod"
export MICROSERVICES="axon-server backend-services frontend"
