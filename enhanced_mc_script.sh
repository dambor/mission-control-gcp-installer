#!/bin/bash

# Mission Control Installation on GCP in GKE Cluster
# This script automates the installation process of Mission Control on GCP

# Color outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# State tracking file
STATE_FILE="mc_install_state.env"

# Configuration file
CONFIG_FILE="mc_install_config.env"

# Function to display messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to save current state
save_state() {
    echo "CURRENT_STATE=$1" > $STATE_FILE
    log "Current state saved: $1"
}

# Function to load current state
load_state() {
    if [ -f "$STATE_FILE" ]; then
        source $STATE_FILE
        log "Loaded previous state: $CURRENT_STATE"
        return 0
    fi
    CURRENT_STATE="start"
    return 1
}

# [Previous functions remain the same - check_prerequisites, load_saved_config, etc.]
# ... (keeping all existing functions for brevity)

# NEW SECTION 1: Delete HCD Cluster
delete_hcd_cluster() {
    log "HCD Cluster Deletion"
    log "==================="
    
    # Load configuration if available
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Get project namespace
    if [ -z "$PROJECT_NAMESPACE" ]; then
        log "Available namespaces (look for your project slug):"
        kubectl get namespaces
        read -p "Enter your project namespace/slug: " PROJECT_NAMESPACE
        
        if [ -z "$PROJECT_NAMESPACE" ]; then
            error "Project namespace cannot be empty."
        fi
        
        if ! kubectl get namespace "$PROJECT_NAMESPACE" &>/dev/null; then
            error "Namespace $PROJECT_NAMESPACE does not exist."
        fi
    fi
    
    log "Using project namespace: $PROJECT_NAMESPACE"
    
    # List HCD cluster YAML files in current directory
    HCD_YAML_FILES=$(ls *-mission-control-cluster.yaml 2>/dev/null || ls *mccluster.yaml 2>/dev/null || ls hcd*.yaml 2>/dev/null)
    
    if [ -z "$HCD_YAML_FILES" ]; then
        log "No HCD cluster YAML files found in current directory."
        log "Looking for existing HCD clusters in namespace $PROJECT_NAMESPACE..."
        
        # Check for existing MissionControlCluster resources
        HCD_CLUSTERS=$(kubectl get missioncontrolcluster -n "$PROJECT_NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}')
        
        if [ -z "$HCD_CLUSTERS" ]; then
            warning "No HCD clusters found in namespace $PROJECT_NAMESPACE."
            return 1
        fi
        
        log "Found HCD clusters:"
        echo "$HCD_CLUSTERS"
        
        if [[ $(echo "$HCD_CLUSTERS" | wc -l) -gt 1 ]]; then
            read -p "Enter the name of the HCD cluster to delete: " HCD_CLUSTER_NAME
        else
            HCD_CLUSTER_NAME=$HCD_CLUSTERS
        fi
        
        log "Selected HCD cluster: $HCD_CLUSTER_NAME"
        
        echo -e "\n${RED}WARNING: This will permanently delete the HCD cluster '$HCD_CLUSTER_NAME' and all its data!${NC}"
        read -p "Are you sure you want to delete this HCD cluster? Type 'DELETE' to confirm: " CONFIRM_DELETE
        
        if [ "$CONFIRM_DELETE" != "DELETE" ]; then
            log "HCD cluster deletion cancelled."
            return 0
        fi
        
        log "Deleting HCD cluster $HCD_CLUSTER_NAME from namespace $PROJECT_NAMESPACE..."
        kubectl delete missioncontrolcluster "$HCD_CLUSTER_NAME" -n "$PROJECT_NAMESPACE"
        
        if [ $? -eq 0 ]; then
            log "HCD cluster $HCD_CLUSTER_NAME deletion initiated successfully."
            log "Note: It may take several minutes for all resources to be fully removed."
        else
            error "Failed to delete HCD cluster $HCD_CLUSTER_NAME."
        fi
        
    else
        log "Found HCD cluster YAML files:"
        echo "$HCD_YAML_FILES"
        
        if [[ $(echo "$HCD_YAML_FILES" | wc -l) -gt 1 ]]; then
            read -p "Enter the name of the YAML file to use for deletion: " SELECTED_YAML
        else
            SELECTED_YAML=$HCD_YAML_FILES
        fi
        
        if [ ! -f "$SELECTED_YAML" ]; then
            error "YAML file $SELECTED_YAML not found."
        fi
        
        log "Selected YAML file: $SELECTED_YAML"
        
        # Extract cluster name from YAML file
        HCD_CLUSTER_NAME=$(grep -E "^  name:" "$SELECTED_YAML" | head -1 | awk '{print $2}')
        log "HCD cluster name from YAML: $HCD_CLUSTER_NAME"
        
        echo -e "\n${RED}WARNING: This will permanently delete the HCD cluster '$HCD_CLUSTER_NAME' and all its data!${NC}"
        echo -e "YAML file: ${YELLOW}$SELECTED_YAML${NC}"
        echo -e "Namespace: ${YELLOW}$PROJECT_NAMESPACE${NC}"
        read -p "Are you sure you want to delete this HCD cluster? Type 'DELETE' to confirm: " CONFIRM_DELETE
        
        if [ "$CONFIRM_DELETE" != "DELETE" ]; then
            log "HCD cluster deletion cancelled."
            return 0
        fi
        
        log "Deleting HCD cluster using YAML file: $SELECTED_YAML"
        kubectl delete -f "$SELECTED_YAML"
        
        if [ $? -eq 0 ]; then
            log "HCD cluster deletion initiated successfully using $SELECTED_YAML."
            log "Note: It may take several minutes for all resources to be fully removed."
        else
            error "Failed to delete HCD cluster using $SELECTED_YAML."
        fi
    fi
    
    # Check deletion progress
    read -p "Would you like to monitor the deletion progress? (y/n): " MONITOR_DELETION
    if [[ "$MONITOR_DELETION" == "y" || "$MONITOR_DELETION" == "Y" ]]; then
        log "Monitoring HCD cluster deletion progress..."
        log "Press Ctrl+C to stop monitoring"
        
        while kubectl get pods -n "$PROJECT_NAMESPACE" | grep -q "$HCD_CLUSTER_NAME"; do
            echo "Waiting for HCD pods to be deleted..."
            kubectl get pods -n "$PROJECT_NAMESPACE" | grep "$HCD_CLUSTER_NAME"
            sleep 10
        done
        
        log "HCD cluster deletion completed!"
    fi
    
    log "HCD cluster deletion process completed."
}

# NEW SECTION 2: Install/Delete Langflow
manage_langflow() {
    log "Langflow Management"
    log "=================="
    
    log "Select an action:"
    echo "1. Install Langflow"
    echo "2. Delete Langflow"
    echo "3. Check Langflow status"
    echo "4. Return to main menu"
    
    read -p "Enter your choice [1-4]: " LANGFLOW_CHOICE
    
    case $LANGFLOW_CHOICE in
        1)
            install_langflow
            ;;
        2)
            delete_langflow
            ;;
        3)
            check_langflow_status
            ;;
        4)
            return
            ;;
        *)
            warning "Invalid choice. Returning to main menu."
            ;;
    esac
}

