#!/bin/bash
# check-cert-integration.sh - Diagnostic script for certificate integration

# Set strict error handling
set -e

# Set working directory
WORK_DIR="/home/costas778/abc/trading-platform"
cd $WORK_DIR

echo "======================================================================================"
echo "CERTIFICATE INTEGRATION DIAGNOSTIC SCRIPT"
echo "This script will only check your current configuration without making any changes."
echo "======================================================================================"

# Function to print section headers
print_section() {
  echo
  echo "======================================================================================"
  echo "$1"
  echo "======================================================================================"
}

# Check Post-main.sh for certificate management and subscripts
print_section "1. CHECKING POST-MAIN.SH AND SUBSCRIPTS FOR CERTIFICATE MANAGEMENT"
if [ -f "$WORK_DIR/Post-main.sh" ]; then
  echo "Found Post-main.sh, searching for certificate-related commands..."
  CERT_LINES=$(grep -n "certificate\|cert\|tls\|ssl\|https" "$WORK_DIR/Post-main.sh" || echo "No matches found")
  
  if [ "$CERT_LINES" == "No matches found" ]; then
    echo "No certificate-related commands found in Post-main.sh"
  else
    echo "Certificate-related lines found in Post-main.sh:"
    echo "$CERT_LINES"
  fi
  
  # Look for subscript calls in Post-main.sh
  echo
  echo "Searching for subscript calls in Post-main.sh..."
  SUBSCRIPT_LINES=$(grep -n "source\|\.\/\|\. \/" "$WORK_DIR/Post-main.sh" || echo "No subscript calls found")
  
  if [ "$SUBSCRIPT_LINES" == "No subscript calls found" ]; then
    echo "No subscript calls found in Post-main.sh"
  else
    echo "Potential subscript calls found in Post-main.sh:"
    echo "$SUBSCRIPT_LINES"
    
    # Extract subscript paths and check them for certificate management
    echo
    echo "Analyzing subscripts for certificate management..."
    
    # Extract script paths using various patterns
    SCRIPT_PATHS=$(grep -E "source |\.\/|bash |sh |\.sh" "$WORK_DIR/Post-main.sh" | grep -v "^#" | sed -E 's/.*source +([^ ;]+).*/\1/;s/.*bash +([^ ;]+).*/\1/;s/.*sh +([^ ;]+).*/\1/;s/.*\. +([^ ;]+).*/\1/' | grep -v "^\$" || echo "")
    
    if [ -z "$SCRIPT_PATHS" ]; then
      echo "Could not extract subscript paths"
    else
      for SCRIPT_PATH in $SCRIPT_PATHS; do
        # Resolve relative paths
        if [[ "$SCRIPT_PATH" == "./"* ]]; then
          SCRIPT_PATH="${WORK_DIR}/${SCRIPT_PATH:2}"
        elif [[ "$SCRIPT_PATH" != "/"* ]]; then
          SCRIPT_PATH="${WORK_DIR}/${SCRIPT_PATH}"
        fi
        
        if [ -f "$SCRIPT_PATH" ]; then
          echo "Analyzing subscript: $SCRIPT_PATH"
          SUBSCRIPT_CERT_LINES=$(grep -n "certificate\|cert\|tls\|ssl\|https" "$SCRIPT_PATH" || echo "No certificate management found")
          
          if [ "$SUBSCRIPT_CERT_LINES" == "No certificate management found" ]; then
            echo "  No certificate management found in this subscript"
          else
            echo "  Certificate management found in subscript:"
            echo "$SUBSCRIPT_CERT_LINES"
          fi
        else
          echo "Subscript not found: $SCRIPT_PATH"
        fi
      done
    fi
    
    # Also look for any .sh files in the directory that might be related to certificates
    echo
    echo "Searching for certificate-related scripts in $WORK_DIR..."
    CERT_SCRIPTS=$(find "$WORK_DIR" -name "*.sh" -type f -exec grep -l "certificate\|cert\|tls\|ssl\|https" {} \; 2>/dev/null || echo "")
    
    if [ -z "$CERT_SCRIPTS" ]; then
      echo "No certificate-related scripts found"
    else
      echo "Found certificate-related scripts:"
      for SCRIPT in $CERT_SCRIPTS; do
        echo "  $SCRIPT"
        grep -n "certificate\|cert\|tls\|ssl\|https" "$SCRIPT" | head -5 | sed 's/^/    /'
        echo "    ..."
      done
    fi
  fi
else
  echo "Post-main.sh not found at $WORK_DIR/Post-main.sh"
fi

# Check for existing TLS secrets in Kubernetes
print_section "2. CHECKING FOR EXISTING TLS SECRETS IN KUBERNETES"
TLS_SECRETS=$(kubectl get secrets --all-namespaces | grep -i "tls\|cert\|ssl" || echo "No TLS secrets found")

if [ "$TLS_SECRETS" == "No TLS secrets found" ]; then
  echo "No TLS secrets found in any namespace"
