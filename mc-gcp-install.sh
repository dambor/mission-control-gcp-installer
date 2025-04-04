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

# Function to check if GKE auth plugin is installed
check_gke_auth_plugin() {
    log "Checking for GKE auth plugin..."
    
    if command_exists gke-gcloud-auth-plugin; then
        log "GKE auth plugin is installed."
        return 0
    else
        warning "GKE auth plugin is not installed. This is required for kubectl to work with GKE."
        read -p "Would you like to install the GKE auth plugin now? (y/n): " INSTALL_PLUGIN
        
        if [[ "$INSTALL_PLUGIN" == "y" || "$INSTALL_PLUGIN" == "Y" ]]; then
            log "Installing GKE auth plugin..."
            gcloud components install gke-gcloud-auth-plugin
            
            if ! command_exists gke-gcloud-auth-plugin; then
                error "Failed to install GKE auth plugin. Please install it manually: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin"
            fi
            
            log "GKE auth plugin installed successfully."
            
            # Configure kubectl to use the plugin
            log "Configuring kubectl to use the GKE auth plugin..."
            export USE_GKE_GCLOUD_AUTH_PLUGIN=True
            
            # Add to bash profile if it doesn't exist
            if ! grep -q "USE_GKE_GCLOUD_AUTH_PLUGIN=True" ~/.bash_profile 2>/dev/null; then
                echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> ~/.bash_profile
                log "Added USE_GKE_GCLOUD_AUTH_PLUGIN=True to ~/.bash_profile"
            fi
            
            # Add to zsh profile if it exists
            if [ -f ~/.zshrc ] && ! grep -q "USE_GKE_GCLOUD_AUTH_PLUGIN=True" ~/.zshrc; then
                echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> ~/.zshrc
                log "Added USE_GKE_GCLOUD_AUTH_PLUGIN=True to ~/.zshrc"
            fi
            
            return 0
        else
            error "GKE auth plugin is required for this script to work. Please install it manually: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin"
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check GCP CLI
    if ! command_exists gcloud; then
        error "Google Cloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    else
        log "✓ Google Cloud CLI is installed."
    fi
    
    # Make sure gcloud is updated
    log "Updating gcloud components..."
    gcloud components update
    
    # Check GKE auth plugin
    if ! command_exists gke-gcloud-auth-plugin; then
        warning "GKE auth plugin is not installed. This is required for kubectl to work with GKE."
        read -p "Would you like to install the GKE auth plugin now? (y/n): " INSTALL_PLUGIN
        
        if [[ "$INSTALL_PLUGIN" == "y" || "$INSTALL_PLUGIN" == "Y" ]]; then
            log "Installing GKE auth plugin..."
            gcloud components install gke-gcloud-auth-plugin
            
            if ! command_exists gke-gcloud-auth-plugin; then
                error "Failed to install GKE auth plugin. Please install it manually: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin"
            fi
            
            log "GKE auth plugin installed successfully."
            
            # Configure kubectl to use the plugin
            log "Configuring kubectl to use the GKE auth plugin..."
            export USE_GKE_GCLOUD_AUTH_PLUGIN=True
            
            # Add to bash profile if it doesn't exist
            if ! grep -q "USE_GKE_GCLOUD_AUTH_PLUGIN=True" ~/.bash_profile 2>/dev/null; then
                echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> ~/.bash_profile
                log "Added USE_GKE_GCLOUD_AUTH_PLUGIN=True to ~/.bash_profile"
            fi
            
            # Add to zsh profile if it exists
            if [ -f ~/.zshrc ] && ! grep -q "USE_GKE_GCLOUD_AUTH_PLUGIN=True" ~/.zshrc; then
                echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> ~/.zshrc
                log "Added USE_GKE_GCLOUD_AUTH_PLUGIN=True to ~/.zshrc"
            fi
        else
            error "GKE auth plugin is required for this script to work. Please install it manually: https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin"
        fi
    else
        log "✓ GKE auth plugin is installed."
    fi
    
    # Check kubectl
    if ! command_exists kubectl; then
        warning "kubectl is not installed. Installing it now..."
        gcloud components install kubectl
        
        if ! command_exists kubectl; then
            error "Failed to install kubectl. Please install it manually."
        fi
    else
        log "✓ kubectl is installed."
    fi
    
    # Check Helm
    if ! command_exists helm; then
        warning "Helm is not installed. Would you like to install it now? (y/n): "
        read INSTALL_HELM
        
        if [[ "$INSTALL_HELM" == "y" || "$INSTALL_HELM" == "Y" ]]; then
            if command_exists brew; then
                brew install helm
            else
                curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            fi
            
            if ! command_exists helm; then
                error "Failed to install Helm. Please install it manually: https://helm.sh/docs/intro/install/"
            fi
        else
            error "Helm is required for this script to work. Please install it manually: https://helm.sh/docs/intro/install/"
        fi
    else
        log "✓ Helm is installed."
    fi
    
    # Check krew
    if ! command_exists kubectl-krew; then
        warning "Krew plugin manager is not installed. Installing it now..."
        (
            set -x; cd "$(mktemp -d)" &&
            OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
            ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
            KREW="krew-${OS}_${ARCH}" &&
            curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
            tar zxvf "${KREW}.tar.gz" &&
            ./"${KREW}" install krew
        )
        
        # Add krew to PATH for current session
        export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
        
        warning "Please add the following to your shell configuration file and restart your terminal:"
        warning 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"'
        
        # Add to bash profile if it doesn't exist
        if ! grep -q 'KREW_ROOT' ~/.bash_profile 2>/dev/null; then
            echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bash_profile
            log "Added Krew to PATH in ~/.bash_profile"
        fi
        
        # Add to zsh profile if it exists
        if [ -f ~/.zshrc ] && ! grep -q 'KREW_ROOT' ~/.zshrc; then
            echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.zshrc
            log "Added Krew to PATH in ~/.zshrc"
        fi
        
        read -p "Press Enter to continue anyway..." CONTINUE
    else
        log "✓ kubectl-krew is installed."
    fi
    
    # Check kots - Detailed explanation and installation
    log "Checking for KOTS CLI (Kubernetes Off-The-Shelf Software)..."
    if ! command_exists kubectl-kots; then
        warning "KOTS CLI is not installed."
        log "KOTS is a deployment platform for Kubernetes applications, required for Mission Control installation."
        log "It provides a web-based admin console to manage Mission Control deployment and updates."
        
        read -p "Would you like to install KOTS CLI now? (y/n): " INSTALL_KOTS
        
        if [[ "$INSTALL_KOTS" == "y" || "$INSTALL_KOTS" == "Y" ]]; then
            log "Installing KOTS CLI..."
            
            mkdir -p "$HOME/tools/kots"
            curl https://kots.io/install | REPL_INSTALL_PATH=$HOME/tools/kots bash
            
            if [ $? -ne 0 ]; then
                log "Trying alternative installation method..."
                curl https://kots.io/install | bash
            fi
            
            # Add kots to PATH for current session
            export PATH="$HOME/tools/kots:$PATH"
            
            # Verify installation
            if ! command_exists kubectl-kots; then
                error "Failed to install KOTS CLI. You can install it manually with: curl https://kots.io/install | bash"
            fi
            
            log "KOTS CLI installed successfully."
            
            # Add to bash profile if it doesn't exist
            if ! grep -q 'tools/kots' ~/.bash_profile 2>/dev/null; then
                echo 'export PATH="$HOME/tools/kots:$PATH"' >> ~/.bash_profile
                log "Added KOTS to PATH in ~/.bash_profile"
            fi
            
            # Add to zsh profile if it exists
            if [ -f ~/.zshrc ] && ! grep -q 'tools/kots' ~/.zshrc; then
                echo 'export PATH="$HOME/tools/kots:$PATH"' >> ~/.zshrc
                log "Added KOTS to PATH in ~/.zshrc"
            fi
        else
            error "KOTS CLI is required for Mission Control installation. Please install it manually: curl https://kots.io/install | bash"
        fi
    else
        log "✓ KOTS CLI is installed."
        # Display KOTS version
        KOTS_VERSION=$(kubectl kots version 2>/dev/null | head -n1)
        log "KOTS version: $KOTS_VERSION"
    fi
    
    # Configure environment variables for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    log "All prerequisites are met or installed."
    save_state "prerequisites_checked"
}

