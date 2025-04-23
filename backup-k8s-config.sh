#!/bin/bash

# Color coding for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create backup directory with timestamp
BACKUP_DIR="k8s_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Function to perform backup with verification
backup_resource() {
    local resource=$1
    local namespace=$2
    local filename=$3
    
    echo -e "${YELLOW}Backing up ${resource} from namespace ${namespace}...${NC}"
    
    if kubectl get ${resource} -n ${namespace} &> /dev/null; then
        kubectl get ${resource} -n ${namespace} -o yaml > "${BACKUP_DIR}/${filename}"
        if [ -s "${BACKUP_DIR}/${filename}" ]; then
            echo -e "${GREEN}✓ Successfully backed up to ${filename}${NC}"
        else
            echo -e "${RED}✗ Backup file ${filename} is empty${NC}"
        fi
    else
        echo -e "${YELLOW}No ${resource} found in namespace ${namespace}${NC}"
    fi
}

# Function to discover and output configuration values
discover_config_values() {
    echo -e "\n${YELLOW}Discovering Configuration Values...${NC}"
    
    # Find monitoring namespace
    echo -e "\n${YELLOW}Looking for monitoring namespace...${NC}"
    MONITORING_NS=$(kubectl get ns | grep -E 'monitoring|prometheus' | awk '{print $1}')
    if [ -n "$MONITORING_NS" ]; then
        echo -e "${GREEN}Found monitoring namespace: ${MONITORING_NS}${NC}"
    else
        echo -e "${RED}No monitoring namespace found${NC}"
    fi

    # # Find Prometheus service account
    # echo -e "\n${YELLOW}Looking for Prometheus service account...${NC}"
    # PROM_SA=$(kubectl get sa -n ${MONITORING_NS:-monitoring} | grep -E 'prometheus|prom' | awk '{print $1}')
    # if [ -n "$PROM_SA" ]; then
    #     echo -e "${GREEN}Found Prometheus service account: ${PROM_SA}${NC}"
    # else
    #     echo -e "${RED}No Prometheus service account found${NC}"
    # fi

     # Find Prometheus service account
    echo -e "\n${YELLOW}Looking for Prometheus service account...${NC}"
    PROM_SA=$(kubectl get sa -n ${MONITORING_NS:-monitoring} | grep -E 'prometheus|prom' | awk '{print $1}')
    if [ -n "$PROM_SA" ]; then
        echo -e "${GREEN}Found Prometheus service account: ${PROM_SA}${NC}"
    else
        echo -e "${RED}No Prometheus service account found${NC}"
    fi

     # Check set-env.sh first for domain
    echo -e "\n${YELLOW}Checking set-env.sh for domain configuration...${NC}"
    if [ -f "set-env.sh" ]; then
        SET_ENV_DOMAIN=$(grep DOMAIN_NAME set-env.sh | cut -d'"' -f2)
        if [ -n "$SET_ENV_DOMAIN" ]; then
            echo -e "${GREEN}Found domain in set-env.sh: ${SET_ENV_DOMAIN}${NC}"
            DOMAIN_NAME="${SET_ENV_DOMAIN}"
        else
            echo -e "${YELLOW}No domain found in set-env.sh, will check EKS cluster...${NC}"
        fi
    else
        echo -e "${YELLOW}set-env.sh not found, will check EKS cluster...${NC}"
    fi

    # # Get EKS cluster info
    # echo -e "\n${YELLOW}Getting EKS cluster information...${NC}"
    # if command -v aws &> /dev/null; then
    #     CLUSTER_NAME=$(aws eks list-clusters --query 'clusters[0]' --output text)
    #     if [ -n "$CLUSTER_NAME" ]; then
    #         DOMAIN_NAME=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text | sed 's/https:\/\///')
    #         echo -e "${GREEN}Found EKS cluster domain: ${DOMAIN_NAME}${NC}"
    #     else
    #         echo -e "${RED}No EKS cluster found${NC}"
    #     fi
    # else
    #     echo -e "${RED}AWS CLI not installed${NC}"
    # fi

    # Get latest Argo CD version
    echo -e "\n${YELLOW}Getting latest Argo CD version...${NC}"
    if command -v curl &> /dev/null; then
        ARGOCD_VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        echo -e "${GREEN}Latest Argo CD version: ${ARGOCD_VERSION}${NC}"
    else
        echo -e "${RED}curl not installed${NC}"
    fi

    # Output discovered values in format suitable for the main script
    echo -e "\n${YELLOW}Configuration Values Summary:${NC}"
    cat << EOF > "${BACKUP_DIR}/discovered_config.txt"
# =============================================
# DISCOVERED CONFIGURATION VALUES
# =============================================
ARGOCD_NAMESPACE="argocd"                    # Default Argo CD namespace
ARGOCD_VERSION="${ARGOCD_VERSION:-7.8.13}"   # Latest discovered version
MONITORING_NAMESPACE="${MONITORING_NS}"       # Discovered monitoring namespace
PROMETHEUS_SERVICE_ACCOUNT="${PROM_SA}"      # Discovered Prometheus service account
DOMAIN_NAME="${DOMAIN_NAME}"                 # Discovered domain name
# =============================================
EOF

    cat "${BACKUP_DIR}/discovered_config.txt"
}

