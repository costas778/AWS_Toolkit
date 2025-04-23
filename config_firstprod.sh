#!/bin/bash

# Ensure AWS credentials are set in the environment
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "AWS credentials must be set in environment variables"
    exit 1
fi

echo "Starting AWS configuration update..."
echo "Using AWS Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "Using AWS Secret Access Key: ${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}" # Show only first and last 3 chars for security

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS Account ID. Please check AWS credentials."
    exit 1
fi
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Set bucket name based on account ID
TF_STATE_BUCKET="bucket${AWS_ACCOUNT_ID}"
echo "Setting TF_STATE_BUCKET=${TF_STATE_BUCKET}"

# Find all references to the old bucket name
echo "Searching for references to old bucket names in Terraform files..."
OLD_BUCKET_REFS=$(grep -r "bucket[0-9]\{12\}" --include="*.tf" /home/costas778/abc/trading-platform/infrastructure/terraform/)

if [ -n "$OLD_BUCKET_REFS" ]; then
    echo "Found references to old bucket names in the following files:"
    echo "$OLD_BUCKET_REFS"
    echo ""
    echo "These references will be updated to use ${TF_STATE_BUCKET}"
else
    echo "No references to old bucket names found in Terraform files."
fi

# Set DB instance name
DB_INSTANCE_NAME="db_prod_${AWS_ACCOUNT_ID}"
echo "Setting DB_INSTANCE_NAME=${DB_INSTANCE_NAME}"

# Get subnet IDs for us-east-1a, us-east-1b, us-east-1c
echo "Fetching subnet IDs..."
SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=availability-zone,Values=us-east-1a" --query "Subnets[0].SubnetId" --output text)
SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=availability-zone,Values=us-east-1b" --query "Subnets[0].SubnetId" --output text)
SUBNET_1C=$(aws ec2 describe-subnets --filters "Name=availability-zone,Values=us-east-1c" --query "Subnets[0].SubnetId" --output text)

echo "Subnet IDs:"
echo "  us-east-1a: ${SUBNET_1A}"
echo "  us-east-1b: ${SUBNET_1B}"
echo "  us-east-1c: ${SUBNET_1C}"

# List available hosted zones
echo "Available hosted zones:"
aws route53 list-hosted-zones --query "HostedZones[].[Id,Name]" --output text | sed 's|/hostedzone/||'

# Review and confirm or update all key configuration values
echo ""
echo "=== Review Configuration Values ==="
echo ""

# 1. Confirm AWS Account ID
echo -n "AWS Account ID (default: ${AWS_ACCOUNT_ID}): "
read input_account_id
AWS_ACCOUNT_ID=${input_account_id:-$AWS_ACCOUNT_ID}
echo "Using AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}"

# 2. Confirm AWS Access Key ID
echo -n "AWS Access Key ID (default: ${AWS_ACCESS_KEY_ID}): "
read input_access_key
AWS_ACCESS_KEY_ID=${input_access_key:-$AWS_ACCESS_KEY_ID}
echo "Using AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"

# 3. Confirm AWS Secret Access Key (show first and last 3 chars)
echo -n "AWS Secret Access Key (default: ${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}, press Enter to keep): "
read input_secret_key
if [ ! -z "$input_secret_key" ]; then
    AWS_SECRET_ACCESS_KEY=$input_secret_key
fi
echo "Using AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}"

# 4. Confirm Hosted Zone ID
echo -n "Hosted Zone ID (default: Z0568951QVMPBG6CVZQ5): "
read input_zone_id
HOSTED_ZONE_ID=${input_zone_id:-Z0568951QVMPBG6CVZQ5}
echo "Using HOSTED_ZONE_ID=${HOSTED_ZONE_ID}"

# 5. Confirm TF State Bucket
echo -n "TF State Bucket (default: ${TF_STATE_BUCKET}): "
read input_bucket
TF_STATE_BUCKET=${input_bucket:-$TF_STATE_BUCKET}
echo "Using TF_STATE_BUCKET=${TF_STATE_BUCKET}"

