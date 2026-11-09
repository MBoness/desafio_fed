# Custom Airflow image: official Airflow + Meltano (isolated) + our DAGs.
# Build from the repository root:
#   docker build -t banvic-airflow:<tag> -f docker/airflow.Dockerfile .
FROM apache/airflow:3.2.2

# Meltano lives in its own virtualenv so its dependencies can never clash with
# Airflow's. Only the `meltano` command is exposed (symlink below); putting the
# whole venv on PATH would make its `python`/`pip` shadow Airflow's.
RUN python -m venv /home/airflow/meltano-venv \
    && /home/airflow/meltano-venv/bin/pip install --no-cache-dir meltano==4.4.1 \
    && ln -s /home/airflow/meltano-venv/bin/meltano /home/airflow/.local/bin/meltano

# DAGs are baked into the image so code and runtime ship together (see DECISIONS.md).
COPY --chown=airflow:0 dags/ /opt/airflow/dags/