# Main backup process
echo -e "${YELLOW}Starting backup process...${NC}"

# Backup monitoring configurations
backup_resource "configmap" "monitoring" "monitoring-configmaps.yaml"
backup_resource "secret" "monitoring" "monitoring-secrets.yaml"

# Backup ServiceMonitors
backup_resource "servicemonitor" "monitoring" "servicemonitors.yaml"

# Backup RBAC configurations
echo -e "${YELLOW}Backing up RBAC configurations...${NC}"
kubectl get clusterrole,clusterrolebinding -o yaml > "${BACKUP_DIR}/rbac-backup.yaml"
if [ -s "${BACKUP_DIR}/rbac-backup.yaml" ]; then
    echo -e "${GREEN}✓ Successfully backed up RBAC configurations${NC}"
fi

# Backup Prometheus configuration
backup_resource "prometheus" "monitoring" "prometheus-config.yaml"

# Backup network policies
echo -e "${YELLOW}Backing up NetworkPolicies...${NC}"
kubectl get networkpolicy --all-namespaces -o yaml > "${BACKUP_DIR}/network-policies.yaml"
if [ -s "${BACKUP_DIR}/network-policies.yaml" ]; then
    echo -e "${GREEN}✓ Successfully backed up NetworkPolicies${NC}"
fi

# Create verification file
echo "Backup completed at $(date)" > "${BACKUP_DIR}/backup-verification.txt"
echo "Backup location: $(pwd)/${BACKUP_DIR}" >> "${BACKUP_DIR}/backup-verification.txt"

# List all backed up files with sizes
echo -e "\n${YELLOW}Backup Summary:${NC}"
ls -lh "${BACKUP_DIR}"

# Discover and output configuration values
discover_config_values

echo -e "\n${GREEN}Backup and configuration discovery completed!${NC}"
echo -e "${YELLOW}Backup directory: $(pwd)/${BACKUP_DIR}${NC}"
echo -e "${YELLOW}Configuration values saved to: ${BACKUP_DIR}/discovered_config.txt${NC}"

# Verify backup integrity
echo -e "\n${YELLOW}Verifying backup integrity...${NC}"
for file in "${BACKUP_DIR}"/*.yaml; do
    if [ -f "$file" ]; then
        if kubectl apply --dry-run=client -f "$file" &> /dev/null; then
            echo -e "${GREEN}✓ Verified: $(basename $file)${NC}"
        else
            echo -e "${RED}✗ Verification failed: $(basename $file)${NC}"
        fi
    fi
done

# Create a tar archive of the backup
tar -czf "${BACKUP_DIR}.tar.gz" "${BACKUP_DIR}"
echo -e "\n${GREEN}Created backup archive: ${BACKUP_DIR}.tar.gz${NC}"
