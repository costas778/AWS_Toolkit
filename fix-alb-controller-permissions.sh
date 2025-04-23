#!/bin/bash
set -e

# Debug mode - uncomment the next line if you want to see all commands being executed
# set -x

# Function to log messages with timestamps
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Determine environment from cluster name
CURRENT_CONTEXT=$(kubectl config current-context)
log_message "Current kubectl context: $CURRENT_CONTEXT"

if [[ $CURRENT_CONTEXT == *"-staging" ]]; then
    ENV="staging"
elif [[ $CURRENT_CONTEXT == *"-dev" ]]; then
    ENV="dev"
elif [[ $CURRENT_CONTEXT == *"-prod" ]]; then    # Add this block
    ENV="prod"
else
    log_message "Error: Unable to determine environment from context: $CURRENT_CONTEXT"
    log_message "Current context should contain either '-staging', '-dev', or '-prod'"
    exit 1
fi

log_message "Detected environment: ${ENV}"

# Set environment-specific variables
ROLE_NAME="AmazonEKSLoadBalancerControllerRole-${ENV}"
POLICY_NAME="AmazonEKSLoadBalancerControllerPolicy-${ENV}"

log_message "Using Role Name: ${ROLE_NAME}"
log_message "Using Policy Name: ${POLICY_NAME}"

# Check if policy exists
EXISTING_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)

if [ -n "$EXISTING_POLICY_ARN" ]; then
    log_message "Found existing policy: $EXISTING_POLICY_ARN"
    log_message "Checking policy versions..."
    
    # List and delete non-default versions if they exist
    VERSIONS=$(aws iam list-policy-versions --policy-arn "$EXISTING_POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    
    if [ -n "$VERSIONS" ]; then
        log_message "Deleting non-default policy versions: $VERSIONS"
        for version in $VERSIONS; do
            log_message "Deleting version: $version"
            aws iam delete-policy-version --policy-arn "$EXISTING_POLICY_ARN" --version-id "$version"
        done
    fi
fi

echo "Creating ALB Controller policy file..."
cat > alb-controller-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAccountAttributes",
                "ec2:DescribeAddresses",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeTags",
                "ec2:GetCoipPoolUsage",
                "ec2:DescribeCoipPools",
                "ec2:GetSecurityGroupsForVpc",
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags",
                "elasticloadbalancing:DescribeListenerAttributes",
                "elasticloadbalancing:ModifyListenerAttributes",
                "elasticloadbalancing:DescribeTrustStores"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "waf-regional:GetWebACL",
                "waf-regional:GetWebACLForResource",
                "waf-regional:AssociateWebACL",
                "waf-regional:DisassociateWebACL",
                "wafv2:GetWebACL",
                "wafv2:GetWebACLForResource",
                "wafv2:AssociateWebACL",
                "wafv2:DisassociateWebACL",
                "shield:GetSubscriptionState",
                "shield:DescribeProtection",
                "shield:CreateProtection",
                "shield:DeleteProtection"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSecurityGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": "CreateSecurityGroup"
                },
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DeleteTags"
            ],
            "Resource": "arn:aws:ec2:*:*:security-group/*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:DeleteSecurityGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
            ],
            "Condition": {
                "Null": {
                    "aws:RequestTag/elbv2.k8s.aws/cluster": "true",
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:ModifyTargetGroup",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:DeleteTargetGroup"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets"
            ],
            "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:SetWebAcl",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:ModifyRule"
            ],
            "Resource": "*"
        }
    ]
}
EOF

echo "Creating or updating IAM policy for AWS Load Balancer Controller..."
#aws iam create-policy --policy-name AmazonEKSLoadBalancerControllerPolicy --policy-document file://alb-controller-policy.json || aws iam update-policy --policy-name AmazonEKSLoadBalancerControllerPolicy --policy-document file://alb-controller-policy.json
aws iam create-policy --policy-name "${POLICY_NAME}" --policy-document file://alb-controller-policy.json || aws iam update-policy --policy-name "${POLICY_NAME}" --policy-document file://alb-controller-policy.json


echo "Getting policy ARN..."
#POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AmazonEKSLoadBalancerControllerPolicy`].Arn' --output text)
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)
echo "Policy ARN: $POLICY_ARN"

echo "Attaching policy to role..."
#aws iam attach-role-policy --role-name AmazonEKSLoadBalancerControllerRole --policy-arn $POLICY_ARN
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn $POLICY_ARN


echo "Restarting AWS Load Balancer Controller pods..."
#kubectl delete pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl --context=${CURRENT_CONTEXT} delete pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller


echo "Waiting for controller pods to restart..."
sleep 10

echo "Checking controller pod status..."
#kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl --context=${CURRENT_CONTEXT} get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller


echo "Waiting for controller pods to be ready..."
#kubectl wait --for=condition=Ready pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s
kubectl --context=${CURRENT_CONTEXT} wait --for=condition=Ready pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s


echo "Deleting existing ingress if it exists..."
#kubectl delete ingress freqtrade-ingress --ignore-not-found=true
#kubectl delete ingress freqtrade-ingress -n freqtrade-${ENV} --ignore-not-found=true
kubectl --context=${CURRENT_CONTEXT} delete ingress freqtrade-ingress -n freqtrade-${ENV} --ignore-not-found=true


echo "Finding ingress YAML file..."
INGRESS_FILE=$(find ~/abc -name "freqtrade-ingress.yaml")
echo "Found ingress file at: $INGRESS_FILE"

echo "Applying ingress YAML..."
#kubectl apply -f $INGRESS_FILE
kubectl --context=${CURRENT_CONTEXT} apply -f $INGRESS_FILE


echo "Waiting for ingress to be created..."
sleep 10

echo "Checking ingress status..."
#kubectl get ingress freqtrade-ingress
kubectl get ingress freqtrade-ingress -n freqtrade-${ENV}
kubectl --context=${CURRENT_CONTEXT} get ingress freqtrade-ingress -n freqtrade-${ENV}



echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
for i in {1..12}; do
  ALB_ADDRESS=$(kubectl get ingress freqtrade-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$ALB_ADDRESS" ]; then
    echo "ALB has been provisioned!"
    echo "Your Freqtrade application is accessible at: http://$ALB_ADDRESS"
    break
  fi
  echo "Waiting for ALB address... (attempt $i/12)"
  sleep 15
done

if [ -z "$ALB_ADDRESS" ]; then
  echo "ALB is still being provisioned. Check the status with:"
  #echo "kubectl get ingress freqtrade-ingress -n freqtrade"
  echo "kubectl get ingress -n freqtrade-${ENV}green freqtrade-ingress-green"
  echo "kubectl get ingress -n freqtrade-${ENV}blue freqtrade-ingress-blue"
#   echo "kubectl get ingress freqtrade-ingress -n freqtrade-${ENV}"
  echo "Current context: ${ENV}"
fi

echo "Script completed!"
