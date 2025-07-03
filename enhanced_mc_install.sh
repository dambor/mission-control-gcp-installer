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

# Install HCD Cluster
install_hcd_cluster() {
    log "Installing HCD Cluster using Mission Control..."
    
    # Make sure environment variable is set for GKE auth plugin
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True
    
    log "IMPORTANT: Before continuing, you must have:"
    log "1. Completed Mission Control installation"
    log "2. Created a project in the Mission Control UI"
    log "3. Noted the Project Slug from the UI or from the namespace list"
    read -p "Have you completed these steps? (y/n): " PREREQS_DONE
    
    if [[ "$PREREQS_DONE" != "y" && "$PREREQS_DONE" != "Y" ]]; then
        log "Please complete the prerequisites first:"
        log "1. Access Mission Control UI and log in"
        log "2. Click '+New Project' and create a project"
        log "3. Note the Project Slug value shown in the UI"
        log "4. Run this script again and select option 2"
        return 1
    fi
    
    # List available namespaces to find project slug
    log "Available namespaces (look for your project slug - it usually starts with 'opscenter-'):"
    kubectl get namespaces
    
    # Ask for the project namespace
    read -p "Enter your project namespace/slug: " PROJECT_NAMESPACE
    
    if [ -z "$PROJECT_NAMESPACE" ]; then
        error "Project namespace cannot be empty. Please try again."
    fi
    
    # Check if the provided namespace exists
    if ! kubectl get namespace "$PROJECT_NAMESPACE" &>/dev/null; then
        error "Namespace $PROJECT_NAMESPACE does not exist. Please check the namespace name and try again."
    fi
    
    log "Using project namespace: $PROJECT_NAMESPACE"
    
    # Prompt for HCD cluster name
    log "Enter a name for your HCD cluster (default: hcd):"
    read -p "HCD Cluster Name: " HCD_NAME
    HCD_NAME=${HCD_NAME:-hcd}

    # Prompt for the Datacenter name
    log "Enter a name for the Datacenter:"
    read -p "Datacenter Name: " DC_NAME
    
    # Create HCD cluster YAML file
    log "Creating HCD cluster configuration..."
    
    cat > ${HCD_NAME}-mission-control-cluster.yaml << EOF
apiVersion: missioncontrol.datastax.com/v1beta2
kind: MissionControlCluster
metadata:
  name: ${HCD_NAME}
  namespace: ${PROJECT_NAMESPACE}
spec:
  createIssuer: true
  dataApi: 
    enabled: true
    port: 8181
  createIssuer: true
  encryption:
    internodeEncryption:
      certs:
        createCerts: true
      enabled: true
  k8ssandra:
    auth: true
    cassandra:
      config:
        cassandraYaml: {}
        dseYaml: {}
        jvmOptions:
          gc: G1GC
          heapSize: 1Gi
      datacenters:
        - config:
            cassandraYaml: {}
            dseYaml: {}
          datacenterName: ${DC_NAME}
          dseWorkloads: {}
          metadata:
            name: ${DC_NAME}
            pods: {}
            services:
              additionalSeedService: {}
              allPodsService: {}
              dcService: {}
              nodePortService: {}
              seedService: {}
          networking: {}
          perNodeConfigMapRef: {}
          racks:
            - name: rack1
              nodeAffinityLabels: {}
            - name: rack2
              nodeAffinityLabels: {}
            - name: rack3
              nodeAffinityLabels: {}
          size: 3
      resources:
        requests:
          cpu: 1000m
          memory: 4Gi
      serverType: hcd
      serverVersion: 1.1.0
      storageConfig:
        cassandraDataVolumeClaimSpec:
          accessModes:
          - ReadWriteOnce
          resources:
            requests:
              storage: 8Gi
          storageClassName: standard
      superuserSecretRef:
        name: hcd-superuser
EOF

    # Apply the HCD cluster configuration
    log "Applying HCD cluster configuration..."
    kubectl apply -f ${HCD_NAME}-mission-control-cluster.yaml
    
    if [ $? -ne 0 ]; then
        warning "Failed to apply HCD cluster configuration."
        read -p "Would you like to retry? (y/n): " RETRY_HCD
        if [[ "$RETRY_HCD" == "y" || "$RETRY_HCD" == "Y" ]]; then
            kubectl apply -f ${HCD_NAME}-mission-control-cluster.yaml
            if [ $? -ne 0 ]; then
                error "Failed to apply HCD cluster configuration after retry."
            fi
        else
            error "Cannot continue without HCD cluster."
        fi
    fi
    
    # Wait for HCD cluster to be ready
    log "Cluster creation initiated. The HCD cluster will be created in the Mission Control UI."
    log "This process may take several minutes to complete."
    log "You can check the status in the Mission Control UI or with:"
    log "kubectl get pods -n $PROJECT_NAMESPACE"
    
    # Save the namespace for future reference
    echo "PROJECT_NAMESPACE=$PROJECT_NAMESPACE" >> $CONFIG_FILE
    echo "HCD_NAME=$HCD_NAME" >> $CONFIG_FILE
    
    # Ask if user wants to wait and check status
    read -p "Would you like to check the status of the pods? (y/n): " CHECK_STATUS
    if [[ "$CHECK_STATUS" == "y" || "$CHECK_STATUS" == "Y" ]]; then
        log "Checking pods in namespace $PROJECT_NAMESPACE:"
        kubectl get pods -n $PROJECT_NAMESPACE
    fi
    
    log "HCD Cluster creation has been initiated. You can monitor the progress in the Mission Control UI."
    log "Once the cluster is ready, you can access the Data API at port 8181."
    
    save_state "hcd_cluster_initiated"
}

