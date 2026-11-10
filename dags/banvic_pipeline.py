"""BanVic pipeline: source CSV files -> Postgres warehouse (raw -> standard -> curated).

wait_for_files >> ingest_<table> (x7) >> validate_counts >> standardize_<table> (x7) >> build_curated

Runs daily and can also be triggered by hand. The sensor makes the schedule safe for
a file delivery: if the files are late, the run waits for them (up to 30 minutes).
Every step is idempotent, so re-running the whole DAG, or any single task, is safe:
- ingest: Meltano upserts by primary key (see meltano/meltano.yml);
- standardize: each table is dropped and rebuilt in one transaction.
"""

import csv
import logging
from datetime import datetime, timedelta
from pathlib import Path

from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.sensors.python import PythonSensor
from airflow.sdk import DAG, task

log = logging.getLogger(__name__)

SOURCE_DIR = Path("/opt/airflow/source")  # CSV landing folder (mounted by Terraform)
WAREHOUSE_CONN_ID = "warehouse"  # AIRFLOW_CONN_WAREHOUSE, injected by Terraform
TABLES = [
    "agencias",
    "clientes",
    "colaborador_agencia",
    "colaboradores",
    "contas",
    "propostas_credito",
    "transacoes",
]


def log_failure(context):
    """Failure callback: one clear log line saying what failed and where to look."""
    ti = context["task_instance"]
    log.error(
        "PIPELINE FAILURE | dag=%s task=%s run=%s try=%s | error=%s",
        ti.dag_id,
        ti.task_id,
        context["run_id"],
        ti.try_number,
        context.get("exception"),
    )


def all_files_arrived() -> bool:
    missing = [t for t in TABLES if not (SOURCE_DIR / f"{t}.csv").exists()]
    if missing:
        log.info("Still waiting for: %s", ", ".join(missing))
    return not missing


with DAG(
    dag_id="banvic_pipeline",
    schedule="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    # Two tasks at a time. Meltano keeps its run state in a local SQLite file, so
    # more parallelism would only add lock contention for a few MB of data.
    max_active_tasks=2,
    default_args={
        "retries": 2,
        # Wait before retrying so a transient failure (e.g. Postgres restarting) can clear.
        "retry_delay": timedelta(seconds=30),
        "on_failure_callback": log_failure,
    },
    tags=["banvic", "elt"],
) as dag:
    # reschedule mode frees the worker slot between checks.
    wait_for_files = PythonSensor(
        task_id="wait_for_files",
        python_callable=all_files_arrived,
        mode="reschedule",
        poke_interval=30,
        timeout=60 * 30,
    )

    @task
    def validate_counts():
        """Every CSV row must be in raw: compare file rows with table rows."""
        hook = PostgresHook(postgres_conn_id=WAREHOUSE_CONN_ID)
        mismatches = []
        for table in TABLES:
            # csv.reader, not line counting: quoted fields may contain line breaks.
            with open(SOURCE_DIR / f"{table}.csv", newline="", encoding="utf-8") as f:
                expected = sum(1 for _ in csv.reader(f)) - 1  # minus the header
            loaded = hook.get_first(f"SELECT count(*) FROM raw.{table}")[0]
            log.info("%-20s file=%-6s raw=%s", table, expected, loaded)
            if expected != loaded:
                mismatches.append(f"{table}: file={expected} raw={loaded}")
        if mismatches:
            raise ValueError("Row count mismatch: " + "; ".join(mismatches))

    @task
    def build_curated():
        """Placeholder: the curated layer waits for business rules."""
        log.info(
            "Schema `curated` exists. Waiting for the business rules to define "
            "the standard -> curated transformations; nothing to build yet."
        )

    validate = validate_counts()
    curated = build_curated()

    for table in TABLES:
        ingest = BashOperator(
            task_id=f"ingest_{table}",
            # `el` (extract-load) accepts --select, so each task loads a single stream.
            # Meltano refuses two runs with the same state ID at once, so each table
            # gets its own, which is what allows two loads to run in parallel.
            bash_command=(
                f"meltano el tap-csv target-postgres --select {table} "
                f"--state-id banvic-{table}"
            ),
        )
        standardize = SQLExecuteQueryOperator(
            task_id=f"standardize_{table}",
            conn_id=WAREHOUSE_CONN_ID,
            sql=f"sql/standard/{table}.sql",  # relative to this DAG folder
        )
        wait_for_files >> ingest >> validate >> standardize >> curated