# Load saved configuration if available
load_saved_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Found saved configuration file: $CONFIG_FILE"
        read -p "Would you like to use this saved configuration? (y/n): " USE_SAVED
        if [[ "$USE_SAVED" == "y" || "$USE_SAVED" == "Y" ]]; then
            # Source the config file to get the variables
            source "$CONFIG_FILE"
            log "Loaded configuration from $CONFIG_FILE"
            
            # Display the loaded configuration
            echo -e "\n${BLUE}Loaded Configuration:${NC}"
            echo -e "Prefix: ${YELLOW}$PREFIX${NC}"
            echo -e "GCP Project: ${YELLOW}$GCP_PROJECT${NC}"
            echo -e "GCP Region: ${YELLOW}$GCP_REGION${NC}"
            echo -e "GCP Zone: ${YELLOW}$GCP_ZONE${NC}"
            echo -e "GCP Network: ${YELLOW}$GCP_NETWORK${NC}"
            echo -e "Machine Type: ${YELLOW}$MACHINE_TYPE${NC}"
            echo -e "Disk Size: ${YELLOW}$DISK_SIZE GB${NC}"
            echo -e "Node Count: ${YELLOW}$NODE_COUNT${NC}"
            
            read -p "Proceed with this configuration? (y/n): " PROCEED
            if [[ "$PROCEED" != "y" && "$PROCEED" != "Y" ]]; then
                log "Will proceed with manual configuration instead."
                return 1
            fi
            save_state "config_loaded"
            return 0
        fi
    fi
    return 1
}