# Install Langflow
install_langflow() {
    log "Installing Langflow..."
    
    # Check if Helm is installed
    if ! command_exists helm; then
        error "Helm is required for Langflow installation. Please install Helm first."
    fi
    
    # Check if values.yaml exists
    if [ ! -f "values.yaml" ]; then
        warning "values.yaml file not found in current directory."
        read -p "Do you want to continue with default values? (y/n): " USE_DEFAULT
        
        if [[ "$USE_DEFAULT" != "y" && "$USE_DEFAULT" != "Y" ]]; then
            error "values.yaml file is required for Langflow installation."
        fi
        VALUES_FLAG=""
    else
        log "Found values.yaml file. Using it for installation."
        VALUES_FLAG="-f ./values.yaml"
    fi
    
    # Ask for namespace
    read -p "Enter the namespace for Langflow installation [langflow]: " LANGFLOW_NAMESPACE
    LANGFLOW_NAMESPACE=${LANGFLOW_NAMESPACE:-langflow}
    
    # Check if namespace exists, create if not
    if ! kubectl get namespace "$LANGFLOW_NAMESPACE" &>/dev/null; then
        log "Namespace $LANGFLOW_NAMESPACE doesn't exist. Creating it..."
        kubectl create namespace "$LANGFLOW_NAMESPACE"
        
        if [ $? -ne 0 ]; then
            error "Failed to create namespace $LANGFLOW_NAMESPACE."
        fi
        log "Namespace $LANGFLOW_NAMESPACE created successfully."
    else
        log "Using existing namespace: $LANGFLOW_NAMESPACE"
    fi
    
    # Check if Langflow Helm repository is added
    log "Adding Langflow Helm repository..."
    helm repo add langflow https://langflow-ai.github.io/langflow-helm-charts
    helm repo update
    
    if [ $? -ne 0 ]; then
        error "Failed to add Langflow Helm repository."
    fi
    
    # Check if Langflow is already installed
    if helm list -n "$LANGFLOW_NAMESPACE" | grep -q "langflow-ide"; then
        log "Langflow is already installed in namespace $LANGFLOW_NAMESPACE."
        read -p "Do you want to upgrade the existing installation? (y/n): " UPGRADE_LANGFLOW
        
        if [[ "$UPGRADE_LANGFLOW" == "y" || "$UPGRADE_LANGFLOW" == "Y" ]]; then
            log "Upgrading Langflow installation..."
            helm upgrade langflow-ide langflow/langflow-ide -n "$LANGFLOW_NAMESPACE" $VALUES_FLAG
        else
            log "Skipping Langflow installation."
            return 0
        fi
    else
        # Install Langflow
        log "Installing Langflow in namespace $LANGFLOW_NAMESPACE..."
        helm install langflow-ide langflow/langflow-ide -n "$LANGFLOW_NAMESPACE" $VALUES_FLAG
    fi
    
    if [ $? -eq 0 ]; then
        log "Langflow installation completed successfully!"
        
        # Wait for pods to be ready
        log "Waiting for Langflow pods to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/instance=langflow-ide -n "$LANGFLOW_NAMESPACE"
        
        # Show access information
        log "Langflow installation details:"
        log "Namespace: $LANGFLOW_NAMESPACE"
        log "Release name: langflow-ide"
        
        # Check for LoadBalancer service
        LB_SERVICE=$(kubectl get svc -n "$LANGFLOW_NAMESPACE" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}')
        if [ -n "$LB_SERVICE" ]; then
            log "Checking for external IP..."
            EXTERNAL_IP=$(kubectl get svc "$LB_SERVICE" -n "$LANGFLOW_NAMESPACE" --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
            
            if [ -n "$EXTERNAL_IP" ]; then
                log "Langflow is accessible at: http://$EXTERNAL_IP:8080"
            else
                log "LoadBalancer is provisioning. Check external IP with:"
                log "kubectl get svc $LB_SERVICE -n $LANGFLOW_NAMESPACE"
            fi
        else
            log "No LoadBalancer service found. You may need to use port-forwarding:"
            log "kubectl port-forward svc/langflow-ide-langflow-frontend -n $LANGFLOW_NAMESPACE 8080:8080"
        fi
        
        # Save namespace to config
        echo "LANGFLOW_NAMESPACE=$LANGFLOW_NAMESPACE" >> $CONFIG_FILE
        
    else
        error "Failed to install Langflow. Please check the error messages above."
    fi
}

# Delete Langflow
delete_langflow() {
    log "Deleting Langflow..."
    
    # Get namespace from config or ask user
    if [ -f "$CONFIG_FILE" ] && grep -q "LANGFLOW_NAMESPACE" "$CONFIG_FILE"; then
        source "$CONFIG_FILE"
        log "Found Langflow namespace from config: $LANGFLOW_NAMESPACE"
    else
        read -p "Enter the namespace where Langflow is installed [langflow]: " LANGFLOW_NAMESPACE
        LANGFLOW_NAMESPACE=${LANGFLOW_NAMESPACE:-langflow}
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$LANGFLOW_NAMESPACE" &>/dev/null; then
        warning "Namespace $LANGFLOW_NAMESPACE does not exist."
        return 1
    fi
    
    # Check if Langflow is installed
    if ! helm list -n "$LANGFLOW_NAMESPACE" | grep -q "langflow-ide"; then
        warning "Langflow (langflow-ide) is not installed in namespace $LANGFLOW_NAMESPACE."
        log "Available Helm releases in namespace $LANGFLOW_NAMESPACE:"
        helm list -n "$LANGFLOW_NAMESPACE"
        return 1
    fi
    
    echo -e "\n${RED}WARNING: This will permanently delete Langflow and all its data!${NC}"
    echo -e "Namespace: ${YELLOW}$LANGFLOW_NAMESPACE${NC}"
    echo -e "Release: ${YELLOW}langflow-ide${NC}"
    read -p "Are you sure you want to delete Langflow? Type 'DELETE' to confirm: " CONFIRM_DELETE
    
    if [ "$CONFIRM_DELETE" != "DELETE" ]; then
        log "Langflow deletion cancelled."
        return 0
    fi
    
    log "Deleting Langflow Helm release..."
    helm uninstall langflow-ide -n "$LANGFLOW_NAMESPACE"
    
    if [ $? -eq 0 ]; then
        log "Langflow Helm release deleted successfully."
        
        # Ask if user wants to delete the namespace
        read -p "Do you want to delete the namespace $LANGFLOW_NAMESPACE as well? (y/n): " DELETE_NAMESPACE
        if [[ "$DELETE_NAMESPACE" == "y" || "$DELETE_NAMESPACE" == "Y" ]]; then
            kubectl delete namespace "$LANGFLOW_NAMESPACE"
            if [ $? -eq 0 ]; then
                log "Namespace $LANGFLOW_NAMESPACE deleted successfully."
            else
                warning "Failed to delete namespace $LANGFLOW_NAMESPACE."
            fi
        fi
        
        # Remove from config file
        if [ -f "$CONFIG_FILE" ]; then
            sed -i '/LANGFLOW_NAMESPACE=/d' "$CONFIG_FILE"
        fi
        
    else
        error "Failed to delete Langflow. Please check the error messages above."
    fi
}

# Check Langflow status
check_langflow_status() {
    log "Checking Langflow status..."
    
    # Get namespace from config or ask user
    if [ -f "$CONFIG_FILE" ] && grep -q "LANGFLOW_NAMESPACE" "$CONFIG_FILE"; then
        source "$CONFIG_FILE"
    else
        read -p "Enter the namespace where Langflow is installed [langflow]: " LANGFLOW_NAMESPACE
        LANGFLOW_NAMESPACE=${LANGFLOW_NAMESPACE:-langflow}
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$LANGFLOW_NAMESPACE" &>/dev/null; then
        warning "Namespace $LANGFLOW_NAMESPACE does not exist."
        return 1
    fi
    
    log "Langflow status in namespace: $LANGFLOW_NAMESPACE"
    log "================================================"
    
    # Check Helm releases
    log "Helm releases:"
    helm list -n "$LANGFLOW_NAMESPACE"
    
    # Check pods
    log "Pods:"
    kubectl get pods -n "$LANGFLOW_NAMESPACE"
    
    # Check services
    log "Services:"
    kubectl get svc -n "$LANGFLOW_NAMESPACE"
    
    # Check for external access
    LB_SERVICE=$(kubectl get svc -n "$LANGFLOW_NAMESPACE" -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}')
    if [ -n "$LB_SERVICE" ]; then
        EXTERNAL_IP=$(kubectl get svc "$LB_SERVICE" -n "$LANGFLOW_NAMESPACE" --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
        
        if [ -n "$EXTERNAL_IP" ]; then
            log "External access: http://$EXTERNAL_IP:8080"
        else
            log "LoadBalancer is still provisioning external IP..."
        fi
    else
        log "No LoadBalancer service found. Use port-forwarding for access:"
        log "kubectl port-forward svc/langflow-ide-langflow-frontend -n $LANGFLOW_NAMESPACE 8080:8080"
    fi
}

# [Keep all existing functions...]

# Updated show_menu function
show_menu() {
    echo -e "\n${BLUE}Mission Control Installation Menu${NC}"
    echo "1. Start or resume installation"
    echo "2. Install/Configure HCD Cluster" 
    echo "3. HCD Post-Installation Setup"
    echo "4. Delete HCD Cluster"
    echo "5. Manage Langflow (Install/Delete)"
    echo "6. Delete environment"
    echo "7. Exit"
    read -p "Enter your choice [1-7]: " MENU_CHOICE
    
    case $MENU_CHOICE in
        1)
            start_or_resume_installation
            ;;
        2)
            install_hcd_cluster
            ;;
        3)
            hcd_post_installation
            ;;
        4)
            delete_hcd_cluster
            ;;
        5)
            manage_langflow
            ;;
        6)
            delete_environment
            ;;
        7)
            log "Exiting script."
            exit 0
            ;;
        *)
            warning "Invalid choice. Please select a valid option."
            show_menu
            ;;
    esac
}

# Main function to start the script
main() {
    log "Mission Control GCP Installation Script"
    log "======================================="
    
    # Check for configuration file
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Show menu
    show_menu
}

# Run the main function
main