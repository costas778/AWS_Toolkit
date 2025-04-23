#!/bin/bash
set -e

# Color coding for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to install ArgoCD CLI
install_argocd_cli() {
    echo -e "${YELLOW}Installing ArgoCD CLI v2.14.7...${NC}"
    curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/download/v2.14.7/argocd-linux-amd64
    chmod +x argocd
    sudo mv argocd /usr/local/bin/
}

# Check if ArgoCD CLI exists and install if needed
check_install_argocd_cli() {
    if ! command -v argocd &> /dev/null; then
        echo -e "${YELLOW}ArgoCD CLI not found. Installing...${NC}"
        install_argocd_cli
    else
        INSTALLED_VERSION=$(argocd version --client | head -n 1 | cut -d ' ' -f 2 | cut -d '+' -f 1)
        if [ "$INSTALLED_VERSION" != "v2.14.7" ]; then
            echo -e "${YELLOW}ArgoCD CLI version mismatch. Installing v2.14.7...${NC}"
            install_argocd_cli
        else
            echo -e "${GREEN}ArgoCD CLI v2.14.7 already installed${NC}"
        fi
    fi
}

# Execute the check and install
check_install_argocd_cli
