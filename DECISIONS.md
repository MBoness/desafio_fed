# Decision log

Short record of the important decisions and why they were made.
Format: **Decision** → **Why** → **Alternatives considered**.

## D1. Where everything runs
- **Decision:** hybrid. Source files are on-premises (local machine). Airflow and Meltano run on a local Kubernetes cluster (Minikube). The data lake lives in AWS S3.
- **Why:** the challenge requires a local Kubernetes environment; a real S3 data lake is closer to what analysts would use in production, and Terraform can provision it.
- **Alternatives:** 100% local with MinIO (fully reproducible without an AWS account, but less realistic); everything in AWS/EKS (costly, out of scope).
- **Trade-off:** the PDF lists "Postgres or MinIO" as destinations. S3 is the managed equivalent of MinIO (same API), so this is a small, deliberate deviation. Reproducing the project requires an AWS account.

## D2. Source
- **Decision:** the 7 BanVic CSV files live in a local folder (`data/`, git-ignored). `scripts/deliver_source_files.py` copies them into the Minikube node (`/data/banvic`), simulating the legacy system dropping its export. A `hostPath` volume exposes that folder to Airflow, and a `FileSensor` waits for the files.
- **Why:** simulates a legacy/on-premises system, as asked by the challenge, and makes the sensor visible in the demo (deliver files → sensor fires).
- **Alternatives:** `minikube start --mount` (Docker Desktop on Windows did not expose the bind mount inside the node); `minikube mount` (needs a terminal kept open, fragile); ConfigMap (1 MB limit, data is 4.7 MB); baking files into the image (mixes data with code).

## D3. Destination and layers
- **Decision:** three S3 buckets created by Terraform: `raw`, `standard`, `curated`.
  - `raw`: data as it arrived, no value changes.
  - `standard`: validated and cleaned (types, dates, duplicates, nulls), Parquet.
  - `curated`: one or two analyst-ready tables.
- **Why:** classic medallion-style separation; each layer has one responsibility, and reruns only touch the layer they write to.
- **Naming:** bucket names include the AWS account id (S3 names are globally unique). `curated` follows the naming used in earlier studies (raw/processed/curated).

## D4. Ingestion tool
- **Decision:** Meltano (`tap-csv` → S3 target). The pipeline is ELT: extract and load first, light transformations afterwards.
- **Why:** taught in the course, configuration is declarative (YAML), Python-based.
- **Alternatives:** Embulk.

## D5. Ingestion strategy and idempotency
- **Decision:** each run writes to a deterministic S3 path (overwrite), with primary keys declared per stream.
- **Why:** running the same DAG twice gives the same result; no duplicates, no manual cleanup.

