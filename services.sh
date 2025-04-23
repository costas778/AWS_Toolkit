#!/bin/bash

# Handle environment argument
ENV=$1
if [ -z "$ENV" ]; then
    echo "Error: Environment not specified"
    echo "Usage: ./services.sh <env>"
    exit 1
fi

# debug statements
echo "DEBUG services.sh: Environment parameter received: $1"
echo "DEBUG services.sh: ENV variable is: $ENV"

# Set CLUSTER_NAME based on environment
CLUSTER_NAME="abc-trading-${ENV}"

# Add these debug lines at the start of services.sh
echo "Debug: CLUSTER_NAME is ${CLUSTER_NAME}"
echo "Debug: Current kubectl context is $(kubectl config current-context)"


# Add at the beginning of services.sh
echo "Cleaning up existing deployments..."
kubectl delete deployment --all
sleep 10  # Wait for cleanup

# debug statements
echo "DEBUG services.sh: Starting nodegroup scaling..."
echo "DEBUG services.sh: Target nodegroup: ${CLUSTER_NAME}-nodes"

# Scale the nodegroup to 5 nodes
echo "Scaling nodegroup to 5 or more nodes..."
eksctl scale nodegroup \
  --cluster="${CLUSTER_NAME}" \
  --name="${CLUSTER_NAME}-nodes" \
  --nodes=5

eksctl scale nodegroup \
  --cluster abc-trading-prod \
  --name abc-trading-prod-nodes \
  --nodes-min 2 \
  --nodes-max 5 \
  --nodes 5

sleep 60  # Wait for nodes to be ready


# Define all services
all_services="api-gateway authentication authorization audit cache compliance logging market-data message-queue notification order-management portfolio-management position-management price-feed quote-service reporting risk-management settlement trade-execution user-management"

# debug statements
echo "DEBUG services.sh: Number of services to deploy: $(echo $all_services | wc -w)"
echo "DEBUG services.sh: Services list: $all_services"

# Deploy each service
for service in $all_services; do
    echo "Deploying $service..."
    kubectl create deployment $service --image=339712995243.dkr.ecr.us-east-1.amazonaws.com/$service:latest
      # Set smaller resource requests and limits
    # kubectl set resources deployment $service \
    # --requests=cpu=50m,memory=128Mi \
    # --limits=cpu=100m,memory=256Mi
    sleep 30  # Wait for pod to stabilize
    
    # Verify pod status
    kubectl get pods -l app=$service
done

# Verify all deployments
kubectl get deployments

# Scale all deployments to 2 replicas
echo "Scaling all deployments to 2 replicas..."
kubectl scale deployment --all --replicas=2

# Verify deployments
echo "Verifying deployments..."
kubectl get deployments --all-namespaces
echo "Verifying services..."
kubectl get services --all-namespaces
echo "Verifying pods..."
kubectl get pods --all-namespaces
echo "get nodes"
kubectl get nodes

# Add your patch command here
echo "Patching authentication service port configuration..."
kubectl patch service authentication -n default -p '{"spec":{"ports":[{"port":8087,"targetPort":8080}]}}'