# Set up configuration
setup_config() {
    log "Setting up configuration..."
    
    # Default values
    DEFAULT_PREFIX="user-mc-lcm-proj"
    DEFAULT_GCP_PROJECT="gcp-lcm-project"
    DEFAULT_GCP_REGION="us-central1"
    DEFAULT_GCP_ZONE="us-central1-c"
    DEFAULT_GCP_NETWORK="ha-vpc-00"
    DEFAULT_MACHINE_TYPE="e2-standard-4"
    DEFAULT_DISK_SIZE="100"
    DEFAULT_NODE_COUNT="2"
    
    # Get user input for configuration with defaults
    read -p "Enter your prefix [${DEFAULT_PREFIX}]: " PREFIX
    PREFIX=${PREFIX:-$DEFAULT_PREFIX}
    
    read -p "Enter GCP project ID [${DEFAULT_GCP_PROJECT}]: " GCP_PROJECT
    GCP_PROJECT=${GCP_PROJECT:-$DEFAULT_GCP_PROJECT}
    
    read -p "Enter GCP region [${DEFAULT_GCP_REGION}]: " GCP_REGION
    GCP_REGION=${GCP_REGION:-$DEFAULT_GCP_REGION}
    
    read -p "Enter GCP zone [${DEFAULT_GCP_ZONE}]: " GCP_ZONE
    GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
    
    read -p "Enter GCP network [${DEFAULT_GCP_NETWORK}]: " GCP_NETWORK
    GCP_NETWORK=${GCP_NETWORK:-$DEFAULT_GCP_NETWORK}
    
    echo -e "\n${BLUE}Advanced Configuration (press Enter to use defaults):${NC}"
    read -p "Node machine type [${DEFAULT_MACHINE_TYPE}]: " MACHINE_TYPE
    MACHINE_TYPE=${MACHINE_TYPE:-$DEFAULT_MACHINE_TYPE}
    
    read -p "Node disk size in GB [${DEFAULT_DISK_SIZE}]: " DISK_SIZE
    DISK_SIZE=${DISK_SIZE:-$DEFAULT_DISK_SIZE}
    
    read -p "Number of nodes [${DEFAULT_NODE_COUNT}]: " NODE_COUNT
    NODE_COUNT=${NODE_COUNT:-$DEFAULT_NODE_COUNT}
    
    # Confirm configuration
    echo -e "\n${BLUE}Configuration Summary:${NC}"
    echo -e "Prefix: ${YELLOW}$PREFIX${NC}"
    echo -e "GCP Project: ${YELLOW}$GCP_PROJECT${NC}"
    echo -e "GCP Region: ${YELLOW}$GCP_REGION${NC}"
    echo -e "GCP Zone: ${YELLOW}$GCP_ZONE${NC}"
    echo -e "GCP Network: ${YELLOW}$GCP_NETWORK${NC}"
    echo -e "\n${BLUE}Advanced Configuration:${NC}"
    echo -e "Machine Type: ${YELLOW}$MACHINE_TYPE${NC}"
    echo -e "Disk Size: ${YELLOW}$DISK_SIZE GB${NC}"
    echo -e "Node Count: ${YELLOW}$NODE_COUNT${NC}"
    
    read -p "Is this configuration correct? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        error "Configuration not confirmed. Exiting."
    fi
    
    # Option to save configuration for future use
    read -p "Would you like to save this configuration for future use? (y/n): " SAVE_CONFIG
    if [[ "$SAVE_CONFIG" == "y" || "$SAVE_CONFIG" == "Y" ]]; then
        cat > $CONFIG_FILE << EOF
PREFIX=$PREFIX
GCP_PROJECT=$GCP_PROJECT
GCP_REGION=$GCP_REGION
GCP_ZONE=$GCP_ZONE
GCP_NETWORK=$GCP_NETWORK
MACHINE_TYPE=$MACHINE_TYPE
DISK_SIZE=$DISK_SIZE
NODE_COUNT=$NODE_COUNT
EOF
        log "Configuration saved to $CONFIG_FILE"
    fi
    
    save_state "config_setup"
}

# Add Helm repositories
add_helm_repos() {
    log "Adding and updating Helm repositories..."
    
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    
    save_state "helm_repos_added"
}

# Authenticate with GCP
gcp_authenticate() {
    log "Authenticating with Google Cloud..."
    
    gcloud auth application-default login
    
    # Get user confirmation for the project
    log "Verifying access to GCP project: $GCP_PROJECT"
    gcloud projects describe $GCP_PROJECT
    
    if [ $? -ne 0 ]; then
        error "Failed to access project $GCP_PROJECT. Please check your permissions or project ID."
    fi
    
    # Enable required APIs
    enable_gcp_apis
    
    save_state "gcp_authenticated"
}

