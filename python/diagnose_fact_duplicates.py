import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROCESSED_DIR = ROOT / "data" / "processed"
fact_sales = pd.read_csv(PROCESSED_DIR / "fact_sales.csv")

dup_mask = fact_sales.duplicated(subset=["Invoice_ID", "Line"], keep=False)
duplicates = fact_sales[dup_mask].sort_values(["Invoice_ID", "Line"])

print("Lignes concernées par un doublon (Invoice_ID, Line):", len(duplicates))
print("Paires (Invoice_ID, Line) dupliquées:", duplicates.groupby(["Invoice_ID","Line"]).ngroups)

# Sont-elles des doublons EXACTS (toutes colonnes identiques) ou différentes ?
exact_dup_count = fact_sales.duplicated(keep=False).sum()
print("Doublons exacts (toutes colonnes):", exact_dup_count)

duplicates.head(20)