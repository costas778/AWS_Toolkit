#!/bin/bash

echo "=== ArgoCD Integration Requirements Audit ==="
echo

# Check AWS CLI and kubectl configuration
echo "=== Checking Basic Requirements ==="
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found"
else
    echo "✅ AWS CLI installed"
    echo "Current AWS Profile: $(aws configure list | grep profile | awk '{print $2}')"
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found"
else
    echo "✅ kubectl installed"
    echo "Current context: $(kubectl config current-context)"
fi

echo -e "\n=== EKS Cluster Information ==="
# Get EKS cluster details
CLUSTER_NAME=$(aws eks list-clusters --output text --query 'clusters[0]')
if [ ! -z "$CLUSTER_NAME" ]; then
    echo "✅ EKS Cluster found: $CLUSTER_NAME"
    CLUSTER_VERSION=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.version' --output text)
    echo "Cluster version: $CLUSTER_VERSION"
else
    echo "❌ No EKS clusters found"
fi

echo -e "\n=== ECR Repositories ==="
# List ECR repositories
aws ecr describe-repositories --query 'repositories[].repositoryName' --output table

echo -e "\n=== Kubernetes RBAC Information ==="
echo "Current cluster roles:"
kubectl get clusterroles --no-headers | wc -l

echo "Current cluster role bindings:"
kubectl get clusterrolebindings --no-headers | wc -l

echo -e "\n=== Namespace Information ==="
echo "Current namespaces:"
kubectl get namespaces

echo -e "\n=== Service Account Information ==="
echo "Service accounts across all namespaces:"
kubectl get serviceaccounts --all-namespaces | grep -v 'default' | grep -v 'NAMESPACE'

echo -e "\n=== Git Repository Check ==="
if ! command -v git &> /dev/null; then
    echo "❌ Git not found"
else
    echo "✅ Git installed"
    if [ -d .git ]; then
        echo "Current repository remote(s):"
        git remote -v
    else
        echo "Not in a git repository"
    fi
fi

echo -e "\n=== IAM Roles for Service Accounts (IRSA) ==="
# Check if IRSA is configured
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null | cut -d'/' -f5)
if [ ! -z "$OIDC_ID" ]; then
    echo "✅ OIDC provider ID: $OIDC_ID"
else
    echo "❌ OIDC provider not configured"
fi

echo -e "\n=== Current Deployments ==="
echo "Deployments across all namespaces:"
kubectl get deployments --all-namespaces

echo -e "\n=== Storage Classes ==="
kubectl get storageclasses

echo -e "\n=== Load Balancer Services ==="
kubectl get svc --all-namespaces | grep LoadBalancer

echo -e "\n=== Recommendations ==="
echo "1. Create ArgoCD namespace"
echo "2. Set up IRSA for ArgoCD"
echo "3. Configure ECR pull permissions"
echo "4. Set up Git repository access"
echo "5. Create necessary RBAC roles"

echo -e "\n=== Required Actions ==="
[ -z "$CLUSTER_NAME" ] && echo "❌ EKS cluster needs to be created"
[ -z "$OIDC_ID" ] && echo "❌ OIDC provider needs to be configured"
! kubectl get namespace argocd >/dev/null 2>&1 && echo "❌ ArgoCD namespace needs to be created"

echo -e "\nAudit complete. Please review the information above."