# 6. Confirm DB Instance Name
echo -n "DB Instance Name (default: ${DB_INSTANCE_NAME}): "
read input_db_name
DB_INSTANCE_NAME=${input_db_name:-$DB_INSTANCE_NAME}
echo "Using DB_INSTANCE_NAME=${DB_INSTANCE_NAME}"

# 7. Confirm Subnet IDs
echo -n "Subnet ID for us-east-1a (default: ${SUBNET_1A}): "
read input_subnet_1a
SUBNET_1A=${input_subnet_1a:-$SUBNET_1A}
echo "Using SUBNET_1A=${SUBNET_1A}"

echo -n "Subnet ID for us-east-1b (default: ${SUBNET_1B}): "
read input_subnet_1b
SUBNET_1B=${input_subnet_1b:-$SUBNET_1B}
echo "Using SUBNET_1B=${SUBNET_1B}"

echo -n "Subnet ID for us-east-1c (default: ${SUBNET_1C}): "
read input_subnet_1c
SUBNET_1C=${input_subnet_1c:-$SUBNET_1C}
echo "Using SUBNET_1C=${SUBNET_1C}"

# Final confirmation before proceeding
echo ""
echo "=== Final Configuration Summary ==="
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "AWS Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "AWS Secret Access Key: ${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}"
echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"
echo "TF State Bucket: ${TF_STATE_BUCKET}"
echo "DB Instance Name: ${DB_INSTANCE_NAME}"
echo "Subnet IDs:"
echo "  us-east-1a: ${SUBNET_1A}"
echo "  us-east-1b: ${SUBNET_1B}"
echo "  us-east-1c: ${SUBNET_1C}"
echo ""

echo -n "Proceed with these values? (y/n): "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Configuration update cancelled."
    exit 0
fi

# Create backups of all files
# echo "Creating backups of configuration files..."
# TIMESTAMP=$(date +%Y%m%d%H%M%S)
# [ -f /home/costas778/abc/trading-platform/set-env.sh ] && cp /home/costas778/abc/trading-platform/set-env.sh /home/costas778/abc/trading-platform/set-env.sh.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/.env ] && cp /home/costas778/abc/trading-platform/.env /home/costas778/abc/trading-platform/.env.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/terraform.tfvars ] && cp /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/terraform.tfvars /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/terraform.tfvars.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf ] && cp /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf ] && cp /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/services.sh ] && cp /home/costas778/abc/trading-platform/services.sh /home/costas778/abc/trading-platform/services.sh.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh ] && cp /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/build-freqtrade.sh ] && cp /home/costas778/abc/trading-platform/build-freqtrade.sh /home/costas778/abc/trading-platform/build-freqtrade.sh.${TIMESTAMP}
# [ -f /home/costas778/abc/trading-platform/install-alb-controller.sh ] && cp /home/costas778/abc/trading-platform/install-alb-controller.sh /home/costas778/abc/trading-platform/install-alb-controller.sh.${TIMESTAMP}



# 1. Update set-env.sh
cat > /home/costas778/abc/trading-platform/set-env.sh << EOF
#!/bin/bash
# AWS credentials
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCOUNT_ID=\$(aws sts get-caller-identity --query "Account" --output text)
if [ \$? -ne 0 ]; then
    echo "Error: Failed to get AWS Account ID. Please check AWS credentials."
    exit 1
fi
echo "Using AWS Account: \${AWS_ACCOUNT_ID}"
echo "Using Access Key ID: \${AWS_ACCESS_KEY_ID}"
echo "Using Secret Access Key: \${AWS_SECRET_ACCESS_KEY:0:3}...\${AWS_SECRET_ACCESS_KEY: -3}"
echo "Using Default Region: \${AWS_DEFAULT_REGION}"
echo "Your good to go! First ./main.sh prod, then ./Post_main.sh finally services.sh for a NON production provisioning"
echo "Then your ready to deploy the application"
echo "For a production deployment, first please use the backup_secrets_config.sh followed by the setup_secrets_configuration.sh"

