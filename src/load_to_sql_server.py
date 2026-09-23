"""Charge les tables de data/processed/ dans le schéma `warehouse` de SQL Server.

Prérequis : scripts sql/01 -> sql/03 exécutés, puis `python -m src.etl`.

Usage :
    python -m src.load_to_sql_server              # dimensions + Fact_Sales
    python -m src.load_to_sql_server --fact-only  # recharge uniquement Fact_Sales

Le chargement est idempotent : les tables sont vidées avant d'être rechargées.
"""

import argparse
import logging
from pathlib import Path

import pandas as pd
from sqlalchemy import text
from sqlalchemy.engine import Engine

from src.config import DB_BULK_DATA_DIR, PROCESSED_DIR
from src.db import get_engine
from src.etl import FACT_COLUMNS

logger = logging.getLogger(__name__)

# Ordre compatible avec les clés étrangères (Dim_Employee référence Dim_Store).
DIMENSIONS = ["Dim_Date", "Dim_Store", "Dim_Employee", "Dim_Customer", "Dim_Product", "Dim_Discount"]
STRING_COLUMNS = {"Telephone": "string", "ZIP_Code": "string"}


def csv_path(table: str) -> Path:
    path = PROCESSED_DIR / f"{table.lower()}.csv"
    if not path.exists():
        raise FileNotFoundError(f"{path} introuvable : lancer d'abord `python -m src.etl`.")
    return path


def count_rows(engine: Engine, table: str) -> int:
    with engine.connect() as conn:
        return conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar_one()


def load_dimensions(engine: Engine) -> None:
    with engine.begin() as conn:
        # Fact_Sales référence les dimensions : elle doit être vidée en premier.
        conn.execute(text("TRUNCATE TABLE warehouse.Fact_Sales"))
        for table in reversed(DIMENSIONS):
            conn.execute(text(f"DELETE FROM warehouse.{table}"))

    for table in DIMENSIONS:
        df = pd.read_csv(csv_path(table), dtype=STRING_COLUMNS)
        df.to_sql(table, engine, schema="warehouse", if_exists="append", index=False, chunksize=5_000)
        logger.info("warehouse.%-13s %10d lignes", table, len(df))


def load_fact_sales(engine: Engine) -> None:
    """BULK INSERT vers une table de staging, puis transfert vers warehouse.Fact_Sales.

    Le fichier CSV doit être lisible par SQL Server : chemin local par défaut,
    ou DB_BULK_DATA_DIR si le serveur voit le dossier autrement (conteneur Docker).
    """
    local_path = csv_path("Fact_Sales").resolve()
    server_path = f"{DB_BULK_DATA_DIR.rstrip('/')}/{local_path.name}" if DB_BULK_DATA_DIR else str(local_path)
    path = server_path.replace("'", "''")
    columns = ", ".join(FACT_COLUMNS)

    with engine.begin() as conn:
        conn.execute(text("TRUNCATE TABLE staging.Fact_Sales"))
        # Pas d'option CODEPAGE (non supportée par SQL Server sous Linux/Docker) :
        # fact_sales.csv ne contient que des caractères ASCII.
        conn.execute(text(f"""
            BULK INSERT staging.Fact_Sales
            FROM '{path}'
            WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"',
                  ROWTERMINATOR = '0x0a', TABLOCK);
        """))
        conn.execute(text("TRUNCATE TABLE warehouse.Fact_Sales"))
        conn.execute(text(f"""
            INSERT INTO warehouse.Fact_Sales WITH (TABLOCK) ({columns})
            SELECT {columns} FROM staging.Fact_Sales;
        """))

    logger.info("warehouse.Fact_Sales    %10d lignes", count_rows(engine, "warehouse.Fact_Sales"))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fact-only", action="store_true", help="ne recharger que Fact_Sales")
    args = parser.parse_args()

    engine = get_engine()
    if not args.fact_only:
        load_dimensions(engine)
    load_fact_sales(engine)


if __name__ == "__main__":
    main()
