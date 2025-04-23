#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Base directory
BASE_DIR="/home/costas778/abc/trading-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%dT%H:%M:%S%z')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%dT%H:%M:%S%z')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%dT%H:%M:%S%z')] ERROR: $1${NC}"
}

# Function to clean up Terraform files
cleanup_terraform() {
    local env=$1
    local terraform_dir="${BASE_DIR}/infrastructure/terraform/environments/${env}"
    
    log "Cleaning up Terraform files in ${terraform_dir}..."
    
    # Navigate to the Terraform directory
    cd "${terraform_dir}" || {
        error "Failed to change directory to ${terraform_dir}"
        return 1
    }
    
    # Remove Terraform files and directories
    log "Removing .terraform directory..."
    rm -rf .terraform/
    
    log "Removing terraform state files..."
    rm -f terraform.tfstate
    rm -f terraform.tfstate.backup
    
    log "Removing terraform lock file..."
    rm -f .terraform.lock.hcl
    
    log "Terraform cleanup completed"
}

# Main deployment function
deploy() {
    local env=$1
    
    if [ -z "$env" ]; then
        error "Environment parameter is required (dev|staging|prod)"
        echo "Usage: $0 <environment>"
        exit 1
    fi
    
    # Validate environment
    case "$env" in
        dev|staging|prod)
            log "Starting deployment for environment: $env"
            ;;
        *)
            error "Invalid environment. Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac
    
    # Clean up Terraform files first
    cleanup_terraform "$env"
    if [ $? -ne 0 ]; then
        error "Failed to clean up Terraform files"
        exit 1
    fi
    
    # Return to base directory
    cd "${BASE_DIR}" || {
        error "Failed to return to base directory"
        exit 1
    }
    
    # 1. Run main.sh
    if [ -f "${BASE_DIR}/main.sh" ]; then
        log "Running main.sh..."
        bash "${BASE_DIR}/main.sh" "$env"
        
        # Check if we need to run migrate_terraform_backend.sh
        if [ $? -ne 0 ]; then
            warn "main.sh encountered an error. This might be due to Terraform backend configuration."
            if [ -f "${BASE_DIR}/migrate_terraform_backend.sh" ]; then
                log "Running migrate_terraform_backend.sh to handle Terraform backend configuration..."
                bash "${BASE_DIR}/migrate_terraform_backend.sh" "$env"
                if [ $? -ne 0 ]; then
                    error "migrate_terraform_backend.sh failed"
                    exit 1
                fi
            else
                error "migrate_terraform_backend.sh not found in ${BASE_DIR}"
                exit 1
            fi
        fi
    else
        error "main.sh not found in ${BASE_DIR}"
        exit 1
    fi
    
    # 3. Run Post_main.sh with environment parameter
    if [ -f "${BASE_DIR}/Post_main.sh" ]; then
        log "Running Post_main.sh for environment: $env..."
        bash "${BASE_DIR}/Post_main.sh" "$env"
        if [ $? -ne 0 ]; then
            error "Post_main.sh failed"
            exit 1
        fi
    else
        error "Post_main.sh not found in ${BASE_DIR}"
        exit 1
    fi
    
    # 4. Run services.sh with environment parameter
    if [ -f "${BASE_DIR}/services.sh" ]; then
        log "Running services.sh for environment: $env..."
        bash "${BASE_DIR}/services.sh" "$env"
        if [ $? -ne 0 ]; then
            error "services.sh failed"
            exit 1
        fi
    else
        error "services.sh not found in ${BASE_DIR}"
        exit 1
    fi
    
    # Final check for ALB address
    log "Checking for ALB address..."
    echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
    for i in {1..12}; do
        ALB_ADDRESS=$(kubectl get ingress freqtrade-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$ALB_ADDRESS" ]; then
            log "ALB has been provisioned!"
            log "Your Freqtrade application is accessible at: http://$ALB_ADDRESS"
            break
        fi
        echo "Waiting for ALB address... (attempt $i/12)"
        sleep 15
    done
    
    log "Deployment completed successfully!"
}

# Script execution starts here
if [ "$0" = "$BASH_SOURCE" ]; then
    # Script is being run directly
    deploy "$1"
fi