# Delete HCD Cluster
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

# Langflow Management Functions
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

# Expose Data API as LoadBalancer
expose_data_api() {
    log "Setting up Data API access..."
    
    # Get the project namespace from config or ask user
    if [ -z "$PROJECT_NAMESPACE" ] && [ -f "$CONFIG_FILE" ] && grep -q "PROJECT_NAMESPACE" "$CONFIG_FILE"; then
        source "$CONFIG_FILE"
    fi
    
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
    
    # List all services in the namespace
    log "Services in namespace $PROJECT_NAMESPACE:"
    kubectl get services -n $PROJECT_NAMESPACE
    
    # Find the Data API service
    DATA_API_SERVICES=$(kubectl get services -n $PROJECT_NAMESPACE | grep -iE 'data-api|stargate' | awk '{print $1}')
    
    if [ -z "$DATA_API_SERVICES" ]; then
        log "No Data API service found in namespace $PROJECT_NAMESPACE."
        log "Please enter the name of the Data API service:"
        read -p "Service name: " DATA_API_SVC
    elif [[ $(echo "$DATA_API_SERVICES" | wc -l) -gt 1 ]]; then
        log "Multiple potential Data API services found:"
        echo "$DATA_API_SERVICES"
        read -p "Enter the name of the Data API service to expose: " DATA_API_SVC
    else
        DATA_API_SVC=$DATA_API_SERVICES
        log "Found Data API service: $DATA_API_SVC"
    fi
    
    if [ -z "$DATA_API_SVC" ]; then
        error "Data API service name cannot be empty."
    fi
    
    # Export the service YAML
    log "Exporting Data API service configuration..."
    kubectl get service $DATA_API_SVC -n $PROJECT_NAMESPACE -o yaml > hcd-data-api-svc.yaml
    
    if [ $? -ne 0 ]; then
        error "Failed to get service $DATA_API_SVC. Please check the service name."
    fi
    
    # Modify the service type to LoadBalancer
    log "Modifying service type from ClusterIP to LoadBalancer..."
    sed -i'.bak' 's/type: ClusterIP/type: LoadBalancer/' hcd-data-api-svc.yaml
    
    # Apply the updated service
    log "Applying updated Data API service configuration..."
    kubectl apply -f hcd-data-api-svc.yaml
    
    if [ $? -ne 0 ]; then
        error "Failed to update Data API service."
    fi
    
    log "Data API service updated successfully."
    
    # Wait for the external IP
    log "Waiting for LoadBalancer to be provisioned with an external IP..."
    external_ip=""
    timeout=300  # 5 minutes timeout
    start_time=$(date +%s)
    
    while [ -z "$external_ip" ]; do
        echo "Waiting for external IP..."
        external_ip=$(kubectl get svc $DATA_API_SVC -n $PROJECT_NAMESPACE --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}" 2>/dev/null)
        
        # Check for timeout
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $timeout ]; then
            warning "Timed out waiting for external IP after 5 minutes."
            warning "The LoadBalancer service has been created, but hasn't received an external IP yet."
            warning "You can check its status later with: kubectl get svc $DATA_API_SVC -n $PROJECT_NAMESPACE"
            break
        fi
        
        [ -z "$external_ip" ] && sleep 10
    done
    
    if [ -n "$external_ip" ]; then
        log "Data API is now accessible at: http://$external_ip:8181/"
        echo "DATA_API_SVC=$DATA_API_SVC" >> $CONFIG_FILE
        echo "DATA_API_URL=http://$external_ip:8181" >> $CONFIG_FILE
    fi
    
    # Offer to set up port forwarding
    log "Would you like to set up port forwarding to access the Data API locally? (y/n)"
    read SETUP_PORT_FORWARD
    if [[ "$SETUP_PORT_FORWARD" == "y" || "$SETUP_PORT_FORWARD" == "Y" ]]; then
        log "Starting port forwarding from localhost:8181 to the Data API service..."
        log "Keep this terminal window open to maintain the connection."
        log "Press Ctrl+C to stop port forwarding when done."
        kubectl port-forward svc/$DATA_API_SVC -n $PROJECT_NAMESPACE 8181:8181
    else
        log "You can set up port forwarding later with:"
        log "kubectl port-forward svc/$DATA_API_SVC -n $PROJECT_NAMESPACE 8181:8181"
    fi
}