# Sensitive variables
export TF_VAR_database_password="Harvee777"

# Application runtime configuration
export BUILD_VERSION="1.0.0"
export DOMAIN_NAME="abc-trading-prod.42web.io"
export HOSTED_ZONE_ID="${HOSTED_ZONE_ID}"

# Infrastructure configuration
export TF_STATE_BUCKET="${TF_STATE_BUCKET}"
export TF_LOCK_TABLE="terraform-state-lock"
export CLUSTER_NAME="abc-trading-prod"
export MICROSERVICES="axon-server backend-services frontend"
EOF
chmod +x /home/costas778/abc/trading-platform/set-env.sh
echo "Updated set-env.sh at /home/costas778/abc/trading-platform/set-env.sh"

# 2. Update .env
cat > /home/costas778/abc/trading-platform/.env << EOF
# Application runtime configuration
BUILD_VERSION=1.0.0
DOMAIN_NAME=abc-trading-prod.42web.io
HOSTED_ZONE_ID="${HOSTED_ZONE_ID}"

# AWS Configuration
TF_STATE_BUCKET="${TF_STATE_BUCKET}"
TF_LOCK_TABLE="terraform-state-lock"
AWS_DEFAULT_REGION="us-east-1"

# Cluster Configuration
CLUSTER_NAME="abc-trading-prod"
MICROSERVICES="axon-server backend-services frontend"

# Database Configuration
DB_USERNAME="dbmaster"
DB_PASSWORD="\${TF_VAR_database_password}"
DB_PORT="5432"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME}"

# Service Groups
CORE_SERVICES="authentication authorization user-management"
DEPENDENT_SERVICES="api-gateway audit cache compliance logging market-data message-queue"
BUSINESS_SERVICES="order-management portfolio-management position-management price-feed quote-service reporting risk-management settlement trade-execution notification"

# Legacy Configuration
MICROSERVICES="axon-server backend-services frontend"
EOF
echo "Updated .env at /home/costas778/abc/trading-platform/.env"

# 3. Update terraform.tfvars
cat > /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/terraform.tfvars << EOF
# Infrastructure configuration
aws_region          = "us-east-1"
environment         = "prod"
project_name        = "abc-trading"
cluster_name        = "abc-trading-prod"
vpc_cidr            = "10.0.0.0/16"
database_name       = "${DB_INSTANCE_NAME}"
database_username   = "dbmaster"

availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# EKS configuration
kubernetes_version  = "1.28"
node_instance_type = "t3.medium"
node_desired_size  = 4
node_min_size      = 2
node_max_size      = 4

# RDS configuration
db_instance_class  = "db.t3.medium"
db_storage        = 20
EOF
echo "Updated terraform.tfvars at /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/terraform.tfvars"

# 4. Update all Terraform files with the correct bucket name
echo "Updating all Terraform files with the correct bucket name..."
find /home/costas778/abc/trading-platform/infrastructure/terraform -type f -name "*.tf" -exec sed -i "s/bucket\s*=\s*\"bucket[0-9]\{12\}\"/bucket = \"${TF_STATE_BUCKET}\"/g" {} \;
echo "Updated all Terraform files with the correct bucket name."

# 5. Update backend.tf with the correct bucket name
if [ -f /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf ]; then
    # Update the bucket name
    sed -i "s/bucket\s*=\s*\"bucket[0-9]\{12\}\"/bucket = \"${TF_STATE_BUCKET}\"/g" /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf
    
    echo "Updated backend.tf with the correct bucket name at /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf"
else
    echo "Warning: backend.tf not found at /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/backend.tf"
fi

