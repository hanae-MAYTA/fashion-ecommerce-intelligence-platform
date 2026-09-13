# python/load_fact_only.py
import pyodbc
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSED_DIR = ROOT / "data" / "processed"
SERVER = "DESKTOP-LKG2222"
DATABASE = "FashionEcommerce"

fact_path = (PROCESSED_DIR / "fact_sales.csv").resolve()

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};DATABASE={DATABASE};"
    f"Trusted_Connection=yes;TrustServerCertificate=yes;"
)
cursor = conn.cursor()

# 1. Vider la staging et Fact_Sales avant de recharger
cursor.execute("TRUNCATE TABLE staging.Fact_Sales_Staging")
cursor.execute("TRUNCATE TABLE warehouse.Fact_Sales")
conn.commit()

# 2. BULK INSERT vers staging (pas de colonne IDENTITY -> mapping direct OK)
bulk_insert_sql = f"""
BULK INSERT staging.Fact_Sales_Staging
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

cursor.execute("SELECT COUNT(*) FROM staging.Fact_Sales_Staging")
print("Staging:", cursor.fetchone()[0], "lignes chargées")

# 3. Transfert staging -> warehouse (Sale_Key s'auto-génère)
insert_sql = """
INSERT INTO warehouse.Fact_Sales (
    Invoice_ID, Line, Date_Key, Customer_Key, Product_Key,
    Store_Key, Employee_Key, SKU, Size, Color,
    Quantity, Unit_Price, Discount, Line_Total, Invoice_Total,
    Return_Ratio, Transaction_Type, Payment_Method, Currency
)
SELECT
    Invoice_ID, Line, Date_Key, Customer_Key, Product_Key,
    Store_Key, Employee_Key, SKU, Size, Color,
    Quantity, Unit_Price, Discount, Line_Total, Invoice_Total,
    Return_Ratio, Transaction_Type, Payment_Method, Currency
FROM staging.Fact_Sales_Staging;
"""
cursor.execute(insert_sql)
conn.commit()

cursor.execute("SELECT COUNT(*) FROM warehouse.Fact_Sales")
print("Fact_Sales:", cursor.fetchone()[0], "lignes chargées")

cursor.close()
conn.close()