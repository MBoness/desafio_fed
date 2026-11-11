# Decision log

Short record of the important decisions and why they were made.
Format: **Decision** → **Why** → **Alternatives considered**.

## D1. Where everything runs
- **Decision:** everything runs locally. Source files are on-premises (local machine) and the data warehouse is a Postgres running next to Airflow and Meltano on a local Kubernetes cluster (Minikube).
- **Why:** the challenge asks for storage ("Postgres or MinIO") on a local Kubernetes environment. A local destination makes the project reproducible with no cloud account and no cost.
- **Alternatives, in the order they were tried:**
  1. *S3 on AWS.* Built and applied with Terraform (buckets, least-privilege IAM user, budget alert), then removed: it needs an AWS account to reproduce, which goes against the "local" requirement.
  2. *MinIO in the cluster.* Dropped before it ran: the official images are no longer public (`quay.io/minio/minio` answers 401 and Docker Hub `minio/minio` denies access, checked on 2026-11-10). Only unofficial community forks remain, which is a reproducibility risk.
  3. *Postgres* (chosen): official image, permanent, and one of the two destinations the challenge allows.
- **Production path:** an object-storage data lake (S3 with Parquet) plus a managed engine. The Meltano and Airflow parts would stay the same; only the target and the SQL tasks change.

## D2. Source
- **Decision:** the 7 BanVic CSV files live in a local folder (`data/`, git-ignored). `scripts/deliver_source_files.py` copies them into the Minikube node (`/data/banvic`), simulating the legacy system dropping its export. A `hostPath` volume exposes that folder to Airflow, and a sensor waits for the files (a `PythonSensor`, see D13).
- **Why:** simulates a legacy/on-premises system, as asked by the challenge, and makes the sensor visible in the demo (deliver files → sensor fires).
- **Alternatives:** `minikube start --mount` (Docker Desktop on Windows did not expose the bind mount inside the node); `minikube mount` (needs a terminal kept open, fragile); ConfigMap (1 MB limit, data is 4.7 MB); baking files into the image (mixes data with code).

## D3. Destination and layers
- **Decision:** one Postgres database (`banvic`) with three schemas created by Terraform: `raw`, `standard`, `curated`.
  - `raw`: data as it arrived, no value changes. Every column is text; the loader adds `_sdc_*` metadata columns.
  - `standard`: validated and cleaned (types, dates, blanks as NULL); no deduplication needed (see D12).
  - `curated`: analyst-ready tables, empty for now until the business rules are defined (see D12).
- **Why:** classic medallion-style separation; each layer has one responsibility, and reruns only touch the layer they write to. Schemas give the same separation as buckets with a single piece of infrastructure.
- **Postgres is separate from Airflow's metadata database** on purpose: orchestration state and business data have different lifecycles. It is a small StatefulSet with the official `postgres:17-alpine` image; the schemas come from an init script in a ConfigMap, so they exist as soon as the database starts.

## D4. Ingestion tool
- **Decision:** Meltano (`tap-csv` → `target-postgres`, both the MeltanoLabs variant). The pipeline is ELT: extract and load first, light transformations afterwards.
- **Why:** taught in the course, configuration is declarative (YAML), Python-based. Both plugins are maintained and run on the Python 3.13 of the Airflow image with no workaround.
- **Project layout:** `meltano/meltano.yml` holds the whole load definition (the 7 streams with their keys, host, schema, `load_method`) and is versioned together with the plugin lock files. Only the credentials (user, password, database) are left out: Terraform injects them as `TARGET_POSTGRES_*` env vars from the `warehouse-credentials` Secret. `meltano install` runs at image build time, so tasks never download anything while running. Both plugins are pinned to the exact versions tested (`tap-csv` to a git commit, since its `v1.2.0` tag points to an older one; `target-postgres` to `0.8.1`), so a rebuild cannot pull a different plugin.
- **Environment required:** Meltano 4 refuses to run without an environment (`A Meltano environment must be specified`), so the project defines a single one, `prod`, as default. Found when the first `meltano run` in the cluster failed.
- **Alternatives:** Embulk. The S3 targets for Meltano (`target-s3-csv`, `target-s3`) were tested and are not maintained: they pin 2021-era dependencies (`boto3` 1.17, `pyarrow` 10) that fail on Python 3.13.

## D5. Ingestion strategy and idempotency
- **Decision:** `load_method: upsert`, with the primary key of each table declared in `tap-csv` (the first column of each file). Running the same DAG twice gives the same result: rows are updated, not duplicated.
- **Why:** it is a native feature of the target, needs no extra task and the table keeps a real primary key. The data was profiled: no duplicated or empty keys in any of the 7 files.
- **Tested, not assumed:** `load_method: overwrite` looked simpler but did **not** overwrite with `tap-csv` (the target only truncates when the tap sends an `ACTIVATE_VERSION` message, and `tap-csv` does not), so two runs produced 20 rows. A `DROP TABLE` task before each load would work but is a home-made version of a standard pattern, so it was dropped in favour of upsert.
- **Rows deleted at the source: detected, not fixed (deliberate).** Upsert never deletes, so if a new delivery has fewer rows, the old rows stay in `raw`, `raw` ends up with more rows than the file, and `validate_counts` fails the run. Nothing reaches `standard`, which keeps the last good version. This is kept on purpose:
  - The pipeline cannot tell a real deletion from a truncated or partial export (a common failure of legacy exports). Deleting rows automatically would turn a broken file into silent data loss; failing makes a person look at it.
  - The automatic alternatives were weighed: `TRUNCATE` + load before each run would mirror any file blindly, including a broken one, and leave `raw` empty while loading; a delete marker (`ACTIVATE_VERSION` / `hard_delete`) needs a tap that sends it, and `tap-csv` does not.
  - Recovery today: once the deletion is confirmed as real, empty the affected `raw` table (`TRUNCATE raw.<table>`) and re-run the DAG.