# 6. Update main.tf subnet IDs
if [ -f /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf ]; then
    # Create a temporary file with the updated subnet IDs
    TMP_FILE=$(mktemp)
    
    # Process the file line by line
    while IFS= read -r line; do
        if [[ $line =~ subnet_ids ]]; then
            # Found the subnet_ids line, output it
            echo "$line" >> "$TMP_FILE"
            # Skip the next 4 lines (the opening bracket and 3 subnet lines)
            read -r line
            read -r line
            read -r line
            read -r line
            # Output the new subnet IDs
            echo "    \"${SUBNET_1A}\",  # us-east-1a" >> "$TMP_FILE"
            echo "    \"${SUBNET_1B}\",  # us-east-1b" >> "$TMP_FILE"
            echo "    \"${SUBNET_1C}\"   # us-east-1c" >> "$TMP_FILE"
            echo "  ]" >> "$TMP_FILE"
        else
            # Output the line unchanged
            echo "$line" >> "$TMP_FILE"
        fi
    done < /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf
    
    # Replace the original file with the updated one
    mv "$TMP_FILE" /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf
    
    echo "Updated main.tf with subnet IDs at /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf"
else
    echo "Warning: main.tf not found at /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod/main.tf"
fi



# 7. Update services.sh with the correct AWS account ID
if [ -f /home/costas778/abc/trading-platform/services.sh ]; then
    # Replace the AWS account ID in the ECR image URL
    sed -i "s/\([0-9]\{12\}\)\.dkr\.ecr\.us-east-1\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.us-east-1\.amazonaws\.com/g" /home/costas778/abc/trading-platform/services.sh
    echo "Updated services.sh with AWS account ID ${AWS_ACCOUNT_ID} at /home/costas778/abc/trading-platform/services.sh"
else
    echo "Warning: services.sh not found at /home/costas778/abc/trading-platform/services.sh"
fi

# 8. Update setup-freqtrade-ecr.sh with the correct AWS account ID
if [ -f /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh ]; then
    # Replace the AWS account ID in the specific lines
    sed -i "14s/[0-9]\{12\}\.dkr\.ecr\.us-east-1\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.us-east-1\.amazonaws\.com/g" /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh
    sed -i "22s/[0-9]\{12\}\.dkr\.ecr\.us-east-1\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.us-east-1\.amazonaws\.com/g" /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh
    sed -i "26s/[0-9]\{12\}\.dkr\.ecr\.us-east-1\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.us-east-1\.amazonaws\.com/g" /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh
    
    echo "Updated setup-freqtrade-ecr.sh with AWS account ID ${AWS_ACCOUNT_ID} at lines 14, 22, and 26"
else
    echo "Warning: setup-freqtrade-ecr.sh not found at /home/costas778/abc/trading-platform/setup-freqtrade-ecr.sh"
fi

# 9. Update build-freqtrade.sh with the correct subnet IDs
if [ -f /home/costas778/abc/trading-platform/build-freqtrade.sh ]; then
    # Replace the subnet IDs in the alb.ingress.kubernetes.io/subnets annotation
    SUBNET_LIST="${SUBNET_1A},${SUBNET_1B},${SUBNET_1C}"
    sed -i "s/alb\.ingress\.kubernetes\.io\/subnets: subnet-[^,]*,subnet-[^,]*,subnet-[^,]*/alb\.ingress\.kubernetes\.io\/subnets: ${SUBNET_LIST}/g" /home/costas778/abc/trading-platform/build-freqtrade.sh
    
    # Also update the AWS account ID in the ECR repository URI
    sed -i "s/\([0-9]\{12\}\)\.dkr\.ecr\.${AWS_REGION:-us-east-1}\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.${AWS_REGION:-us-east-1}\.amazonaws\.com/g" /home/costas778/abc/trading-platform/build-freqtrade.sh
    
    echo "Updated build-freqtrade.sh with subnet IDs (${SUBNET_LIST}) and AWS account ID ${AWS_ACCOUNT_ID} at /home/costas778/abc/trading-platform/build-freqtrade.sh"