# Ensure required GCP APIs are enabled
enable_gcp_apis() {
    log "Ensuring required GCP APIs are enabled..."
    
    # List of required APIs
    REQUIRED_APIS=(
        "container.googleapis.com"      # Kubernetes Engine API
        "compute.googleapis.com"        # Compute Engine API
        "iam.googleapis.com"            # Identity and Access Management API
        "monitoring.googleapis.com"     # Cloud Monitoring API
        "logging.googleapis.com"        # Cloud Logging API
        "storage-api.googleapis.com"    # Cloud Storage API
    )
    
    for api in "${REQUIRED_APIS[@]}"; do
        log "Enabling $api..."
        gcloud services enable $api --project=$GCP_PROJECT
        
        # Check if API was successfully enabled
        if [ $? -ne 0 ]; then
            warning "Failed to enable $api. This might cause issues during deployment."
            warning "Please enable this API manually: https://console.developers.google.com/apis/api/$api/overview?project=$GCP_PROJECT"
            read -p "Do you want to continue anyway? (y/n): " CONTINUE
            if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
                error "Exiting due to API enablement failure."
            fi
        fi
    done
    
    log "All required APIs have been enabled or attempted to enable."
    log "Waiting 30 seconds for API enablement to propagate..."
    sleep 30
    
    save_state "apis_enabled"
}

# Check project and billing
check_project_billing() {
    log "Checking project billing status..."
    
    BILLING_INFO=$(gcloud billing projects describe $GCP_PROJECT --format="value(billingEnabled)")
    
    if [[ "$BILLING_INFO" != "True" ]]; then
        warning "Billing is not enabled for project $GCP_PROJECT."
        warning "GKE clusters require billing to be enabled."
        log "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$GCP_PROJECT"
        
        read -p "Have you enabled billing for this project? (y/n): " BILLING_ENABLED
        if [[ "$BILLING_ENABLED" != "y" && "$BILLING_ENABLED" != "Y" ]]; then
            error "Billing must be enabled to continue. Exiting."
        fi
    else
        log "Billing is enabled for project $GCP_PROJECT."
    fi
    
    save_state "billing_checked"
}

