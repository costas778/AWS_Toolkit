#!/bin/bash
# wrapper2.sh - Post-infrastructure component setup

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check what components exist
check_component_status() {
    echo "Checking existing components..."
    
    # Check ECR
    if aws ecr describe-repositories --repository-names "trading-platform" &>/dev/null; then
        echo "ECR repositories exist - skipping creation"
        ECR_EXISTS=true
    fi

    # Check ALB Controller
    if kubectl get deployment -n kube-system aws-load-balancer-controller &>/dev/null; then
        echo "ALB Controller exists - skipping installation"
        ALB_EXISTS=true
    fi

    # Check Ingress
    if kubectl get ingress -n trading-platform &>/dev/null; then
        echo "Ingress rules exist - skipping setup"
        INGRESS_EXISTS=true
    fi

    # Check if deployments exist
    if kubectl get deployment market-data &>/dev/null; then
        echo "K8s deployments exist - skipping creation"
        DEPLOYMENTS_EXIST=true
    fi
}

# Install only missing components
deploy_missing_components() {
    local env=$1
    
    # ECR Setup & Image Push
    if [ "$ECR_EXISTS" != "true" ]; then
        echo "Setting up ECR repositories..."
        "${SCRIPT_DIR}/setup-ecr-deployments.sh" "$env"
    fi

    # ALB Controller
    if [ "$ALB_EXISTS" != "true" ]; then
        echo "Installing ALB Controller..."
        #"${SCRIPT_DIR}/install-alb-controller.sh" "$env"
        "${SCRIPT_DIR}/install-alb-controller.sh" "abc-trading-${env}" "${env}"
    fi

    # Create K8s Deployments if they don't exist
    if [ "$DEPLOYMENTS_EXIST" != "true" ]; then
        echo "Creating initial K8s deployments..."
        "${SCRIPT_DIR}/create-k8s-deployments.sh"
    fi

    # Apply patches (including SSL certificates and resource limits)
    echo "Applying deployment patches..."
    "${SCRIPT_DIR}/create-patches.sh"

    # Service Deployments (always run to ensure latest state)
    echo "Updating service deployments..."
    "${SCRIPT_DIR}/deploy-services.sh" "$env"

    # Ingress Setup
    if [ "$INGRESS_EXISTS" != "true" ]; then
        echo "Setting up ingress rules..."
        "${SCRIPT_DIR}/post-deploy-ingress.sh" "$env"
    fi
}

main() {
    local env=$1
    
    if [ -z "$env" ]; then
        echo "Usage: $0 <environment>"
        exit 1
    fi

    check_component_status
    deploy_missing_components "$env"
    
    echo "Post-infrastructure setup complete!"
}

main "$@"
