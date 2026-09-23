"""Chemins du projet et paramètres de connexion (lus depuis `.env`)."""

import os
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env")

DATA_DIR = PROJECT_ROOT / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"

DB_SERVER = os.getenv("DB_SERVER", "localhost")
DB_NAME = os.getenv("DB_NAME", "FashionEcommerce")
DB_DRIVER = os.getenv("DB_DRIVER", "ODBC Driver 17 for SQL Server")
DB_USER = os.getenv("DB_USER") or None
DB_PASSWORD = os.getenv("DB_PASSWORD") or None
# Chemin de data/processed vu par SQL Server (ex. volume Docker) ; par défaut le chemin local.
DB_BULK_DATA_DIR = os.getenv("DB_BULK_DATA_DIR") or None

RANDOM_STATE = 42
