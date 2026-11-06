# BanVic data platform (Data Engineer certification challenge)

Proof of concept: ingest the BanVic ERP tables (7 CSV files, simulating an on-premises legacy system) into a data lake on S3, orchestrated by Airflow running on a local Kubernetes cluster.

> Status: work in progress. Sections below are filled in as each step is completed.

## Architecture

_Diagram: to be added._

- **Source:** local folder with the 7 BanVic CSV files (on-premises simulation).
- **Orchestration:** Apache Airflow on Minikube.
- **Ingestion:** Meltano (`tap-csv` → S3).
- **Data lake:** S3 buckets `raw`, `standard`, `curated`.
- **Infrastructure as code:** Terraform (AWS resources, Kubernetes resources, Helm release).

Design decisions and their reasons are in [DECISIONS.md](DECISIONS.md).

## Prerequisites

Docker, Minikube, kubectl, Helm, Terraform, AWS CLI, an AWS account and a named AWS profile.

## How to run

_To be added: step-by-step (deploy environment → trigger DAG → verify data)._

## Ingestion strategy

_To be added: extraction, loading, idempotency, validations, layers._

## Monitoring and failure handling

_To be added: retries, alerts, validations._

## Security

No secrets are stored in the repository. See `.env.example` for the expected variable names.

## Cleanup

_To be added: `terraform destroy` and `minikube delete`._
