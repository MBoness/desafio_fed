locals {
  common_labels = {
    "app.kubernetes.io/part-of"    = "banvic-pipeline"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

# One namespace keeps every project resource together, so it can be
# inspected (kubectl -n airflow ...) and removed as a unit.
resource "kubernetes_namespace_v1" "airflow" {
  metadata {
    name   = var.airflow_namespace
    labels = local.common_labels
  }
}

# Landing folder for the "legacy system" CSV files.
# The files are delivered into the node by scripts/deliver_source_files.py;
# this volume only exposes that folder to pods.
resource "kubernetes_persistent_volume_v1" "source_files" {
  metadata {
    name   = "banvic-source-files"
    labels = local.common_labels
  }

  spec {
    # Not enforced for hostPath volumes; required by the API.
    capacity = {
      storage = "1Gi"
    }
    # Airflow only reads the source files.
    access_modes = ["ReadOnlyMany"]
    # A named class (instead of Minikube's default "standard") stops the
    # cluster from provisioning a new, empty volume for our claim.
    storage_class_name = "manual"
    # Deleting the claim must never delete the source data.
    persistent_volume_reclaim_policy = "Retain"

    persistent_volume_source {
      host_path {
        path = var.source_files_node_path
        # Created empty if the files were not delivered yet,
        # so pods still start and the sensor simply waits.
        type = "DirectoryOrCreate"
      }
    }
  }
}

# The claim is what Airflow pods mount (see `volumes` in airflow.tf).
resource "kubernetes_persistent_volume_claim_v1" "source_files" {
  metadata {
    name      = "banvic-source-files"
    namespace = kubernetes_namespace_v1.airflow.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    access_modes       = ["ReadOnlyMany"]
    storage_class_name = "manual"
    # Bind explicitly to the volume above instead of letting Kubernetes match one.
    volume_name = kubernetes_persistent_volume_v1.source_files.metadata[0].name

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
