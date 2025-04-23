#!/bin/bash

# Set error handling
set -e

# Color codes for output
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

# Variables
CLUSTER_NAME="abc-trading-dev"
ACCOUNT_ID="${AWS_ACCOUNT_ID}"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
ROLE_NAME="AmazonEKSLoadBalancerControllerRole"
REGION="${AWS_DEFAULT_REGION}"

# Logging functions
log() {
    printf "${GREEN}[%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    printf "${YELLOW}[%s] WARNING: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[%s] ERROR: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    exit 1
}

# Check if role exists and delete if necessary
check_and_cleanup_role() {
    log "Checking for existing IAM role..."
    if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null; then
        warn "Role ${ROLE_NAME} exists. Cleaning up..."
        
        # Remove role from service account if it exists
        if kubectl get serviceaccount -n kube-system aws-load-balancer-controller 2>/dev/null; then
            kubectl delete serviceaccount -n kube-system aws-load-balancer-controller
        fi
        
        # Delete existing CloudFormation stack if it exists
        STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
        if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" 2>/dev/null; then
            log "Deleting existing CloudFormation stack..."
            aws cloudformation delete-stack --stack-name "${STACK_NAME}"
            aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
        fi
        
        # Delete the IAM role
        log "Deleting IAM role..."
        aws iam delete-role --role-name "${ROLE_NAME}"
    fi
}

# Verify OIDC provider
verify_oidc_provider() {
    log "Verifying OIDC provider..."
    
    OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)
    if ! aws iam list-open-id-connect-providers | grep -q ${OIDC_ID}; then
        log "Creating OIDC provider..."
        eksctl utils associate-iam-oidc-provider \
            --region=${REGION} \
            --cluster=${CLUSTER_NAME} \
            --approve
    else
        log "OIDC provider already exists"
    fi
}

# Create IAM policy
create_iam_policy() {
    log "Creating IAM policy..."
    
    if [ ! -f "iam_policy.json" ]; then
        curl -s -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
    fi
    
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null; then
        aws iam create-policy \
            --policy-name ${POLICY_NAME} \
            --policy-document file://iam_policy.json
    else
        log "Policy already exists"
    fi
}

# Verify policy exists and is accessible
verify_policy() {
    log "Verifying IAM policy..."
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    if ! aws iam get-policy --policy-arn "${POLICY_ARN}" 2>/dev/null; then
        error "Policy ${POLICY_NAME} not found or not accessible"
    fi
}

# Create service account
create_service_account() {
    log "Creating IAM service account..."
    
    # Check if there's an existing failed stack and delete it
    STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" 2>/dev/null; then
        log "Found existing stack, cleaning up..."
        aws cloudformation delete-stack --stack-name "${STACK_NAME}"
        aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
    fi

    # Check and delete existing service account if present
    if kubectl get serviceaccount -n kube-system aws-load-balancer-controller 2>/dev/null; then
        log "Removing existing service account..."
        kubectl delete serviceaccount -n kube-system aws-load-balancer-controller
    fi

    # Verify OIDC provider is properly set up
    OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)
    if ! aws iam list-open-id-connect-providers | grep -q ${OIDC_ID}; then
        error "OIDC provider not found. Please ensure it's properly set up"
    fi

    # Create the service account with eksctl
    eksctl create iamserviceaccount \
        --cluster=${CLUSTER_NAME} \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name ${ROLE_NAME} \
        --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME} \
        --override-existing-serviceaccounts \
        --approve || {
            error_code=$?
            error "Failed to create IAM service account. Exit code: ${error_code}"
            # Get more details from CloudFormation
            aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
                --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
                --output text
            exit ${error_code}
        }
        
    # Verify service account creation
    kubectl get serviceaccount -n kube-system aws-load-balancer-controller || \
        error "Service account creation failed"
    
    log "Service account created successfully"
}

# Main execution
main() {
    log "Starting AWS Load Balancer Controller setup..."
    
    check_and_cleanup_role
    verify_oidc_provider
    create_iam_policy
    verify_policy
    create_service_account
    
    log "AWS Load Balancer Controller setup completed!"
}

# Execute main function
main "$@"

//////////////////////////////////

#!/bin/bash

# Set error handling
set -e

# Color codes for output
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
NC=$(printf '\033[0m')

