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

variable "airflow_chart_version" {
  description = "Version of the official Apache Airflow Helm chart (1.22.0 installs Airflow 3.2.2)."
  type        = string
  default     = "1.22.0"
}

variable "airflow_image_repository" {
  description = "Name of the custom Airflow image (built from docker/airflow.Dockerfile)."
  type        = string
  default     = "banvic-airflow"
}

variable "airflow_image_tag" {
  description = "Tag of the custom Airflow image. Bump it on every rebuild so Kubernetes rolls the pods."
  type        = string
  default     = "0.1.0"
}

variable "airflow_admin_password" {
  description = "Password of the Airflow admin user. Set it with TF_VAR_airflow_admin_password; never commit it."
  type        = string
  sensitive   = true
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform. Fixed to the personal account so the company one is never touched."
  type        = string
  default     = "pessoal"
}

variable "aws_region" {
  description = "AWS region for the data lake buckets."
  type        = string
  default     = "us-east-1"
}

variable "budget_email" {
  description = "E-mail that receives the AWS Budget alerts. Set it with TF_VAR_budget_email; never commit it."
  type        = string
  sensitive   = true
}

variable "budget_limit_usd" {
  description = "Monthly cost limit (USD) of the AWS Budget alert."
  type        = number
  default     = 5
}

variable "source_files_node_path" {
  description = "Folder inside the Minikube node where scripts/deliver_source_files.py drops the CSV files."
  type        = string
  default     = "/data/banvic"
}
