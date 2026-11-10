terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    # Data lake buckets, the pipeline's IAM user and the budget alert.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the Airflow encryption keys so nobody has to create or store them.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
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

# Personal AWS account (profile "pessoal"), never the company one.
# default_tags puts the same tags on every AWS resource, which helps spot
# leftovers in the console after the final destroy.
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      project    = "banvic-fed"
      managed_by = "terraform"
    }
  }
}

# Same cluster, same pinned context, for installing the Airflow chart.
provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