# Create Terraform files
create_terraform_files() {
    log "Creating Terraform files..."
    
    # Create directory for Terraform files
    mkdir -p terraform
    cd terraform
    
    # Create main.tf
    cat > main.tf << 'EOF'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

resource "google_container_cluster" "control_plane" {
  name               = "${var.prefix}-mc-control-plane"
  location           = var.gcp_zone
  initial_node_count = 1
  
  # Create a separate node pool
  remove_default_node_pool = true
  
  network    = var.gcp_network
  subnetwork = var.gcp_network

  # Enable workload identity
  workload_identity_config {
    workload_pool = "${var.gcp_project}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.prefix}-primary-node-pool"
  location   = var.gcp_zone
  cluster    = google_container_cluster.control_plane.name
  node_count = var.node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]
    
    # Enable workload identity at the node level
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
EOF

    # Create variables.tf
    cat > variables.tf << 'EOF'
variable "prefix" {
  description = "Prefix to use for resource names"
  type        = string
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "gcp_zone" {
  description = "GCP zone"
  type        = string
}

variable "gcp_network" {
  description = "GCP network name"
  type        = string
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
}

variable "disk_size" {
  description = "Disk size for GKE nodes in GB"
  type        = number
}

variable "node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
}
EOF

    # Create terraform.tfvars
    cat > terraform.tfvars << EOF
prefix      = "$PREFIX"
gcp_project = "$GCP_PROJECT"
gcp_region  = "$GCP_REGION"
gcp_zone    = "$GCP_ZONE"
gcp_network = "$GCP_NETWORK"
machine_type = "$MACHINE_TYPE"
disk_size   = $DISK_SIZE
node_count  = $NODE_COUNT
EOF
    
    cd ..
    
    save_state "terraform_files_created"
}

# Create GKE cluster using Terraform
create_gke_cluster() {
    log "Creating GKE cluster using Terraform..."
    
    cd terraform
    
    # Check if terraform state already exists
    if [ -f "terraform.tfstate" ]; then
        log "Terraform state file exists. Checking if cluster already exists..."
        
        # Check if the cluster already exists in the state
        if grep -q "google_container_cluster" terraform.tfstate; then
            log "Cluster already exists in Terraform state."
            log "Would you like to:"
            echo "1. Skip cluster creation and continue (recommended if cluster exists)"
            echo "2. Recreate/update the cluster (may cause errors with existing resources)"
            echo "3. Destroy and recreate the cluster (will delete all data)"
            read -p "Enter your choice [1-3]: " CLUSTER_CHOICE
            
            case $CLUSTER_CHOICE in
                1)
                    log "Skipping cluster creation..."
                    cd ..
                    save_state "gke_cluster_created"
                    return 0
                    ;;
                2)
                    log "Will attempt to update the cluster..."
                    ;;
                3)
                    log "Destroying existing cluster before recreation..."
                    terraform destroy -target=google_container_node_pool.primary_nodes -auto-approve
                    terraform destroy -target=google_container_cluster.control_plane -auto-approve
                    log "Existing cluster destroyed."
                    ;;
                *)
                    log "Invalid choice. Defaulting to skip cluster creation..."
                    cd ..
                    save_state "gke_cluster_created"
                    return 0
                    ;;
            esac
        fi
    fi
    
    # Initialize Terraform
    terraform init
    
    # Create plan and save it to a file
    log "Creating Terraform plan..."
    terraform plan -out=tfplan
    
    # Apply the configuration with error handling
    log "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Check if terraform apply was successful
    if [ $? -ne 0 ]; then
        warning "Terraform encountered an error during cluster creation."
        log "Common issues and resolutions:"
        log "1. API not fully enabled: Sometimes API enablement takes longer than expected."
        log "2. Quota limits: Check if you have sufficient quota for the requested resources."
        log "3. Permission issues: Ensure your account has the necessary permissions."
        log "4. Node pool configuration: Error may be due to trying to modify immutable attributes."
        
        # Special handling for node pool updates
        if grep -q "Error 400.*node_pool" terraform.tfstate; then
            warning "Node pool update error detected. This might be due to trying to modify immutable attributes."
            log "Would you like to try recreating the node pool? (y/n)"
            read RECREATE_POOL
            
            if [[ "$RECREATE_POOL" == "y" || "$RECREATE_POOL" == "Y" ]]; then
                log "Recreating node pool..."
                terraform destroy -target=google_container_node_pool.primary_nodes -auto-approve
                terraform apply -auto-approve
            fi
        else
            # Generic retry
            read -p "Would you like to retry the cluster creation? (y/n): " RETRY
            if [[ "$RETRY" == "y" || "$RETRY" == "Y" ]]; then
                log "Waiting 60 seconds before retrying..."
                sleep 60
                log "Retrying cluster creation..."
                terraform apply -auto-approve
                
                if [ $? -ne 0 ]; then
                    error "Failed to create cluster after retry. Please check the error messages above."
                fi
            else
                error "Cluster creation failed. Exiting."
            fi
        fi
    fi
    
    log "GKE cluster created successfully."
    cd ..
    
    save_state "gke_cluster_created"
}

# Configure kubectl to use the new cluster
configure_kubectl() {
    log "Configuring kubectl to use the new cluster..."
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    # Get credentials for the new cluster
    gcloud container clusters get-credentials "${PREFIX}-mc-control-plane" --zone "$GCP_ZONE" --project "$GCP_PROJECT"
    
    # Verify the current context
    kubectl config current-context
    
    save_state "kubectl_configured"
}

# Install cert-manager and other prerequisites
install_prerequisites() {
    log "Installing cert-manager and other prerequisites..."
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    # Install cert-manager
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.3 \
        --set installCRDs=true
    
    if [ $? -ne 0 ]; then
        error "Failed to install cert-manager. Please check the error messages above."
    fi
    
    # Install krew plugins
    log "Installing kubectl plugins via krew..."
    
    kubectl krew install minio || warning "Failed to install minio plugin"
    kubectl krew install preflight || warning "Failed to install preflight plugin"
    kubectl krew install support-bundle || warning "Failed to install support-bundle plugin"
    
    # Wait for cert-manager to be ready
    log "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    
    save_state "prerequisites_installed"
}

