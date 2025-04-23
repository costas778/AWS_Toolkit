#!/bin/bash

# monitoring-setup.sh
set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo_success() {
    echo -e "${GREEN}$1${NC}"
}

echo_error() {
    echo -e "${RED}$1${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl is not installed"
        exit 1
    fi

    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        echo_error "helm is not installed"
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        echo_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

# Check and scale nodes if needed
check_and_scale_nodes() {
    echo "Checking node capacity..."
    
    # Get current number of nodes
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    
    if [ "$NODE_COUNT" -lt 5 ]; then
        echo "Current node count ($NODE_COUNT) is less than 5. Scaling up..."
        # Get nodegroup name
        NODEGROUP_NAME=$(eksctl get nodegroup --cluster abc-trading-prod -o json | jq -r '.[0].Name')
        eksctl scale nodegroup --cluster abc-trading-prod --name "$NODEGROUP_NAME" --nodes 5
        
        # Wait for nodes to be ready
        echo "Waiting for nodes to be ready..."
        kubectl wait --for=condition=ready node --all --timeout=300s
    fi
}

# Install EBS CSI Driver
install_ebs_csi_driver() {
    echo "Installing EBS CSI Driver..."
    
    # Create IAM service account
    eksctl create iamserviceaccount \
        --name ebs-csi-controller-sa \
        --namespace kube-system \
        --cluster abc-trading-prod \
        --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
        --approve \
        --role-name AmazonEKS_EBS_CSI_DriverRole || true

    # Install EBS CSI Driver addon
    eksctl create addon \
        --name aws-ebs-csi-driver \
        --cluster abc-trading-prod \
        --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole \
        --force || true
}

# Create Storage Class
create_storage_class() {
    echo "Creating Storage Class..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
EOF
}

# Install Prometheus and Grafana
install_monitoring_stack() {
    echo "Installing Prometheus and Grafana..."
    
    # Add Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Install prometheus-operator
    helm install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --set grafana.adminPassword='admin' \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=ebs-sc \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
}

# Create ServiceMonitor for FreqTrade
create_service_monitor() {
    echo "Creating ServiceMonitor for FreqTrade..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: freqtrade-blue
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - freqtrade-prod-blue
  selector:
    matchLabels:
      app: freqtrade
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: freqtrade-green
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - freqtrade-prod-green
  selector:
    matchLabels:
      app: freqtrade
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF
}

# Setup port forwarding and print access information
setup_access() {
    echo "Setting up access..."
    
    # Get Grafana password
    GRAFANA_PASSWORD=$(kubectl -n monitoring get secret prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    
    echo_success "\nSetup completed successfully!"
    echo_success "\nGrafana Access:"
    echo "Username: admin"
    echo "Password: $GRAFANA_PASSWORD"
    echo "\nTo access Grafana UI:"
    echo "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    echo "Then visit: http://localhost:3000"
    
    echo "\nTo access Prometheus UI:"
    echo "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "Then visit: http://localhost:9090"
}

# Main execution
main() {
    check_prerequisites
    check_and_scale_nodes
    install_ebs_csi_driver
    create_storage_class
    install_monitoring_stack
    
    # Wait for Prometheus operator to be ready
    echo "Waiting for Prometheus operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus-kube-prometheus-operator -n monitoring
    
    create_service_monitor
    setup_access
}

# Run main function
main
