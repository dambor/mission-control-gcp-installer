# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands
- Terraform: `terraform init`, `terraform plan`, `terraform apply`, `terraform validate`
- Lint Terraform: `terraform fmt -recursive`
- Validate script: `shellcheck mc-gcp-install.sh`
- Run script: `bash mc-gcp-install.sh`

## Coding Style
- Shell scripts: Use function-based organization, proper error handling with `set -e`
- Terraform: Follow HCL formatting with 2-space indentation
- Variable naming: Use snake_case for variables, descriptive resource names
- Comments: Document complex operations, configuration details
- Error handling: Validate inputs, provide clear error messages
- Logging: Use formatted log messages with timestamps and colors where appropriate
- Security: Never hardcode credentials, use authentication workflows

## Project Structure
This repository contains infrastructure-as-code for deploying Mission Control on GCP using Terraform and Kubernetes.