# Install Mission Control
install_mission_control() {
    log "Installing Mission Control..."
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    # Ask for namespace
    read -p "Enter the namespace for Mission Control installation [mission-control]: " MC_NAMESPACE
    MC_NAMESPACE=${MC_NAMESPACE:-mission-control}
    
    # Check if namespace already exists
    if ! kubectl get namespace "$MC_NAMESPACE" &>/dev/null; then
        log "Namespace $MC_NAMESPACE doesn't exist. Creating it..."
        kubectl create namespace "$MC_NAMESPACE"
        
        if [ $? -ne 0 ]; then
            error "Failed to create namespace $MC_NAMESPACE. Check your permissions and try again."
        fi
        log "Namespace $MC_NAMESPACE created successfully."
    else
        log "Using existing namespace: $MC_NAMESPACE"
    fi
    
    # More thorough check if Mission Control is already installed in this namespace
    MC_INSTALLED=false
    
    # Check for kotsadm pods
    if kubectl get pods -n "$MC_NAMESPACE" -l app=kotsadm &>/dev/null; then
        log "Found existing KOTS admin pods in namespace $MC_NAMESPACE."
        
        # Also check for actual mission-control deployments
        if kubectl get deployments -n "$MC_NAMESPACE" | grep -q "mission-control"; then
            log "Found existing Mission Control deployments in namespace $MC_NAMESPACE."
            MC_INSTALLED=true
        else
            log "KOTS is installed, but Mission Control may not be fully deployed."
            MC_INSTALLED=false
        fi
    fi
    
    if $MC_INSTALLED; then
        log "Would you like to:"
        echo "1. Continue with existing installation (recommended)"
        echo "2. Reinstall Mission Control (may lose configuration)"
        read -p "Enter your choice [1-2]: " REINSTALL_CHOICE
        
        if [[ "$REINSTALL_CHOICE" == "2" ]]; then
            log "Reinstalling Mission Control..."
            # Continue with installation
        else
            log "Using existing installation."
            log "To access the KOTS Admin Console: kubectl kots admin-console --namespace $MC_NAMESPACE"
            
            # Store the namespace for future reference
            echo "MC_NAMESPACE=$MC_NAMESPACE" >> $CONFIG_FILE
            
            save_state "mission_control_installed"
            return 0
        fi
    fi
    
    # Prompt for license file
    log "Mission Control requires a license file for installation."
    log "Do you have a license file? (y/n): "
    read HAS_LICENSE
    
    LICENSE_FLAG=""
    if [[ "$HAS_LICENSE" == "y" || "$HAS_LICENSE" == "Y" ]]; then
        read -p "Enter the path to your license file: " LICENSE_PATH
        if [ -f "$LICENSE_PATH" ]; then
            LICENSE_FLAG="--license-file=$LICENSE_PATH"
            log "Using license file: $LICENSE_PATH"
        else
            warning "License file not found: $LICENSE_PATH"
            warning "Will proceed without license file. You'll need to upload it in the Admin Console."
        fi
    else
        log "No license file provided. You'll need to upload it in the Admin Console."
    fi
    
    # Start the installation
    log "Starting Mission Control installation in namespace $MC_NAMESPACE..."
    log "This will open a browser window to the KOTS Admin Console."
    log "In the console, you'll need to:"
    log "1. Upload your license file (if not provided)"
    log "2. Configure Mission Control settings"
    log "3. Deploy the application"
    
    # Check for existing KOTS admin pods and remove them if needed
    if kubectl get pods -n "$MC_NAMESPACE" -l app=kotsadm &>/dev/null; then
        log "Found existing KOTS admin pods. Removing them to ensure clean installation..."
        kubectl delete deployment -n "$MC_NAMESPACE" -l app=kotsadm
        kubectl delete pods -n "$MC_NAMESPACE" -l app=kotsadm
    fi
    
    # Set a longer timeout for installation
    kubectl kots install mission-control --namespace "$MC_NAMESPACE" $LICENSE_FLAG --wait-duration 10m
    
    if [ $? -ne 0 ]; then
        warning "KOTS installation command returned an error."
        warning "This might be temporary. You can try accessing the Admin Console with:"
        warning "kubectl kots admin-console --namespace $MC_NAMESPACE"
        
        # Try to check if pods were created anyway
        if kubectl get pods -n "$MC_NAMESPACE" -l app=kotsadm &>/dev/null; then
            log "However, KOTS admin pods were found in the namespace."
            log "The installation might have partially succeeded."
        else
            warning "No KOTS admin pods were found. The installation likely failed."
        fi
        
        read -p "Would you like to retry the Mission Control installation? (y/n): " RETRY_INSTALL
        if [[ "$RETRY_INSTALL" == "y" || "$RETRY_INSTALL" == "Y" ]]; then
            log "Retrying Mission Control installation..."
            kubectl kots install mission-control --namespace "$MC_NAMESPACE" $LICENSE_FLAG --wait-duration 15m
            
            if [ $? -ne 0 ]; then
                error "Failed to install Mission Control after retry. Please check the error messages above."
            fi
        else
            warning "Continuing without completing Mission Control installation."
            warning "You can install it later with: kubectl kots install mission-control --namespace $MC_NAMESPACE"
        fi
    fi
    
    log "Mission Control installation process initiated."
    
    # Wait for user to complete the installation in the browser
    log "The KOTS Admin Console should be open in your browser."
    log "Please complete the installation steps in the browser, then return here."
    read -p "Have you completed the Mission Control installation in the browser? (y/n): " INSTALLATION_COMPLETE
    
    if [[ "$INSTALLATION_COMPLETE" == "y" || "$INSTALLATION_COMPLETE" == "Y" ]]; then
        log "Verifying Mission Control installation..."
        
        # Check for Mission Control deployments
        RETRY_COUNT=0
        while ! kubectl get deployments -n "$MC_NAMESPACE" | grep -q "mission-control"; do
            RETRY_COUNT=$((RETRY_COUNT+1))
            if [ $RETRY_COUNT -gt 10 ]; then
                warning "Mission Control deployments not found after waiting."
                warning "The installation might not be complete."
                break
            fi
            log "Waiting for Mission Control deployments to appear (attempt $RETRY_COUNT/10)..."
            sleep 30
        done
        
        if kubectl get deployments -n "$MC_NAMESPACE" | grep -q "mission-control"; then
            log "Mission Control deployments found! Installation appears successful."
        else
            warning "No Mission Control deployments found. The installation might not be complete."
            warning "You may need to complete the installation steps in the KOTS Admin Console:"
            warning "kubectl kots admin-console --namespace $MC_NAMESPACE"
        fi
    else
        warning "You indicated the Mission Control installation is not complete."
        warning "You need to complete the installation through the KOTS Admin Console."
        warning "You can access it later with: kubectl kots admin-console --namespace $MC_NAMESPACE"
    fi
    
    log "To access the KOTS Admin Console again later, run:"
    log "kubectl kots admin-console --namespace $MC_NAMESPACE"
    log "If you need to reset the Admin Console password:"
    log "kubectl kots reset-password -n $MC_NAMESPACE"
    
    # Store the namespace for future reference
    echo "MC_NAMESPACE=$MC_NAMESPACE" >> $CONFIG_FILE
    
    save_state "mission_control_installed"
}

