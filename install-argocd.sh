#!/bin/bash
set -e

# =============================================
# CONFIGURATION SECTION - ADJUST THESE VALUES
# =============================================
ARGOCD_NAMESPACE="argocd"                    # Your desired Argo CD namespace
ARGOCD_VERSION="7.8.13"                      # Argo CD version
MONITORING_NAMESPACE="monitoring"             # Your existing Prometheus namespace
PROMETHEUS_SERVICE_ACCOUNT="prometheus-kube-prometheus-prometheus"   # Your Prometheus service account name
DOMAIN_NAME="abc-trading-prod.42web.io"                # Your domain for Argo CD ingress
# =============================================

# Color coding for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local required_commands=("kubectl" "helm" "curl")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed.${NC}"
            exit 1
        fi
    done

    # Check kubectl context
    if ! kubectl config current-context &> /dev/null; then
        echo -e "${RED}No kubectl context found. Please configure kubectl first.${NC}"
        exit 1
    fi
}

# Function to install Argo CD
install_argocd() {
    echo -e "${YELLOW}Installing Argo CD...${NC}"

    # Create namespace if it doesn't exist
    kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Add Argo CD helm repository
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update

    # =============================================
    # ADJUST VALUES BELOW ACCORDING TO YOUR NEEDS
    # =============================================
 cat << EOF > argocd-values.yaml
# global:
#   image:
#     tag: v2.14.7

server:
  extraArgs:
    - --insecure  
  service:
    type: ClusterIP
  ingress:
    enabled: false    # Disable ingress in Helm chart
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
  config:
    timeout.reconciliation: 180s
    timeout.connection: 60s    
  
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

configs:
  params:
    server.insecure: true
EOF


    # Install Argo CD using Helm
    helm upgrade --install argocd argo/argo-cd \
        --namespace ${ARGOCD_NAMESPACE} \
        --version ${ARGOCD_VERSION} \
        --values argocd-values.yaml \
        --wait

    # Create Ingress matching your existing pattern
    echo -e "${YELLOW}Creating Ingress for Argo CD...${NC}"
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
spec:
  ingressClassName: alb
  rules:
    - host: argocd.${DOMAIN_NAME}
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

    # Verification section remains the same
    echo -e "${YELLOW}Verifying ingress creation...${NC}"
    if kubectl get ingress -n ${ARGOCD_NAMESPACE} argocd-server-ingress &> /dev/null; then
        echo -e "${GREEN}✓ Ingress created successfully${NC}"
        INGRESS_ADDRESS=$(kubectl get ingress -n ${ARGOCD_NAMESPACE} argocd-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        if [ -n "$INGRESS_ADDRESS" ]; then
            echo -e "${GREEN}✓ Load balancer address: ${INGRESS_ADDRESS}${NC}"
        fi
    else
        echo -e "${RED}✗ Ingress creation failed${NC}"
    fi
}


# Function to setup monitoring integration
setup_monitoring_integration() {
    echo -e "${YELLOW}Setting up monitoring integration...${NC}"

    # Check existing monitoring setup
    if ! kubectl get namespace ${MONITORING_NAMESPACE} &> /dev/null; then
        echo -e "${RED}Monitoring namespace ${MONITORING_NAMESPACE} not found!${NC}"
        echo -e "${YELLOW}Please ensure Prometheus is properly installed.${NC}"
        return 1
    fi

    # Setup RBAC for Prometheus to access Argo CD metrics
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-argocd
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["argoproj.io"]
  resources: ["applications", "appprojects"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["monitoring.coreos.com"]
  resources: ["servicemonitors"]
  verbs: ["get", "list", "watch", "create", "update"]
EOF

    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-argocd
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-argocd
subjects:
- kind: ServiceAccount
  name: ${PROMETHEUS_SERVICE_ACCOUNT}
  namespace: ${MONITORING_NAMESPACE}
EOF

    # Label namespace for Prometheus discovery
    kubectl label namespace ${ARGOCD_NAMESPACE} prometheus=monitor --overwrite

    # Create ServiceMonitor with both metrics endpoints
    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: argocd-metrics
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    release: prometheus
spec:
  endpoints:
  - targetPort: 8083
    path: /metrics
    interval: 30s
  - port: metrics
    interval: 30s
  namespaceSelector:
    matchNames:
    - ${ARGOCD_NAMESPACE}
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-metrics
EOF
}


# Function to verify setup
verify_setup() {
    echo -e "${YELLOW}Verifying setup...${NC}"

    # Wait for Argo CD server to be ready
    echo -e "${YELLOW}Waiting for Argo CD server...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ${ARGOCD_NAMESPACE}

    # # Wait for controller deployment
    # echo -e "${YELLOW}Waiting for controller deployment...${NC}"
    # kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n ${ARGOCD_NAMESPACE}
    
    # Wait for controller statefulset
    # echo -e "${YELLOW}Waiting for controller statefulset...${NC}"
    # kubectl wait --for=condition=Ready statefulset/argocd-application-controller -n ${ARGOCD_NAMESPACE} --timeout=300s
    

    # Get initial admin password with error handling
    INITIAL_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    if [ -z "$INITIAL_PASSWORD" ]; then
        INITIAL_PASSWORD=$(kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
    fi
    
    # Verify ServiceMonitor
    if kubectl get servicemonitor argocd-metrics -n ${ARGOCD_NAMESPACE} &> /dev/null; then
        echo -e "${GREEN}ServiceMonitor created successfully.${NC}"
    else
        echo -e "${RED}ServiceMonitor creation failed.${NC}"
    fi

    # Verify metrics endpoints with retry for controller
    echo -e "${YELLOW}Verifying metrics endpoints...${NC}"
    for component in server controller repo-server; do
        if kubectl get ep -n ${ARGOCD_NAMESPACE} argocd-${component}-metrics &> /dev/null; then
            echo -e "${GREEN}✓ argocd-${component}-metrics endpoint found${NC}"
        else
            if [ "$component" = "controller" ]; then
                echo -e "${YELLOW}Waiting for controller metrics to become available...${NC}"
                sleep 10
                if kubectl get ep -n ${ARGOCD_NAMESPACE} argocd-${component}-metrics &> /dev/null; then
                    echo -e "${GREEN}✓ argocd-${component}-metrics endpoint now available${NC}"
                else
                    echo -e "${RED}✗ argocd-${component}-metrics endpoint not found${NC}"
                fi
            else
                echo -e "${RED}✗ argocd-${component}-metrics endpoint not found${NC}"
            fi
        fi
    done
}

# Main execution
main() {
    echo -e "${YELLOW}Starting Argo CD deployment...${NC}"
    
    check_prerequisites
    install_argocd
    setup_monitoring_integration
    verify_setup

    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "\n${YELLOW}Access Information:${NC}"
    echo -e "Argo CD UI: http://argocd.${DOMAIN_NAME}"
    echo -e "Username: admin"
    if [ -n "$INITIAL_PASSWORD" ]; then
        echo -e "Password: ${INITIAL_PASSWORD}"
    else
        echo -e "${RED}Password not found. Please check the pods in the argocd namespace.${NC}"
    fi
    echo -e "\n${YELLOW}To access via port-forward:${NC}"
    echo "kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:80"
    echo -e "Then visit: http://localhost:8080"
    echo -e "\n${YELLOW}Initial password:${NC}"
    # echo "kubectl get pods -n ${ARGOCD_NAMESPACE} -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2"
    echo -e "Password: ${INITIAL_PASSWORD}"
}


# Execute main function
main "$@"
