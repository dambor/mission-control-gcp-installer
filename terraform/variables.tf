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
