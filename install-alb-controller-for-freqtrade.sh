#!/bin/bash
set -e

echo "Installing AWS Load Balancer Controller for Freqtrade..."

# Get cluster name
CLUSTER_NAME=$(aws eks list-clusters --query 'clusters[0]' --output text)
if [ -z "$CLUSTER_NAME" ]; then
  echo "No EKS cluster found. Please specify your cluster name:"
  read -p "Cluster name: " CLUSTER_NAME
fi

echo "Using EKS cluster: $CLUSTER_NAME"

# Create IAM OIDC provider for the cluster if it doesn't exist
echo "Setting up IAM OIDC provider..."
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

# Create IAM policy for the ALB controller
echo "Creating IAM policy for ALB controller..."
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
  echo "Downloading IAM policy document..."
  curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

  echo "Creating IAM policy..."
  POLICY_ARN=$(aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json \
    --query 'Policy.Arn' --output text)
  
  rm iam-policy.json
fi

echo "IAM policy ARN: $POLICY_ARN"

# Create additional permissions policy for the ALB controller
echo "Creating additional permissions policy for ALB controller..."
cat << EOF > additional-permissions.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF

ADDITIONAL_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='ALBControllerAdditionalPermissions'].Arn" --output text)

if [ -z "$ADDITIONAL_POLICY_ARN" ]; then
  echo "Creating additional permissions policy..."
  ADDITIONAL_POLICY_ARN=$(aws iam create-policy \
    --policy-name ALBControllerAdditionalPermissions \
    --policy-document file://additional-permissions.json \
    --query 'Policy.Arn' --output text)
fi

echo "Additional IAM policy ARN: $ADDITIONAL_POLICY_ARN"
rm additional-permissions.json

# Create service account
echo "Creating service account..."
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=$POLICY_ARN \
  --attach-policy-arn=$ADDITIONAL_POLICY_ARN \
  --override-existing-serviceaccounts \
  --approve

# Install the AWS Load Balancer Controller using Helm
echo "Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "Installing AWS Load Balancer Controller..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Wait for the controller to be ready
echo "Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=aws-load-balancer-controller \
  --timeout=90s

echo "AWS Load Balancer Controller has been installed successfully!"
echo "You can now create Ingress resources with the ALB ingress class."
