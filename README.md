# Mission Control GCP Installation Script

This script automates the installation of Mission Control on Google Cloud Platform (GCP) using Google Kubernetes Engine (GKE).

## Overview

The script handles the entire installation process including:

1. Checking and installing prerequisites
2. Creating a GKE cluster with Terraform
3. Installing and configuring Mission Control
4. Setting up LoadBalancer for external access

## How to run it

1. Make the script executable:
   ```bash
   chmod +x mc-gcp-install.sh
   ```

2. Run the script:
   ```bash
   ./mc-gcp-install.sh
   ```

3. Follow the interactive prompts to complete the installation.

## Usage Options

The script offers the following options:

1. **Start or Resume Installation**: Begin a new installation or continue from where you left off
2. **Delete Environment**: Remove all resources created by the script
3. **Exit**: Exit the script

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

1. Run the script: `./mc-gcp-install.sh`
2. Select option 2: "Delete environment"
3. Confirm deletion by typing 'DELETE' when prompted

## Additional Resources

- [Mission Control Documentation](https://docs.datastax.com/en/mission-control/docs/)
- [KOTS Documentation](https://docs.replicated.com/reference/kots-cli-getting-started)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)