# Create LoadBalancer service for Mission Control UI
create_loadbalancer() {
    log "Creating LoadBalancer service for Mission Control UI..."
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    # Get the namespace from the config file or use default
    if [ -f "$CONFIG_FILE" ] && grep -q "MC_NAMESPACE" "$CONFIG_FILE"; then
        source "$CONFIG_FILE"
        log "Using namespace from config: $MC_NAMESPACE"
    else
        # Prompt user for the namespace name
        log "Please enter the namespace where Mission Control was installed (default is mission-control):"
        read -p "Namespace: " MC_NAMESPACE
        MC_NAMESPACE=${MC_NAMESPACE:-mission-control}
    fi
    
    # Check if the provided namespace exists
    if ! kubectl get namespace $MC_NAMESPACE &>/dev/null; then
        warning "Namespace $MC_NAMESPACE does not exist."
        log "Would you like to create the $MC_NAMESPACE namespace? (y/n)"
        read CREATE_NS
        
        if [[ "$CREATE_NS" == "y" || "$CREATE_NS" == "Y" ]]; then
            kubectl create namespace $MC_NAMESPACE
            log "Namespace $MC_NAMESPACE created."
        else
            error "Cannot create LoadBalancer without a valid namespace. Please install Mission Control first."
        fi
    else
        log "Using existing namespace: $MC_NAMESPACE"
    fi
    
    # Check if Mission Control UI is running
    log "Checking if Mission Control UI is running in namespace $MC_NAMESPACE..."
    if ! kubectl get deployment -n $MC_NAMESPACE | grep -q "mission-control-ui"; then
        warning "Mission Control UI deployment not found in namespace $MC_NAMESPACE."
        log "This could mean:"
        log "1. Mission Control installation is not complete"
        log "2. The UI component has a different name"
        log "3. Mission Control was installed in a different namespace"
        
        # List all deployments in the namespace
        log "Deployments in namespace $MC_NAMESPACE:"
        kubectl get deployments -n $MC_NAMESPACE
        
        log "Would you like to:"
        echo "1. Create LoadBalancer anyway (might not work until Mission Control is fully installed)"
        echo "2. Abort LoadBalancer creation (recommended if Mission Control is not installed)"
        read -p "Enter your choice [1-2]: " LB_CHOICE
        
        if [[ "$LB_CHOICE" != "1" ]]; then
            log "Aborting LoadBalancer creation."
            log "You can create it later after Mission Control is fully installed."
            return 1
        fi
        
        log "Proceeding with LoadBalancer creation anyway..."
    else
        log "Mission Control UI deployment found in namespace $MC_NAMESPACE."
    fi
    
    # Create service YAML file
    cat > mission-control-ui-external.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: mission-control-ui-external
  namespace: $MC_NAMESPACE
  labels:
    created-by: automation-script
spec:
  selector:
    app: mission-control-ui
  sessionAffinity: None
  type: LoadBalancer
  ports:
  - protocol: TCP
    port: 443
    targetPort: 8080
EOF
    
    # Apply service
    log "Creating LoadBalancer service in namespace $MC_NAMESPACE..."
    kubectl apply -f mission-control-ui-external.yaml
    
    # Wait for service to get external IP
    log "Waiting for LoadBalancer to be provisioned with an external IP..."
    external_ip=""
    timeout=300  # 5 minutes timeout
    start_time=$(date +%s)
    
    while [ -z "$external_ip" ]; do
        echo "Waiting for external IP..."
        external_ip=$(kubectl get svc mission-control-ui-external -n $MC_NAMESPACE --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}" 2>/dev/null)
        
        # Check for timeout
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $timeout ]; then
            warning "Timed out waiting for external IP after 5 minutes."
            warning "The LoadBalancer service has been created, but hasn't received an external IP yet."
            warning "You can check its status later with: kubectl get svc mission-control-ui-external -n $MC_NAMESPACE"
            break
        fi
        
        [ -z "$external_ip" ] && sleep 10
    done
    
    if [ -n "$external_ip" ]; then
        log "Mission Control UI is now accessible at: https://$external_ip/"
        log "Note: It may take a few minutes for the IP to become fully accessible."
    fi
    
    save_state "loadbalancer_created"
}

