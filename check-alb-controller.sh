#!/bin/bash

echo "Checking AWS Load Balancer Controller installation..."

# Check deployment
echo -n "Checking deployment: "
if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
  echo "✅ Found"
  DEPLOYMENT_STATUS=$(kubectl get deployment -n kube-system aws-load-balancer-controller -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
  echo "   Ready pods: $DEPLOYMENT_STATUS"
else
  echo "❌ Not found"
fi

# Check pods
echo -n "Checking pods: "
PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if [ -n "$PODS" ]; then
  if [[ "$PODS" == *"Running"* ]]; then
    echo "✅ Running"
  else
    echo "❌ Not running (status: $PODS)"
  fi
else
  echo "❌ No pods found"
fi

# Check CRDs
echo -n "Checking CRDs: "
if kubectl get crds | grep -q 'elbv2.k8s.aws'; then
  echo "✅ Found"
else
  echo "❌ Not found"
fi

# Check IngressClass
echo -n "Checking IngressClass: "
if kubectl get ingressclass alb &> /dev/null; then
  echo "✅ Found"
else
  echo "❌ Not found"
fi

# Check service account
echo -n "Checking service account: "
if kubectl get serviceaccount -n kube-system aws-load-balancer-controller &> /dev/null; then
  echo "✅ Found"
else
  echo "❌ Not found"
fi

# Overall status
echo ""
if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null && \
   [[ "$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[*].status.phase}')" == *"Running"* ]] && \
   kubectl get crds | grep -q 'elbv2.k8s.aws'; then
  echo "AWS Load Balancer Controller appears to be installed and running correctly."
else
  echo "AWS Load Balancer Controller is not installed or not running correctly."
fi

# Check for Freqtrade ingress and get ALB address
echo ""
echo "Checking for Freqtrade ingress and ALB..."
if kubectl get ingress freqtrade-ingress &> /dev/null; then
  echo "✅ Freqtrade ingress found"
  
  # Get the ALB address
  ALB_ADDRESS=$(kubectl get ingress freqtrade-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  
  if [ -n "$ALB_ADDRESS" ]; then
    echo "✅ ALB has been provisioned"
    echo "Your Freqtrade application is accessible at: http://$ALB_ADDRESS"
  else
    echo "❌ ALB address not found. The ALB may still be provisioning."
    echo "Run this command to check again later:"
    echo "  kubectl get ingress freqtrade-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  fi
else
  echo "❌ Freqtrade ingress not found"
  echo "If you've deployed Freqtrade, check its status with:"
  echo "  kubectl get ingress"
fi
