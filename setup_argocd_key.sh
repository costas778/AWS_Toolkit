#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is required but not installed."
        exit 1
    fi
}

# Function to check if ArgoCD namespace exists
check_argocd_namespace() {
    if ! kubectl get namespace argocd &> /dev/null; then
        print_error "ArgoCD namespace not found. Is ArgoCD installed?"
        exit 1
    fi
}

# Function to get current ArgoCD server pod
get_server_pod() {
    kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name 2>/dev/null | cut -d/ -f2
}

# Main script
echo "=== ArgoCD Server Key Setup ==="
echo

# Check prerequisites
print_status "Checking prerequisites..."
check_command kubectl
check_command openssl
check_argocd_namespace

# Get current server pod
SERVER_POD=$(get_server_pod)
if [ -z "$SERVER_POD" ]; then
    print_error "ArgoCD server pod not found"
    exit 1
fi
print_status "Found ArgoCD server pod: $SERVER_POD"

# Generate secret key
print_status "Generating new server secret key..."
SECRET_KEY=$(openssl rand -base64 32)
if [ $? -ne 0 ]; then
    print_error "Failed to generate secret key"
    exit 1
fi

# Confirm with user
echo
print_warning "This will patch the ArgoCD secret and restart the server pod."
read -p "Do you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Operation cancelled by user"
    exit 1
fi

# Patch the secret
echo
print_status "Patching ArgoCD secret..."
kubectl -n argocd patch secret argocd-secret \
    -p="{\"stringData\": {\"server.secretkey\": \"$SECRET_KEY\"}}" 2>/dev/null

if [ $? -ne 0 ]; then
    print_error "Failed to patch ArgoCD secret"
    exit 1
fi

# Restart the server pod
print_status "Restarting ArgoCD server pod..."
kubectl -n argocd delete pod $SERVER_POD 2>/dev/null

if [ $? -ne 0 ]; then
    print_error "Failed to restart ArgoCD server pod"
    exit 1
fi

# Wait for new pod
print_status "Waiting for new pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=60s 2>/dev/null

if [ $? -ne 0 ]; then
    print_error "Timeout waiting for ArgoCD server pod to be ready"
    exit 1
fi

# Get new pod name
NEW_POD=$(get_server_pod)
print_status "New ArgoCD server pod is ready: $NEW_POD"

echo
print_status "Setup complete! Try these commands to verify:"
echo
echo "1. Start port forwarding in a new terminal:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo
echo "2. Login using ArgoCD CLI:"
echo "   argocd login localhost:8080 --username admin --password $NEW_POD --insecure --plaintext"
echo

exit 0
