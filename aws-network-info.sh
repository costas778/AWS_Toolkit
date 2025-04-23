#!/bin/bash

# Exit on any error
set -e

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

source set-env.sh

# # Check if AWS credentials are set
# if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
#     echo "Error: AWS credentials are not set. Please set them first."
#     exit 1
# fi

echo "Creating Route53 hosted zone..."
aws route53 create-hosted-zone \
    --name abc-trading-prod.42web.io \
    --caller-reference $(date +%s)

echo -e "\nFetching subnet information..."
aws ec2 describe-subnets \
    --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone,CidrBlock]' \
    --output table

echo "Script execution completed."
