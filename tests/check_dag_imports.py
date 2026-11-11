"""Fail if any DAG cannot be imported. Run inside the project image:

docker run --rm -v "$PWD/tests:/tests:ro" --entrypoint python banvic-airflow:ci /tests/check_dag_imports.py
"""

import sys

from airflow.models import DagBag

bag = DagBag("/opt/airflow/dags", include_examples=False)

print("DAGs found:", sorted(bag.dags))
for path, error in bag.import_errors.items():
    print(f"IMPORT ERROR in {path}:\n{error}")

# An empty DagBag would also "pass" silently, so require at least one DAG.
sys.exit(1 if bag.import_errors or not bag.dags else 0)
