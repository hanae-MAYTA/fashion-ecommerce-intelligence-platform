"""Connexion à SQL Server (authentification Windows par défaut, SQL si DB_USER est défini)."""

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, Engine

from src import config


def get_engine() -> Engine:
    query = {"driver": config.DB_DRIVER, "TrustServerCertificate": "yes"}
    if config.DB_USER:
        url = URL.create(
            "mssql+pyodbc",
            username=config.DB_USER,
            password=config.DB_PASSWORD,
            host=config.DB_SERVER,
            database=config.DB_NAME,
            query=query,
        )
    else:
        url = URL.create(
            "mssql+pyodbc",
            host=config.DB_SERVER,
            database=config.DB_NAME,
            query={**query, "Trusted_Connection": "yes"},
        )
    return create_engine(url, fast_executemany=True)


def read_sql(query: str, engine: Engine, **params) -> pd.DataFrame:
    """Exécute une requête paramétrée (`:param`) et renvoie un DataFrame."""
    with engine.connect() as conn:
        return pd.read_sql(text(query), conn, params=params)
