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
