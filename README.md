# Mission Control GCP Installation Script

This script automates the installation of Mission Control on Google Cloud Platform (GCP) using Google Kubernetes Engine (GKE).

## Overview

The script handles the entire installation process including:

1. Checking and installing prerequisites
2. Creating a GKE cluster with Terraform
3. Installing and configuring Mission Control
4. Setting up LoadBalancer for external access

## Prerequisites

Before using this script, you'll need:

- A Google Cloud Platform account with billing enabled
- Basic familiarity with Kubernetes and GCP
- Appropriate permissions to create GKE clusters

## Installation

1. Download the script:
   ```bash
   curl -o install-mc-gcp.sh https://raw.githubusercontent.com/yourusername/mc-gcp-installer/main/install-mc-gcp.sh
   ```

2. Make the script executable:
   ```bash
   chmod +x install-mc-gcp.sh
   ```

3. Run the script:
   ```bash
   ./install-mc-gcp.sh
   ```

4. Follow the interactive prompts to complete the installation.

## Features

- **Interactive Installation**: User-friendly prompts guide you through the process
- **State Management**: Can resume from where it left off if interrupted
- **Automatic Prerequisite Installation**: Installs required tools like kubectl, Helm, krew, and KOTS
- **Custom Configuration**: Allows customizing GKE cluster settings
- **LoadBalancer Setup**: Creates a LoadBalancer for external access to Mission Control UI
- **Environment Cleanup**: Option to delete all created resources when no longer needed

## Usage Options

The script offers the following options:

1. **Start or Resume Installation**: Begin a new installation or continue from where you left off
2. **Delete Environment**: Remove all resources created by the script
3. **Exit**: Exit the script

## Post-Installation

After installation completes:

- Access the KOTS Admin Console: `kubectl kots admin-console --namespace mission-control`
- Reset the Admin Console password: `kubectl kots reset-password -n mission-control`
- Access Mission Control UI via the LoadBalancer IP (provided at the end of installation)

## Troubleshooting

### Common Issues:

1. **API Not Enabled**: The script automatically enables required APIs, but sometimes propagation takes time. If you encounter API-related errors, wait a few minutes and try again.

2. **Cluster Creation Fails**: Check your GCP quotas and permissions. The script offers options to retry or recreate the cluster.

3. **KOTS Installation Times Out**: You can manually access the KOTS admin console with:
   ```bash
   kubectl kots admin-console --namespace mission-control --wait-duration 10m
   ```

4. **LoadBalancer External IP Not Assigned**: This can take a few minutes. Check status with:
   ```bash
   kubectl get svc mission-control-ui-external -n mission-control
   ```

5. **Missing HCD Superuser Credentials**: If you need to access HCD (Cassandra), retrieve credentials with:
   ```bash
   kubectl get secret hcd-superuser -n <namespace> -o jsonpath='{.data.username}' | base64 -d
   kubectl get secret hcd-superuser -n <namespace> -o jsonpath='{.data.password}' | base64 -d
   ```

## Configuration Files

The script creates and uses these files:

- `mc_install_config.env`: Stores your configuration settings
- `mc_install_state.env`: Tracks installation state for resuming
- `terraform/`: Directory containing Terraform configuration files

## License Requirements

Mission Control requires a valid license. You can either:

1. Provide a license file during installation, or
2. Upload a license file through the KOTS Admin Console after installation

## Uninstallation

To completely remove Mission Control and all created resources:

1. Run the script: `./install-mc-gcp.sh`
2. Select option 2: "Delete environment"
3. Confirm deletion by typing 'DELETE' when prompted

## Additional Resources

- [Mission Control Documentation](https://docs.datastax.com/en/mission-control/docs/)
- [KOTS Documentation](https://docs.replicated.com/reference/kots-cli-getting-started)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)