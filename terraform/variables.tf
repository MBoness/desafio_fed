variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used to reach the cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Fixed to Minikube so Terraform never touches another cluster."
  type        = string
  default     = "minikube"
}

variable "airflow_namespace" {
  description = "Namespace that holds Airflow and everything it needs."
  type        = string
  default     = "airflow"
}

variable "source_files_node_path" {
  description = "Folder inside the Minikube node where scripts/deliver_source_files.py drops the CSV files."
  type        = string
  default     = "/data/banvic"
}