# Get HCD superuser credentials
get_hcd_credentials() {
    log "Retrieving HCD superuser credentials..."
    
    # Get the project namespace from config or ask user
    if [ -z "$PROJECT_NAMESPACE" ] && [ -f "$CONFIG_FILE" ] && grep -q "PROJECT_NAMESPACE" "$CONFIG_FILE"; then
        source "$CONFIG_FILE"
    fi
    
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
    
    # Find all secrets in the namespace
    log "Secrets in namespace $PROJECT_NAMESPACE:"
    kubectl get secrets -n $PROJECT_NAMESPACE
    
    # Find superuser secret
    HCD_SECRETS=$(kubectl get secrets -n $PROJECT_NAMESPACE | grep -i superuser | awk '{print $1}')
    
    if [ -z "$HCD_SECRETS" ]; then
        log "No superuser secret found. Please enter the name of the superuser secret:"
        read -p "Secret name: " HCD_SECRET
    elif [[ $(echo "$HCD_SECRETS" | wc -l) -gt 1 ]]; then
        log "Multiple potential superuser secrets found:"
        echo "$HCD_SECRETS"
        read -p "Enter the name of the superuser secret: " HCD_SECRET
    else
        HCD_SECRET=$HCD_SECRETS
        log "Found superuser secret: $HCD_SECRET"
    fi
    
    if [ -z "$HCD_SECRET" ]; then
        error "Superuser secret name cannot be empty."
    fi
    
    # Get username and password
    log "Retrieving credentials from secret $HCD_SECRET..."
    USERNAME=$(kubectl get secret $HCD_SECRET -n $PROJECT_NAMESPACE -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
    PASSWORD=$(kubectl get secret $HCD_SECRET -n $PROJECT_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
    
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
        warning "Failed to retrieve credentials from secret $HCD_SECRET."
        log "Available data keys in the secret:"
        kubectl get secret $HCD_SECRET -n $PROJECT_NAMESPACE -o jsonpath='{.data}' | jq
        
        log "Please enter the correct key names for username and password:"
        read -p "Username key (default: username): " USERNAME_KEY
        USERNAME_KEY=${USERNAME_KEY:-username}
        read -p "Password key (default: password): " PASSWORD_KEY
        PASSWORD_KEY=${PASSWORD_KEY:-password}
        
        USERNAME=$(kubectl get secret $HCD_SECRET -n $PROJECT_NAMESPACE -o jsonpath="{.data.$USERNAME_KEY}" 2>/dev/null | base64 -d)
        PASSWORD=$(kubectl get secret $HCD_SECRET -n $PROJECT_NAMESPACE -o jsonpath="{.data.$PASSWORD_KEY}" 2>/dev/null | base64 -d)
        
        if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
            error "Failed to retrieve credentials with the provided keys."
        fi
    fi
    
    log "Successfully retrieved HCD credentials:"
    log "Username: $USERNAME"
    log "Password: $PASSWORD"
    
    # Save credentials to config file
    echo "HCD_USERNAME=$USERNAME" >> $CONFIG_FILE
    echo "HCD_PASSWORD=$PASSWORD" >> $CONFIG_FILE
    
    # Find Cassandra pods
    log "Looking for Cassandra pods in namespace $PROJECT_NAMESPACE..."
    CASS_PODS=$(kubectl get pods -n $PROJECT_NAMESPACE | grep -iE '(hcd|cassandra).*rack.*sts' | awk '{print $1}')
    
    if [ -z "$CASS_PODS" ]; then
        log "No Cassandra pods found."
        return
    fi
    
    log "Found Cassandra pods:"
    echo "$CASS_PODS"
    
    # Select a pod for connection
    if [[ $(echo "$CASS_PODS" | wc -l) -gt 1 ]]; then
        read -p "Enter the name of the pod to connect to: " CASS_POD
    else
        CASS_POD=$CASS_PODS
    fi
    
    if [ -z "$CASS_POD" ]; then
        log "No pod selected. Skipping connection."
        return
    fi
    
    # Offer to connect to the pod
    log "Would you like to connect to the Cassandra pod $CASS_POD? (y/n)"
    read CONNECT_TO_POD
    if [[ "$CONNECT_TO_POD" == "y" || "$CONNECT_TO_POD" == "Y" ]]; then
        log "Connecting to pod $CASS_POD..."
        log "When connected, you can run:"
        log "nodetool -u $USERNAME -pw $PASSWORD status"
        log "cqlsh -u $USERNAME -p $PASSWORD"
        log ""
        kubectl exec -it $CASS_POD -n $PROJECT_NAMESPACE -- bash
    else
        log "You can connect to the pod later with:"
        log "kubectl exec -it $CASS_POD -n $PROJECT_NAMESPACE -- bash"
        log ""
        log "Then run these commands:"
        log "nodetool -u $USERNAME -pw $PASSWORD status"
        log "cqlsh -u $USERNAME -p $PASSWORD"
    fi
}

# Add post-installation setup for HCD
hcd_post_installation() {
    log "HCD Post-Installation Setup"
    log "==========================="
    
    log "Select an action:"
    echo "1. Expose Data API as LoadBalancer"
    echo "2. Retrieve HCD superuser credentials"
    echo "3. Do both (recommended)"
    echo "4. Return to main menu"
    
    read -p "Enter your choice [1-4]: " POST_INSTALL_CHOICE
    
    case $POST_INSTALL_CHOICE in
        1)
            expose_data_api
            ;;
        2)
            get_hcd_credentials
            ;;
        3)
            expose_data_api
            get_hcd_credentials
            ;;
        4)
            return
            ;;
        *)
            warning "Invalid choice. Returning to main menu."
            ;;
    esac
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
    echo -e "- Mission Control installation in namespace: ${YELLOW}${MC_NAMESPACE:-mission-control}${NC}"
    echo -e "- HCD Cassandra cluster (if installed)"
    echo -e "- All associated resources in project: ${YELLOW}${GCP_PROJECT}${NC}"
    echo -e "\n${RED}This action is irreversible!${NC}"
    
    read -p "Are you absolutely sure you want to delete the environment? Type 'DELETE' to confirm: " CONFIRM_DELETE
    
    if [ "$CONFIRM_DELETE" != "DELETE" ]; then
        log "Deletion cancelled."
        return
    fi
    
    # If HCD cluster was installed, try to delete it first
    if [ -f "$CONFIG_FILE" ] && grep -q "HCD_NAMESPACE" "$CONFIG_FILE"; then
        log "Attempting to delete HCD cluster first..."
        kubectl delete -f hcd-data-api-gcp-mccluster.yaml --ignore-not-found
        
        # Wait for deletion to progress
        log "Waiting for HCD resources to be deleted..."
        sleep 30
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
            
            # Remove config file
            if [ -f "$CONFIG_FILE" ]; then
                rm -f "$CONFIG_FILE"
                log "Removed config file: $CONFIG_FILE"
            fi
            
            # Remove generated files
            log "Cleaning up generated files..."
            rm -f hcd-data-api-gcp-mccluster.yaml hcd-data-api-svc.yaml hcd-data-api-svc.yaml.bak mission-control-ui-external.yaml
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "prerequisites_installed")
            log "Resuming from Mission Control installation step..."
            install_mission_control
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "mission_control_installed")
            log "Mission Control is already installed."
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
            log "Would you like to create a LoadBalancer service for Mission Control UI? (y/n)"
            read CREATE_LB
            if [[ "$CREATE_LB" == "y" || "$CREATE_LB" == "Y" ]]; then
                create_loadbalancer
            fi
            ;;
            
        "hcd_cluster_installed")
            log "HCD Cluster is already installed."
            
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
            
            log "Would you like to install the HCD Cassandra cluster? (y/n)"
            read INSTALL_HCD
            if [[ "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
                install_hcd_cluster
            fi
            
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
    
    if [[ "$CURRENT_STATE" == "hcd_cluster_installed" || "$INSTALL_HCD" == "y" || "$INSTALL_HCD" == "Y" ]]; then
        if [ -f "$CONFIG_FILE" ] && grep -q "HCD_USERNAME" "$CONFIG_FILE"; then
            source "$CONFIG_FILE"
            log "HCD Cluster Notes:"
            log "- Access the Data API: http://localhost:8181 (after port-forwarding)"
            log "- Port-forward command: kubectl port-forward svc/$DATA_API_SVC -n $MC_NAMESPACE 8181:8181"
            log "- Connect to Cassandra: kubectl exec -it hcd-gcp-rack1-sts-0 -n $MC_NAMESPACE -- bash"
            log "- Username: $HCD_USERNAME"
            log "- Password: $HCD_PASSWORD"
        fi
    fi
}

# Show the menu
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
        