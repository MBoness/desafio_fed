"""Smoke test for the custom image: confirms the isolated Meltano install works.

Trigger it manually from the Airflow UI. It is a setup check, not part of the
pipeline, and can be removed once the real ingestion DAG exists.
"""

from datetime import datetime

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

with DAG(
    dag_id="meltano_smoke_test",
    schedule=None,  # manual runs only
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["setup"],
) as dag:
    BashOperator(
        task_id="meltano_version",
        bash_command="meltano --version",
    )