else
  echo "Found TLS-related secrets:"
  echo "$TLS_SECRETS"
  
  # Get more details about the first TLS secret found
  FIRST_SECRET=$(echo "$TLS_SECRETS" | head -1)
  SECRET_NAME=$(echo "$FIRST_SECRET" | awk '{print $2}')
  SECRET_NAMESPACE=$(echo "$FIRST_SECRET" | awk '{print $1}')
  
  if [ ! -z "$SECRET_NAME" ]; then
    echo
    echo "Details for secret $SECRET_NAME in namespace $SECRET_NAMESPACE:"
    kubectl describe secret "$SECRET_NAME" -n "$SECRET_NAMESPACE" | grep -v "tls.key:"
  fi
fi

# Check for certificate files on the filesystem
print_section "3. CHECKING FOR CERTIFICATE FILES ON FILESYSTEM"
CERT_FILES=$(find "$WORK_DIR" -name "*.pem" -o -name "*.crt" -o -name "*.key" -o -name "*.cert" 2>/dev/null || echo "No certificate files found")

if [ "$CERT_FILES" == "No certificate files found" ]; then
  echo "No certificate files found in $WORK_DIR"
else
  echo "Found certificate files:"
  echo "$CERT_FILES"
  
  # Check the first certificate file found
  FIRST_CERT=$(echo "$CERT_FILES" | grep -E "\.pem$|\.crt$|\.cert$" | head -1)
  if [ ! -z "$FIRST_CERT" ] && [ -f "$FIRST_CERT" ]; then
    echo
    echo "Certificate information for $FIRST_CERT:"
    openssl x509 -in "$FIRST_CERT" -text -noout 2>/dev/null | grep -E "Subject:|Issuer:|Not Before:|Not After :|DNS:" || echo "Could not parse certificate"
  fi
fi

# Check existing ingress resources
print_section "4. CHECKING INGRESS RESOURCES FOR CERTIFICATE CONFIGURATION"
INGRESS_RESOURCES=$(kubectl get ingress --all-namespaces 2>/dev/null || echo "No ingress resources found")

if [ "$INGRESS_RESOURCES" == "No ingress resources found" ]; then
  echo "No ingress resources found in any namespace"
