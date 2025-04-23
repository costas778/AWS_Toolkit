#!/bin/bash

# Exit on any error
set -e

echo "Starting ArgoCD ingress setup..."

# Create temporary ingress file
cat << 'EOF' > argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-port: traffic-port
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
  - host: argocd.abc-trading-prod.42web.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

echo "Created ingress configuration file"

# Tag subnets for ALB controller
echo "Tagging subnets for ALB controller..."

SUBNETS=(
    "subnet-0c76ae02a9cf7c33a"  # us-east-1a
    "subnet-0063288a4d139b467"  # us-east-1b
    "subnet-0c7ce543d6c060b28"  # us-east-1c
    )

for subnet in "${SUBNETS[@]}"; do
    echo "Tagging subnet: $subnet"
    aws ec2 create-tags \
        --resources "$subnet" \
        --tags Key=kubernetes.io/role/elb,Value=1
done

echo "Subnet tagging completed"

# Remove any existing ingress
echo "Removing existing ingress if any..."
kubectl delete ingress argocd-server-ingress -n argocd --ignore-not-found

# Apply new ingress
echo "Applying new ingress configuration..."
kubectl apply -f argocd-ingress.yaml

# Clean up the temporary file
rm argocd-ingress.yaml

echo "Waiting for ingress to be created..."
sleep 10

# Display ingress status
echo "Ingress status:"
kubectl get ingress -n argocd
kubectl describe ingress argocd-server-ingress -n argocd

echo "Setup completed. Please check the ingress status above for the ALB address."

echo "Create a DNS recrd in a provider like InfinityFree.com "
echo "CNAME argocd.abc-trading-prod.42web.io"
echo "Load external interface of Argocd with http://argocd.abc-trading-prod.42web.io"
echo "Please run dig argocd.abc-trading-prod.42web.io after making CNAME entry for verification"
echo "Please update subnets using"
echo "aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,VpcId,AvailabilityZone,CidrBlock]' --output table"  