else
    echo "Warning: build-freqtrade.sh not found at /home/costas778/abc/trading-platform/build-freqtrade.sh"
fi

if [ -f /home/costas778/abc/trading-platform/build-freqtrade_enh.sh ]; then
    # Replace the subnet IDs in the alb.ingress.kubernetes.io/subnets annotation
    SUBNET_LIST="${SUBNET_1A},${SUBNET_1B},${SUBNET_1C}"
    sed -i "s/alb\.ingress\.kubernetes\.io\/subnets: subnet-[^,]*,subnet-[^,]*,subnet-[^,]*/alb\.ingress\.kubernetes\.io\/subnets: ${SUBNET_LIST}/g" /home/costas778/abc/trading-platform/build-freqtrade_enh.sh
    
    # Also update the AWS account ID in the ECR repository URI
    sed -i "s/\([0-9]\{12\}\)\.dkr\.ecr\.${AWS_REGION:-us-east-1}\.amazonaws\.com/${AWS_ACCOUNT_ID}\.dkr\.ecr\.${AWS_REGION:-us-east-1}\.amazonaws\.com/g" /home/costas778/abc/trading-platform/build-freqtrade_enh.sh
    
    echo "Updated build-freqtrade_enh.sh with subnet IDs (${SUBNET_LIST}) and AWS account ID ${AWS_ACCOUNT_ID} at /home/costas778/abc/trading-platform/build-freqtrade_enh.sh"
else
    echo "Warning: build-freqtrade_enh.sh not found at /home/costas778/abc/trading-platform/build-freqtrade_enh.sh"
fi

# Update install-alb-controller.sh with correct cluster name
if [ -f /home/costas778/abc/trading-platform/install-alb-controller.sh ]; then
    sed -i 's/CLUSTER_NAME="abc-trading-dev"/CLUSTER_NAME="abc-trading-prod"/' /home/costas778/abc/trading-platform/install-alb-controller.sh
    echo "Updated install-alb-controller.sh with cluster name abc-trading-prod"
else
    echo "Warning: install-alb-controller.sh not found at /home/costas778/abc/trading-platform/install-alb-controller.sh"
fi

# #here
# # Update monitor-route53-change-enh.sh with correct hosted zone ID
# if [ -f /home/costas778/abc/trading-platform/monitor-route53-change-enh.sh ]; then
#     # Replace the hosted zone ID
#     sed -i "s/--hosted-zone-id [A-Z0-9]\{21\}/--hosted-zone-id ${HOSTED_ZONE_ID}/" /home/costas778/abc/trading-platform/monitor-route53-change-enh.sh
    
#     echo "Updated monitor-route53-change-enh.sh with hosted zone ID ${HOSTED_ZONE_ID}"
# else
#     echo "Warning: monitor-route53-change-enh.sh not found at /home/costas778/abc/trading-platform/monitor-route53-change-enh.sh"
# fi

# # Also update any similar files that might exist
# for file in /home/costas778/abc/trading-platform/blue53.sh \
#             /home/costas778/abc/trading-platform/green53.sh \
#             /home/costas778/abc/trading-platform/90-10-split.sh \
#             /home/costas778/abc/trading-platform/75-25-split.sh \
#             /home/costas778/abc/trading-platform/green100.sh; do
#     if [ -f "$file" ]; then
#         # Replace the hosted zone ID in each file
#         sed -i "s/--hosted-zone-id [A-Z0-9]\{21\}/--hosted-zone-id ${HOSTED_ZONE_ID}/" "$file"
#         echo "Updated $(basename "$file") with hosted zone ID ${HOSTED_ZONE_ID}"
#     fi
# done

#here