# Delete the environment
delete_environment() {
    log "Preparing to delete the environment..."
    
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        error "Configuration file not found. Cannot delete environment."
    fi
    
    echo -e "\n${RED}WARNING: This will delete all resources created by this script, including:${NC}"
    echo -e "- GKE cluster: ${YELLOW}${PREFIX}-mc-control-plane${NC}"
    echo -e "- All associated resources in project: ${YELLOW}${GCP_PROJECT}${NC}"
    echo -e "\n${RED}This action is irreversible!${NC}"
    
    read -p "Are you absolutely sure you want to delete the environment? Type 'DELETE' to confirm: " CONFIRM_DELETE
    
    if [ "$CONFIRM_DELETE" != "DELETE" ]; then
        log "Deletion cancelled."
        return
    fi
    
    log "Deleting environment using Terraform..."
    
    if [ -d "terraform" ]; then
        cd terraform
        
        # Initialize Terraform if needed
        if [ ! -d ".terraform" ]; then
            terraform init
        fi
        
        # Destroy resources
        terraform apply -destroy -auto-approve
        
        if [ $? -eq 0 ]; then
            log "Environment deleted successfully."
            
            # Remove state file
            cd ..
            if [ -f "$STATE_FILE" ]; then
                rm -f "$STATE_FILE"
                log "Removed state file: $STATE_FILE"
            fi
        else
            error "Failed to delete environment. Please check the error messages above."
        fi
    else
        error "Terraform directory not found. Cannot delete environment."
    fi
}

# Start or resume installation based on state
start_or_resume_installation() {
    # Load configuration if available
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Load previous state
    load_state
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    # Resume based on current state
    case $CURRENT_STATE in
        "start" | "")
            log "Starting installation from the beginning..."
            check_prerequisites
            load_saved_config || setup_config
            add_helm_repos
            gcp_authenticate
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "prerequisites_checked")
            log "Resuming from configuration step..."
            load_saved_config || setup_config
            add_helm_repos
            gcp_authenticate
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "config_loaded" | "config_setup")
            log "Resuming from Helm repositories step..."
            add_helm_repos
            gcp_authenticate
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "helm_repos_added")
            log "Resuming from GCP authentication step..."
            gcp_authenticate
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "gcp_authenticated" | "apis_enabled")
            log "Resuming from billing check step..."
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "billing_checked")
            log "Resuming from Terraform files creation step..."
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "terraform_files_created")
            log "Resuming from GKE cluster creation step..."
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "gke_cluster_created")
            log "Resuming from kubectl configuration step..."
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "kubectl_configured")
            log "Resuming from prerequisites installation step..."
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "prerequisites_installed")
            log "Resuming from Mission Control installation step..."
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "mission_control_installed")
            log "Mission Control is already installed."
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "loadbalancer_created")
            log "Installation is complete including LoadBalancer setup."
            ;;
            
        *)
            log "Unknown state: $CURRENT_STATE. Starting from the beginning..."
            check_prerequisites
            load_saved_config || setup_config
            add_helm_repos
            gcp_authenticate
            check_project_billing
            create_terraform_files
            create_gke_cluster
            configure_kubectl
            install_prerequisites
            install_mission_control
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
    esac
    
    log "Installation complete!"
    log "Notes:"
    log "1. To access the KOTS Admin Console again: kubectl kots admin-console --namespace mission-control"
    log "2. To reset the Admin Console password: kubectl kots reset-password -n mission-control"
    log "3. To tear down the environment: Run this script again and select 'Delete environment'"
}

# Show the menu
show_menu() {
    echo -e "\n${BLUE}Mission Control Installation Menu${NC}"
    echo "1. Start or resume installation"
    echo "2. Delete environment"
    echo "3. Exit"
    read -p "Enter your choice [1-3]: " MENU_CHOICE
    
    case $MENU_CHOICE in
        1)
            start_or_resume_installation
            ;;
        2)
            delete_environment
            ;;
        3)
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