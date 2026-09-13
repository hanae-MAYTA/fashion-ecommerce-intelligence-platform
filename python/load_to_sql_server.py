import pandas as pd
from sqlalchemy import create_engine
from pathlib import Path
import pyodbc

ROOT = Path(__file__).resolve().parents[1]
PROCESSED_DIR = ROOT / "data" / "processed"
SERVER = "DESKTOP-LKG2222"
DATABASE = "FashionEcommerce"

# Connexion SQLAlchemy (pour les dims, via pandas.to_sql)
engine = create_engine(
    f"mssql+pyodbc://{SERVER}/{DATABASE}"
    "?driver=ODBC+Driver+17+for+SQL+Server"
    "&trusted_connection=yes"
    "&TrustServerCertificate=yes",
    fast_executemany=True
)

# ── 1. Charger les dimensions (petites tables) ──
dims = {
    "Dim_Date": "dim_date.csv",
    "Dim_Customer": "dim_customer.csv",
    "Dim_Product": "dim_product.csv",
    "Dim_Store": "dim_store.csv",
    "Dim_Employee": "dim_employee.csv",
    "Dim_Discount": "dim_discount.csv",
}

for table_name, filename in dims.items():
    df = pd.read_csv(PROCESSED_DIR / filename, low_memory=False)
    df.to_sql(
        table_name,
        engine,
        schema="warehouse",
        if_exists="append",
        index=False,
        chunksize=5000
    )
    print(f"{table_name}: {len(df)} lignes chargées")

# ── 2. Charger Fact_Sales via BULK INSERT ──
fact_path = (PROCESSED_DIR / "fact_sales.csv").resolve()

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};DATABASE={DATABASE};"
    f"Trusted_Connection=yes;TrustServerCertificate=yes;"
)
cursor = conn.cursor()

# sécurité : si un essai précédent a partiellement inséré des lignes
# avant d'échouer, on repart d'une table vide
cursor.execute("SELECT COUNT(*) FROM warehouse.Fact_Sales")
existing = cursor.fetchone()[0]
if existing > 0:
    print(f"Lignes déjà présentes avant retry: {existing} -> TRUNCATE")
    cursor.execute("TRUNCATE TABLE warehouse.Fact_Sales")
    conn.commit()

bulk_insert_sql = f"""
BULK INSERT warehouse.Fact_Sales
FROM '{fact_path}'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0d0a',
    CODEPAGE = '65001',
    TABLOCK
);
"""

cursor.execute(bulk_insert_sql)
conn.commit()

cursor.execute("SELECT COUNT(*) FROM warehouse.Fact_Sales")
print("Fact_Sales:", cursor.fetchone()[0], "lignes chargées")

cursor.close()
conn.close()