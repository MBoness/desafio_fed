"""BanVic pipeline: source CSV files -> Postgres warehouse (raw -> standard -> curated).

wait_for_files >> ingest_<table> (x7) >> validate_counts >> standardize_<table> (x7) >> build_curated

Runs daily and can also be triggered by hand. The sensor makes the schedule safe for
a file delivery: a scheduled run waits (up to 30 minutes) for files newer than the
last successful run, and is skipped if none arrive. A manual run only needs the files.
Every step is idempotent, so re-running the whole DAG, or any single task, is safe:
- ingest: Meltano upserts by primary key (see meltano/meltano.yml);
- standardize and build_curated: each table is dropped and rebuilt in one transaction.
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
    """Failure callback: one clear log line saying what failed and where to look.

    Used for tasks and for the whole run: a run that hits `dagrun_timeout` is
    stopped without task callbacks, so only the run-level callback reports it.
    """
    dag_run = context["dag_run"]
    ti = context.get("task_instance")  # absent in the run-level callback
    log.error(
        "PIPELINE FAILURE | dag=%s task=%s run=%s try=%s | error=%s",
        dag_run.dag_id,
        ti.task_id if ti else "-",
        dag_run.run_id,
        ti.try_number if ti else "-",
        context.get("exception") or context.get("reason"),
    )


def files_are_ready(source_dir: Path, tables: list[str], since: float | None) -> bool:
    """True when every file exists and, if `since` is given, is newer than it."""
    waiting = []
    for table in tables:
        path = source_dir / f"{table}.csv"
        if not path.exists():
            waiting.append(f"{table} (missing)")
        elif since is not None and path.stat().st_mtime <= since:
            waiting.append(f"{table} (not updated since the last run)")
    if waiting:
        log.info("Still waiting for: %s", ", ".join(waiting))
    return not waiting


def new_delivery_arrived(dag_run, prev_start_date_success=None) -> bool:
    """Sensor condition.

    A scheduled run only proceeds when all files were delivered after the previous
    successful run started; otherwise the old files would be reprocessed every day.
    A manual run only needs the files to exist: whoever triggers it means it.
    """
    since = None
    run_type = getattr(dag_run.run_type, "value", dag_run.run_type)  # enum or plain str
    if run_type != "manual" and prev_start_date_success:
        since = prev_start_date_success.timestamp()
    return files_are_ready(SOURCE_DIR, TABLES, since)


with DAG(
    dag_id="banvic_pipeline",
    schedule="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    # One run at a time: a manual run overlapping a scheduled one would load and
    # rebuild the same tables concurrently.
    max_active_runs=1,
    # A normal run takes about a minute (plus up to 30 minutes of sensor wait);
    # anything longer is stuck and should fail visibly instead of holding the slot.
    dagrun_timeout=timedelta(hours=1),
    on_failure_callback=log_failure,  # run-level failures, e.g. the timeout above
    # Two tasks at a time. Meltano keeps its run state in a local SQLite file, so
    # more parallelism would only add lock contention for a few MB of data.
    max_active_tasks=2,
    default_args={
        "retries": 2,
        # Wait before retrying so a transient failure (e.g. Postgres restarting) can clear.
        "retry_delay": timedelta(seconds=30),
        # A hung Meltano or SQL task fails instead of blocking one of the two slots.
        "execution_timeout": timedelta(minutes=15),
        "on_failure_callback": log_failure,
    },
    tags=["banvic", "elt"],
) as dag:
    # reschedule mode frees the worker slot between checks.
    wait_for_files = PythonSensor(
        task_id="wait_for_files",
        python_callable=new_delivery_arrived,
        mode="reschedule",
        poke_interval=30,
        timeout=60 * 30,
        # No new delivery within the window is not an error: the run is skipped.
        soft_fail=True,
    )

    # No retries: a count mismatch is a data problem that waiting will not fix.
    @task(retries=0)
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

    # Example analyst-ready table; it reads several standard tables, so it runs last.
    build_curated = SQLExecuteQueryOperator(
        task_id="build_curated",
        conn_id=WAREHOUSE_CONN_ID,
        sql="sql/curated/resumo_agencias.sql",
    )

    validate = validate_counts()

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
        wait_for_files >> ingest >> validate >> standardize >> build_curated
