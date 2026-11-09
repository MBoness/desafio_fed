terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

# Talks to the local Minikube cluster through the same kubeconfig kubectl uses.
# Pinning the context avoids applying to another cluster by accident
# (e.g. a work cluster that happens to be the current kubectl context).
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
