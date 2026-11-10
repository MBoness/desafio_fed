"""Simulate the legacy (on-premises) system delivering its CSV export.

Copies every CSV in ./data into the Minikube node landing folder that
Airflow watches with a sensor. In production the files would arrive
through SFTP or an NFS share; this script stands in for that delivery.

Usage (from any folder):
    python scripts/deliver_source_files.py

Files are copied, not mounted: Docker Desktop on Windows did not expose host
mounts reliably, and `minikube mount` needs a terminal kept open. Copying
again overwrites the files, so the script is safe to rerun.
"""

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = "data"
LANDING_DIR = "/data/banvic"


def run(*args: str) -> None:
    """Run a command from the repo root and stop the script if it fails."""
    try:
        subprocess.run(args, cwd=REPO_ROOT, check=True)
    except FileNotFoundError:
        sys.exit(f"Command not found: {args[0]}. Is it installed and on PATH?")
    except subprocess.CalledProcessError as error:
        sys.exit(f"Command failed ({error.returncode}): {' '.join(args)}")


def main() -> None:
    csv_files = sorted((REPO_ROOT / SOURCE_DIR).glob("*.csv"))
    if not csv_files:
        sys.exit(f"No CSV files found in ./{SOURCE_DIR}. Copy the BanVic files there first.")

    run("minikube", "ssh", "--", "sudo", "mkdir", "-p", LANDING_DIR)

    for csv_file in csv_files:
        print(f"Delivering {csv_file.name}")
        # Relative POSIX path on purpose: `minikube cp` splits on ":" to find
        # the node name, so a Windows path like C:\... would be misread.
        source = f"{SOURCE_DIR}/{csv_file.name}"
        target = f"{LANDING_DIR}/{csv_file.name}"
        run("minikube", "cp", source, f"minikube:{target}")
        # `minikube cp` keeps the original modification time. The DAG sensor uses the
        # file time to tell a new delivery from an old file, so stamp the delivery time.
        run("minikube", "ssh", "--", "sudo", "touch", target)

    print("Files in the landing folder:")
    run("minikube", "ssh", "--", "ls", "-l", LANDING_DIR)


if __name__ == "__main__":
    main()