else
  echo "Found ingress resources:"
  echo "$INGRESS_RESOURCES"
  
  # Check for certificate annotations in ingresses
  echo
  echo "Checking for certificate annotations in ingress resources:"
  for NS in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
    for ING in $(kubectl get ingress -n $NS -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
      if [ ! -z "$ING" ]; then
        CERT_ANNOTATIONS=$(kubectl get ingress $ING -n $NS -o yaml | grep -E "certificate|tls|ssl" || echo "")
        if [ ! -z "$CERT_ANNOTATIONS" ]; then
          echo "Ingress $ING in namespace $NS has certificate configuration:"
          echo "$CERT_ANNOTATIONS"
          
          # Check if this ingress has TLS configuration
          TLS_CONFIG=$(kubectl get ingress $ING -n $NS -o jsonpath='{.spec.tls}' 2>/dev/null || echo "")
          if [ ! -z "$TLS_CONFIG" ] && [ "$TLS_CONFIG" != "null" ]; then
            echo "TLS configuration found in ingress $ING:"
            kubectl get ingress $ING -n $NS -o jsonpath='{.spec.tls}' | jq . 2>/dev/null || echo "$TLS_CONFIG"
          fi
        fi
      fi
    done
  done
fi

# Check AWS IAM server certificates
print_section "5. CHECKING AWS IAM SERVER CERTIFICATES"
IAM_CERTS=$(aws iam list-server-certificates 2>/dev/null || echo "Failed to list IAM certificates")

if [[ "$IAM_CERTS" == *"ServerCertificateMetadataList"* ]]; then
  echo "Found IAM server certificates:"
  echo "$IAM_CERTS" | jq '.ServerCertificateMetadataList[] | {Name: .ServerCertificateName, Arn: .Arn, Expiration: .Expiration}' 2>/dev/null || echo "$IAM_CERTS"
else
  echo "No IAM server certificates found or failed to retrieve them"
fi

# Check AWS ACM certificates
print_section "6. CHECKING AWS ACM CERTIFICATES"
ACM_CERTS=$(aws acm list-certificates 2>/dev/null || echo "Failed to list ACM certificates")

if [[ "$ACM_CERTS" == *"CertificateSummaryList"* ]]; then
  echo "Found ACM certificates:"
  echo "$ACM_CERTS" | jq '.CertificateSummaryList[] | {Domain: .DomainName, Arn: .CertificateArn}' 2>/dev/null || echo "$ACM_CERTS"
else
  echo "No ACM certificates found or failed to retrieve them"
fi

# Check AWS Load Balancer Controller
print_section "7. CHECKING AWS LOAD BALANCER CONTROLLER"
ALB_CONTROLLER=$(kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null || echo "AWS Load Balancer Controller not found")

if [[ "$ALB_CONTROLLER" == *"aws-load-balancer-controller"* ]]; then
  echo "AWS Load Balancer Controller is installed:"
  echo "$ALB_CONTROLLER"
  
  # Check controller version
  echo
  echo "Controller version:"
  kubectl get deployment -n kube-system aws-load-balancer-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "Could not determine version"
else
  echo "AWS Load Balancer Controller is not installed"
fi

# Check existing ALBs
print_section "8. CHECKING EXISTING APPLICATION LOAD BALANCERS"
ALBS=$(aws elbv2 describe-load-balancers 2>/dev/null || echo "Failed to list ALBs")

if [[ "$ALBS" == *"LoadBalancers"* ]]; then
  echo "Found Application Load Balancers:"
  echo "$ALBS" | jq '.LoadBalancers[] | {Name: .LoadBalancerName, DNS: .DNSName, ARN: .LoadBalancerArn}' 2>/dev/null || echo "$ALBS"
  
  # Check listeners for the first ALB
  FIRST_ALB_ARN=$(echo "$ALBS" | jq -r '.LoadBalancers[0].LoadBalancerArn' 2>/dev/null)
  if [ ! -z "$FIRST_ALB_ARN" ] && [ "$FIRST_ALB_ARN" != "null" ]; then
    echo
    echo "Checking listeners for ALB: $(echo "$ALBS" | jq -r '.LoadBalancers[0].LoadBalancerName' 2>/dev/null)"
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$FIRST_ALB_ARN" 2>/dev/null || echo "Failed to get listeners")
    
    if [[ "$LISTENERS" == *"Listeners"* ]]; then
      echo "Found listeners:"
      echo "$LISTENERS" | jq '.Listeners[] | {Protocol: .Protocol, Port: .Port, Certificates: .Certificates}' 2>/dev/null || echo "$LISTENERS"
    else
      echo "No listeners found or failed to retrieve them"
    fi
  fi
else
  echo "No Application Load Balancers found or failed to retrieve them"
fi

# Check Route 53 hosted zones
print_section "9. CHECKING ROUTE 53 HOSTED ZONES"
HOSTED_ZONES=$(aws route53 list-hosted-zones 2>/dev/null || echo "Failed to list hosted zones")

if [[ "$HOSTED_ZONES" == *"HostedZones"* ]]; then
  echo "Found Route 53 hosted zones:"
  echo "$HOSTED_ZONES" | jq '.HostedZones[] | {Name: .Name, Id: .Id, Private: .Config.PrivateZone}' 2>/dev/null || echo "$HOSTED_ZONES"
else
  echo "No Route 53 hosted zones found or failed to retrieve them"
fi

# Summary and recommendations
print_section "10. SUMMARY AND RECOMMENDATIONS"
echo "Based on the checks performed, here's a summary of your certificate setup:"

# Check if we found any certificate management in scripts
if [ "$CERT_SCRIPTS" != "" ]; then
  echo "✅ Found scripts with certificate management - review these for integration"
else
  echo "❌ No scripts with certificate management found"
fi

# Check if we found any TLS secrets
if [ "$TLS_SECRETS" != "No TLS secrets found" ]; then
  echo "✅ Kubernetes TLS secrets found - you can reference these in your ingress configuration"
else
  echo "❌ No Kubernetes TLS secrets found - you may need to create one from your certificates"
fi

# Check if we found certificate files
if [ "$CERT_FILES" != "No certificate files found" ]; then
  echo "✅ Certificate files found on filesystem - these can be used to create Kubernetes secrets"
else
  echo "❌ No certificate files found - you may need to generate self-signed certificates"
fi

# Check if we found ingress with TLS
INGRESS_WITH_TLS=$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq '.items[] | select(.spec.tls != null)' 2>/dev/null || echo "")
if [ ! -z "$INGRESS_WITH_TLS" ]; then
  echo "✅ Ingress resources with TLS configuration found - you can follow similar patterns"
else
  echo "❌ No ingress resources with TLS configuration found"
fi

# Check if ALB controller is installed
if [[ "$ALB_CONTROLLER" == *"aws-load-balancer-controller"* ]]; then
  echo "✅ AWS Load Balancer Controller is installed - required for ALB ingress"
else
  echo "❌ AWS Load Balancer Controller not found - may need to install it"
fi

# Check if we found ALBs with HTTPS
HTTPS_LISTENERS=$(echo "$LISTENERS" | jq '.Listeners[] | select(.Protocol == "HTTPS")' 2>/dev/null || echo "")
if [ ! -z "$HTTPS_LISTENERS" ]; then
  echo "✅ ALB with HTTPS listeners found - certificates are already configured"
else
  echo "❌ No ALB with HTTPS listeners found - you may need to configure HTTPS"
fi

echo
echo "======================================================================================"
echo "DIAGNOSTIC COMPLETE - NO CHANGES WERE MADE"
echo "======================================================================================"
echo
echo "Next steps:"
echo "1. Review the findings above to understand your current certificate setup"
echo "2. Pay special attention to any subscripts that manage certificates"
echo "3. Based on these findings, determine the best approach for integrating Zipline"
echo "4. Run the appropriate integration script that aligns with your existing infrastructure"