## D6. Kubernetes and Airflow deployment
- **Decision:** Minikube + official Airflow Helm chart, applied through Terraform (`helm_release`). Custom Airflow image with Meltano in an isolated virtualenv; Meltano is called by the DAG.
- **Why:** infrastructure is code and reproducible; the isolated virtualenv avoids dependency conflicts between Airflow and Meltano.
- **Alternatives:** hand-written manifests; running Meltano in separate pods with `KubernetesPodOperator` (better isolation, more complexity).
- **Executor:** `LocalExecutor` (tasks run inside the scheduler). The chart default, `CeleryExecutor`, adds workers and Redis, which is heavy for a 6 GB Minikube and unnecessary for this pipeline.
- **DAGs delivery:** baked into the custom image (`docker/airflow.Dockerfile` copies `dags/`), together with Meltano (4.4.1, in its own virtualenv; only the `meltano` command is exposed so it cannot shadow Airflow's `python`/`pip`). Code and runtime ship as one versioned unit, which is predictable for the demo. Trade-off: every DAG change needs an image rebuild and a new tag. Alternative: `gitSync` (no rebuild, but depends on a branch in GitHub). The image is built locally and loaded into Minikube (`minikube image load`), not pushed to a registry.
- **Chart pinned** to 1.22.0 (Airflow 3.2.2) for reproducibility.
- **Helm hooks disabled for the migration and create-user jobs** (`useHelmHooks = false`). By default they run only after the release is ready, but the pods wait for the migration, so with Terraform's `wait = true` the install deadlocks and times out. Found when the first apply failed after 15 minutes.

## D7. Secrets
- **Decision:** no secrets in git. Values come from environment variables (`TF_VAR_*`), Terraform creates Kubernetes Secrets, Airflow reads them from the environment. `.env.example` documents the variable names only.
- **Why:** challenge criterion; the repository is public.
- **Secrets Manager considered:** AWS Secrets Manager is the production path (rotation, audit, native Airflow secrets backend), but it does not remove the bootstrap problem: Airflow on Minikube still needs an initial AWS credential to read from it, and secrets created by Terraform end up in the state. For this POC we keep Kubernetes Secrets and mention Secrets Manager as the production evolution (talking point for the video).
- **AWS access:** a dedicated IAM user with least privilege (read/write only on the three project buckets), not the admin user used to run Terraform.

## D8. Terraform state
- **Decision:** local state, git-ignored.
- **Why:** simplest option for a single-person POC; avoids the "bucket for the state must exist first" problem.
- **In a team:** use a remote backend (S3 with locking) and one state per environment.

## D9. CI/CD
- **Decision:** lightweight GitHub Actions, triggered on pull requests and on pushes to `develop` and `main`: `terraform fmt`/`validate` (no credentials), Python lint, DAG import test. `terraform apply` is manual from the local machine.
- **Why:** applying from CI would require cloud credentials in GitHub and a cluster reachable from the internet, which is out of proportion for a local Minikube.

## D10. Cost and cleanup
- **Decision:** AWS Budget alert created by Terraform; a documented `terraform destroy` + `minikube delete` at the end.
- **Why:** the data is tiny (a few MB), so cost should be cents, but alerts and cleanup are good practice.

## D11. Tooling and language
- Shell: Git Bash on Windows. Helper scripts are written in Python (standard library only) rather than shell, so they run on any OS and avoid Git Bash path rewriting. AWS profile: `pessoal` (set through a Terraform variable, not hardcoded in the environment).
- Code, comments and documentation in English.
- The source CSV files are **not** committed (see `.gitignore`).

## D12. Raw → standard transformation with AWS Glue
- **Decision:** light transformations from `raw` to `standard` run as AWS Glue jobs (PySpark), provisioned by Terraform and triggered from the Airflow DAG. Built in a later stage, after the core ingestion (CSV → `raw`) works end to end.
- **Why:** keeps the transformation next to the data in AWS, reuses patterns from earlier Glue studies, and shows Airflow orchestrating a managed service.
- **Trade-off:** Glue adds an IAM role, a scripts bucket, a start-up delay of about a minute per run and a few cents of cost. For a few MB of data Spark is more than needed, so the jobs stay minimal.
- **Fallback:** if Glue becomes too heavy, do the same cleaning in a small Python/DuckDB task.

## Possible future improvements (optional, not committed to)
- **History by delivery date.** Today each run overwrites a fixed path in `raw` (D5), so a new delivery replaces the previous one and no history is kept. To keep history, include the delivery date in the path (e.g. `raw/<table>/delivery_date=YYYY-MM-DD/`). Reruns for the same date would still overwrite only that date, so idempotency is preserved. Downstream layers would then need to choose which deliveries to read (latest, or all).
- **Automatic delivery to the node.** Today `scripts/deliver_source_files.py` is run by hand (see D2). A host-side watcher could run it when `data/` changes, at the cost of a process that must stay running.

## Out of scope
- Athena/Glue (SQL over S3), dbt, remote Terraform state, applying infrastructure from CI.
- The MCP server from the course was considered and dropped: the source is plain CSV files, so there is nothing to connect.