# Variables
# CLUSTER_NAME="abc-trading-dev"
CLUSTER_NAME="${1:-abc-trading-dev}"  # Accept cluster name as parameter
ENVIRONMENT="${2:-dev}"
ACCOUNT_ID="${AWS_ACCOUNT_ID}"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
ROLE_NAME="AmazonEKSLoadBalancerControllerRole"
REGION="${AWS_DEFAULT_REGION}"

# Add parameter validation here
if [ "$#" -lt 2 ]; then
    error "Usage: $0 <cluster-name> <environment>"
fi

# Logging functions
log() {
    printf "${GREEN}[%s] %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

warn() {
    printf "${YELLOW}[%s] WARNING: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

error() {
    printf "${RED}[%s] ERROR: %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
    exit 1
}

# Check if role exists and delete if necessary
check_and_cleanup_role() {
    log "Checking for existing IAM role..."
    if aws iam get-role --role-name "${ROLE_NAME}" 2>/dev/null; then
        warn "Role ${ROLE_NAME} exists. Cleaning up..."
        
        # Remove role from service account if it exists
        if kubectl get serviceaccount -n kube-system aws-load-balancer-controller 2>/dev/null; then
            kubectl delete serviceaccount -n kube-system aws-load-balancer-controller
        fi
        
        # Delete existing CloudFormation stack if it exists
        STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
        if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" 2>/dev/null; then
            log "Deleting existing CloudFormation stack..."
            aws cloudformation delete-stack --stack-name "${STACK_NAME}"
            aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
        fi
        
        # Delete the IAM role
        log "Deleting IAM role..."
        aws iam delete-role --role-name "${ROLE_NAME}"
    fi
}

# Verify OIDC provider
verify_oidc_provider() {
    log "Verifying OIDC provider..."
    
    OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)
    if ! aws iam list-open-id-connect-providers | grep -q ${OIDC_ID}; then
        log "Creating OIDC provider..."
        eksctl utils associate-iam-oidc-provider \
            --region=${REGION} \
            --cluster=${CLUSTER_NAME} \
            --approve
    else
        log "OIDC provider already exists"
    fi
}

# Create IAM policy
create_iam_policy() {
    log "Creating IAM policy..."
    
    if [ ! -f "iam_policy.json" ]; then
        curl -s -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json
    fi
    
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null; then
        aws iam create-policy \
            --policy-name ${POLICY_NAME} \
            --policy-document file://iam_policy.json
    else
        log "Policy already exists"
    fi
}

# Verify policy exists and is accessible
verify_policy() {
    log "Verifying IAM policy..."
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    if ! aws iam get-policy --policy-arn "${POLICY_ARN}" 2>/dev/null; then
        error "Policy ${POLICY_NAME} not found or not accessible"
    fi
}

# Create service account
create_service_account() {
    log "Creating IAM service account..."
    
    # Check if there's an existing failed stack and delete it
    STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-kube-system-aws-load-balancer-controller"
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" 2>/dev/null; then
        log "Found existing stack, cleaning up..."
        aws cloudformation delete-stack --stack-name "${STACK_NAME}"
        aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
    fi

    # Check and delete existing service account if present
    if kubectl get serviceaccount -n kube-system aws-load-balancer-controller 2>/dev/null; then
        log "Removing existing service account..."
        kubectl delete serviceaccount -n kube-system aws-load-balancer-controller
    fi

    # Verify OIDC provider is properly set up
    OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d'/' -f5)
    if ! aws iam list-open-id-connect-providers | grep -q ${OIDC_ID}; then
        error "OIDC provider not found. Please ensure it's properly set up"
    fi

    # Create the service account with eksctl
    eksctl create iamserviceaccount \
        --cluster=${CLUSTER_NAME} \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name ${ROLE_NAME} \
        --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME} \
        --override-existing-serviceaccounts \
        --approve || {
            error_code=$?
            error "Failed to create IAM service account. Exit code: ${error_code}"
            # Get more details from CloudFormation
            aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
                --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
                --output text
            exit ${error_code}
        }
        
    # Verify service account creation
    kubectl get serviceaccount -n kube-system aws-load-balancer-controller || \
        error "Service account creation failed"
    
    log "Service account created successfully"
}

# Main execution
main() {
    log "Starting AWS Load Balancer Controller setup..."
    
    check_and_cleanup_role
    verify_oidc_provider
    create_iam_policy
    verify_policy
    create_service_account
    
    log "AWS Load Balancer Controller setup completed!"
}

# Execute main function
main "$@"