# 10. Create the S3 bucket if it doesn't exist
echo "Checking if S3 bucket ${TF_STATE_BUCKET} exists..."
if ! aws s3 ls "s3://${TF_STATE_BUCKET}" 2>&1 > /prod/null; then
    echo "S3 bucket ${TF_STATE_BUCKET} does not exist. Creating it..."
    aws s3 mb "s3://${TF_STATE_BUCKET}" --region us-east-1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create S3 bucket ${TF_STATE_BUCKET}."
        echo "Please create it manually: aws s3 mb s3://${TF_STATE_BUCKET} --region us-east-1"
    else
        echo "S3 bucket ${TF_STATE_BUCKET} created successfully."
        
        # Enable versioning on the bucket
        aws s3api put-bucket-versioning --bucket "${TF_STATE_BUCKET}" --versioning-configuration Status=Enabled
        echo "Enabled versioning on S3 bucket ${TF_STATE_BUCKET}."
    fi
else
    echo "S3 bucket ${TF_STATE_BUCKET} already exists."
fi

# 11. Clean up Terraform state and reinitialize
echo "Cleaning up Terraform state and reinitializing..."
cd /home/costas778/abc/trading-platform/infrastructure/terraform/environments/prod

# Remove the .terraform directory (contains providers and modules)
rm -rf .terraform/

# Remove all state files
rm -f terraform.tfstate
rm -f terraform.tfstate.backup

# Remove the lock file
rm -f .terraform.lock.hcl

# Initialize Terraform with the new backend configuration and automatically migrate state
echo "Initializing Terraform with -migrate-state to handle backend configuration changes..."
terraform init -migrate-state
if [ $? -ne 0 ]; then
    echo "Warning: terraform init -migrate-state failed. Trying with -reconfigure..."
    terraform init -reconfigure
    if [ $? -ne 0 ]; then
        echo "Error: Both terraform init approaches failed. Please run one of the following commands manually:"
        echo "  terraform init -migrate-state   # To migrate existing state to the new backend"
        echo "  terraform init -reconfigure     # To use the new backend without migrating state"
        exit 1
    else
        echo "Successfully initialized Terraform with -reconfigure (new backend without state migration)."
    fi
else
    echo "Successfully initialized Terraform with -migrate-state (state migrated to new backend)."
fi
cd -

# Summary of changes
echo ""
echo "=== Configuration Update Complete ==="
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
echo "AWS Access Key ID: ${AWS_ACCESS_KEY_ID}"
echo "AWS Secret Access Key: ${AWS_SECRET_ACCESS_KEY:0:3}...${AWS_SECRET_ACCESS_KEY: -3}"
echo "Hosted Zone ID: ${HOSTED_ZONE_ID}"
echo "TF State Bucket: ${TF_STATE_BUCKET}"
echo "DB Instance Name: ${DB_INSTANCE_NAME}"
echo "Subnet IDs:"
echo "  us-east-1a: ${SUBNET_1A}"
echo "  us-east-1b: ${SUBNET_1B}"
echo "  us-east-1c: ${SUBNET_1C}"
echo ""
# Source the updated environment variables
echo "Sourcing the updated environment variables..."
if [ -f /home/costas778/abc/trading-platform/set-env.sh ]; then
    # Source the file in the current shell
    source /home/costas778/abc/trading-platform/set-env.sh
    if [ $? -eq 0 ]; then
        echo "✅ Successfully sourced set-env.sh"
        echo "Environment variables have been updated in your current shell"
    else
        echo "❌ Failed to source set-env.sh"
        echo "You may need to manually run: source /home/costas778/abc/trading-platform/set-env.sh"
    fi
else
    echo "❌ set-env.sh not found at /home/costas778/abc/trading-platform/set-env.sh"
    echo "Please check if the file was created correctly"
fi

# Summary of steps
echo ""
echo "Apply ./clear-aws-credentials.sh then login with aws configure in the CLI"
echo "Apply the WS_ACCESS_KEY_ID ,AWS_SECRET_ACCESS_KEY and the us-east-1 region"
echo "replace the WS_ACCESS_KEY_ID and,AWS_SECRET_ACCESS_KEY placeholders within set-env.sh"  
echo "type source set-env.sh in the cli"
echo "Apply ./aws-network-info.sh in the cli"
echo "Apply ./config_firstprod.sh to handle all the placeholders."
echo "Choose the abc-trading-prod.42web.io hosted zone."
echo "=== Configuration Update Complete ==="