- **Duplicated keys:** a duplicated key in a future delivery makes the load fail, which also signals the problem instead of hiding it.

## D6. Kubernetes and Airflow deployment
- **Decision:** Minikube + official Airflow Helm chart, applied through Terraform (`helm_release`). Custom Airflow image with Meltano in an isolated virtualenv; Meltano is called by the DAG.
- **Why:** infrastructure is code and reproducible; the isolated virtualenv avoids dependency conflicts between Airflow and Meltano.
- **Alternatives:** hand-written manifests; running Meltano in separate pods with `KubernetesPodOperator` (better isolation, more complexity).
- **Executor:** `LocalExecutor` (tasks run inside the scheduler). The chart default, `CeleryExecutor`, adds workers and Redis, which is heavy for a 6 GB Minikube and unnecessary for this pipeline.
- **DAGs delivery:** baked into the custom image (`docker/airflow.Dockerfile` copies `dags/`), together with Meltano (4.4.1, in its own virtualenv; only the `meltano` command is exposed so it cannot shadow Airflow's `python`/`pip`). Code and runtime ship as one versioned unit, which is predictable for the demo. Trade-off: every DAG change needs an image rebuild and a new tag. Alternative: `gitSync` (no rebuild, but depends on a branch in GitHub). The image is built locally and loaded into Minikube (`minikube image load`), not pushed to a registry.
- **Warehouse connection:** Airflow reads the env var `AIRFLOW_CONN_WAREHOUSE` as the connection `warehouse`. Terraform builds the URI into its own Secret and the chart's `secret:` value exposes it to the pods, so no connection is created by hand in the UI and no password is in git.
- **Chart pinned** to 1.22.0 (Airflow 3.2.2) for reproducibility.
- **Helm hooks disabled for the migration and create-user jobs** (`useHelmHooks = false`). By default they run only after the release is ready, but the pods wait for the migration, so with Terraform's `wait = true` the install deadlocks and times out. Found when the first apply failed after 15 minutes.

## D7. Secrets
- **Decision:** no secrets in git. The Airflow admin password lives in a local, git-ignored `terraform/terraform.tfvars` (loaded automatically by Terraform); the README shows the expected name. Everything else is generated by Terraform (`random_*` resources: Airflow keys and the warehouse password) and stored only as Kubernetes Secrets, which Airflow and Meltano read from the environment.
- **Why:** challenge criterion; the repository is public.
- **Secret manager considered:** a cloud secret manager (e.g. AWS Secrets Manager) is the production path (rotation, audit, native Airflow secrets backend), but it does not remove the bootstrap problem (Airflow still needs an initial credential to read from it), and secrets created by Terraform end up in the state. For this POC we keep Kubernetes Secrets and mention the secret manager as the production evolution (talking point for the video).
- **Environment variables vs tfvars:** `TF_VAR_*` variables were used first, but they had to be set again in every terminal; `terraform.tfvars` removes that step. No example file is kept: the README shows the format in three lines.

## D8. Terraform state
- **Decision:** local state, git-ignored.
- **Why:** simplest option for a single-person POC; avoids the "bucket for the state must exist first" problem. The generated passwords are in this state, which is why it is never committed.
- **In a team:** use a remote backend (with locking) and one state per environment.

## D9. CI/CD
- **Decision:** lightweight GitHub Actions, triggered on pull requests and on pushes to `develop` and `main`: `terraform fmt`/`validate` (no credentials), `ruff` lint and format check, and a DAG import test that runs inside the project image built from the same Dockerfile as the cluster. `terraform apply` is manual from the local machine.
- **Why:** applying from CI would require a cluster reachable from the internet, which is out of proportion for a local Minikube.

## D10. Cost and cleanup
- **Decision:** nothing in this project costs money: everything runs on the local machine. Cleanup is `terraform destroy` + `minikube delete`, documented in the README.
- **Why:** removing the cloud dependency (D1) also removed the cost, the budget alert and the need to clean cloud leftovers.

## D11. Tooling and language
- Shell: Git Bash on Windows. Helper scripts are written in Python (standard library only) rather than shell, so they run on any OS and avoid Git Bash path rewriting.
- Code, comments and documentation in English.
- The source CSV files are **not** committed (see `.gitignore`).
- **Lesson learned:** check that every container image and plugin exists and runs *before* writing the infrastructure around it. The MinIO chart installed fine, but its image could no longer be pulled.

## D12. Transformations: raw → standard → curated
- **Decision:** the layers are built with plain SQL, run as Airflow tasks against the warehouse (a connection configured from the Kubernetes Secret). `standard` casts types (integers, numerics, dates and timestamps), turns blank text into NULL, drops the Meltano `_sdc_*` columns and adds two metadata columns, `source_extracted_at` (when Meltano read the file) and `processed_at` (when the table was built). Column names already arrive in snake_case, so nothing is renamed. `curated` is created but empty: it waits for the business rules that define the standard → curated transformations (the DAG has a placeholder task for it). The data was profiled beforehand (no duplicated or empty keys), so no deduplication is needed.
- **Why:** the data is a few MB, so SQL in Postgres is the simplest tool and the language the whole team already knows. Each task is a `.sql` file, easy to read, review and explain.
- **Alternatives:** Spark/Glue jobs (a lot of infrastructure for a few MB); dbt (a good fit, but one more tool to install, configure and explain).
- **Production path:** the same layers on object storage with a managed engine (Glue, Athena or dbt); the SQL is largely reusable.

## D13. DAG design (`dags/banvic_pipeline.py`)
- **Flow:** `wait_for_files` → `ingest_<table>` (x7) → `validate_counts` → `standardize_<table>` (x7) → `build_curated`. Scheduled `@daily` (and still triggerable by hand). The source is a file delivery, so the sensor absorbs late files: the run waits up to 30 minutes for them. `catchup=False`, so unpausing the DAG never replays old days. Event-driven triggering (an Airflow asset watcher fired by the arrival of a signal file) is the production evolution; it was not done because the landing folder is read-only and the 7 files need a single "delivery complete" marker, which adds a convention between source and pipeline for no gain at this scale.
- **One ingest task per table**, so a failure retries only that table and the UI shows each load. Each task runs `meltano el tap-csv target-postgres --select <table>`.
- **`max_active_tasks=2`.** Meltano keeps its run state in a local SQLite file, so the DAG runs at most two tasks at a time instead of all seven loads at once. Meltano also refuses two runs with the same state ID, so each table has its own (`--state-id banvic-<table>`). The data is small, so more parallelism would gain seconds and add risk.
- **Sensor:** a `PythonSensor` (reschedule mode). `FileSensor` was not used: it needs a filesystem connection and watches one file per task. A scheduled run proceeds only when all 7 files are **newer than the start of the last successful run** (`prev_start_date_success`), so the daily schedule does not reprocess old files; a manual run only needs the files to exist, because whoever triggers it means it. If no new delivery arrives within 30 minutes the sensor skips (`soft_fail`) instead of failing: a day without a delivery is not an incident. Trade-off: a delivery that never comes also shows up as a skipped run, not a red one. The file time is the delivery time because `deliver_source_files.py` stamps it (`minikube cp` would keep the original modification time).
- **Validation:** one task compares the row count of each CSV (parsed with `csv.reader`, since quoted fields may contain line breaks) with `count(*)` of the `raw` table, and fails on any difference. It has no retries: a count mismatch is a data problem that waiting will not fix.
- **One run at a time (`max_active_runs=1`).** A manual run overlapping a scheduled one would load and rebuild the same tables concurrently; the second run now waits in the queue.
- **Standard is rebuilt, not patched:** each `.sql` file does `DROP TABLE` + `CREATE TABLE AS` + primary key, and Airflow runs it in a single transaction. Re-running is safe and readers never see a half-built table.
- **Resilience:** `retries=2` with a 30 s `retry_delay` (a transient failure, such as Postgres restarting, has time to clear) and an `on_failure_callback` that logs DAG, task, run, attempt and error in one line. The 30 s delay is short on purpose for the demo; a real deployment would use minutes, possibly with exponential backoff. Timeouts make a hung task fail visibly instead of holding one of the two slots: 15 minutes per task (`execution_timeout`) and 1 hour per run (`dagrun_timeout`, which covers the 30-minute sensor wait plus a normal run of about a minute).
- **SQL in files:** the transformations live in `dags/sql/standard/*.sql`, outside the Python code, so they can be reviewed and changed without touching the DAG.

## Possible future improvements (optional, not committed to)
- **Deletions at the source.** Today they are detected, not applied (D5). Applying them safely needs a delete marker (`ACTIVATE_VERSION` / `hard_delete` in the target, which requires a tap that sends it) or a "delivery complete" signal from the source that confirms the file is whole.
- **History by delivery date.** Today a new delivery updates the tables in place and no history is kept. To keep it, add a delivery-date column (or a snapshot table) and let downstream layers choose which deliveries to read.
- **Automatic delivery to the node.** Today `scripts/deliver_source_files.py` is run by hand (see D2). A host-side watcher could run it when `data/` changes, at the cost of a process that must stay running.

## Out of scope
- Cloud services (S3, Glue, Athena), dbt, remote Terraform state, applying infrastructure from CI.
- The MCP server from the course was considered and dropped: the source is plain CSV files, so there is nothing to connect.