echo "All files have been updated successfully!"
echo ""
echo "Next steps:"
echo "1. Run ./setup.sh <env>. You will have 5 Nodes to play with in each environment. During the install type q once and choose 1 for Init"
echo "and type your password to give elevated permissions to the installation"
echo "2. Run ./setup-freqtrade-ecr.sh to load the freqtrade image to ECR"
echo "3. Run ./build-freqtrade_enh.sh to deploy the image to the EKS cluster"
echo "./build-freqtrade_enh.sh -e prod -c blue -n blue"
echo "./build-freqtrade_enh.sh -e prod -c green -n green"
echo "4. Run ./fix-alb-controller-permissions.sh to allow ingress externally through the alb"
echo "run the following: kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue"
echo "run the following: kubectl get ingress -n freqtrade-prod-green freqtrade-ingress-green"
echo "5. Go create / Login into your DNS domain or subdomain account. I use a free one called"
echo "https://dash.infinityfree.com/ than create two CNAME records"
echo "Examaple: green.freqtrade-prod.abc-trading-prod.42web.io	CNAME
	 k8s-freqtradeprod-42931b6ddf-2098924394.us-east-1.elb.amazonaws.com "
echo "blue.freqtrade-prod.abc-trading-prod.42web.io	CNAME	
      k8s-freqtradeprod-42931b6ddf-2098924394.us-east-1.elb.amazonaws.com"
echo      
echo "6. For Blue Green deployment:"
echo "Run ./update-route53-files.sh to ensure that the Host Zone ID's are up to date"
echo "Run ./update-monitor-route53.sh to update both the ALB and Host Zone ID"
echo "Run ./monitor-route53-change-enh.sh . NOTE: update the hosted-zone-id and"
echo "the ALB value within the script" 
echo "aws route53 list-hosted-zones --query 'HostedZones[*].[Id,Name]' --output table"
echo "kubectl get ingress -n freqtrade-prod-blue freqtrade-ingress-blue"
echo
echo "   # 1. First, create the initial blue deployment with 100% traffic
./blue53.sh"
echo "  # 2. Deploy the green environment with 0% traffic
./green53.sh"
echo "  # 3. Start gradual traffic shift with 90/10 split
./90-10-split.sh"
echo "  # 4. Move to 75/25 split
./75-25-split.sh"
echo "  # 5. Finally, when ready, shift 100% to green
./green-100.sh"
echo
echo "7. Run ./monitoring-setup.sh to setup both Prometheus and Grafana"
echo "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "Then visit: http://localhost:3000"
echo "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "Then visit: http://localhost:9090"
echo
echo "8. Setup ARGO CLI if you haven't already ./install-argocd-cli.sh"
echo "NOTE: please make sure that the ARGO CLI is the same version as the server or ARGO CLI will"
echo "not let you logon!"
echo "Run the ./audit_argo.sh to check prerequisites"
echo "Now run ./install-argocd.sh"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "argocd login localhost:8080 --username admin --password <password> --insecure"
echo "http://localhost:8080"
echo "Run ./update-argocd-subnets.sh to update the subnets for the setup argocd ingress file"
echo "To setup ingress for ArgoCD run ./setup-argocd-ingress.sh"
echo "NOTE: update the subnets using the following"
echo "aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone,CidrBlock]' --output table"
echo "Then setup ingress using the DNS website. Example:  argocd.abc-trading-prod.42web.io"	
echo "CNAME	k8s-argocd-argocdse-eeecf6ab8d-1965126674.us-east-1.elb.amazonaws.com"
echo "Argo CD UI: http://argocd.abc-trading-prod.42web.io"
  




   
