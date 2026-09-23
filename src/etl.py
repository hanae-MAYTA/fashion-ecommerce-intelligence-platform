"""ETL : CSV bruts (data/raw/) -> tables du modèle en étoile (data/processed/).

Chaque règle de nettoyage est justifiée dans `notebooks/01_data_audit.ipynb`.

Usage :
    python -m src.etl
"""

import logging
from pathlib import Path

import numpy as np
import pandas as pd

from src.config import PROCESSED_DIR, RAW_DIR

logger = logging.getLogger(__name__)

RAW_TABLES = ["customers", "products", "discounts", "employees", "stores", "transactions"]

# Pays et villes chinoises sont saisis dans la langue locale dans les sources.
COUNTRY_NAMES = {"中国": "China", "Deutschland": "Germany", "España": "Spain"}
CITY_NAMES = {"上海": "Shanghai", "北京": "Beijing", "广州": "Guangzhou", "深圳": "Shenzhen", "重庆": "Chongqing"}

FACT_COLUMNS = [
    "Invoice_ID", "Line", "Date_Key", "Customer_Key", "Product_Key", "Store_Key",
    "Employee_Key", "SKU", "Size", "Color", "Quantity", "Unit_Price", "Discount",
    "Line_Total", "Invoice_Total", "Transaction_Type", "Payment_Method", "Currency",
]


# ── Chargement ────────────────────────────────────────────────────────────────

def load_raw_data(raw_dir: Path = RAW_DIR) -> dict[str, pd.DataFrame]:
    missing = [name for name in RAW_TABLES if not (raw_dir / f"{name}.csv").exists()]
    if missing:
        raise FileNotFoundError(
            f"Fichiers absents de {raw_dir} : {', '.join(f'{m}.csv' for m in missing)}. "
            "Voir data/README.md pour télécharger le dataset."
        )

    read_options = {
        "customers": {"dtype": {"Telephone": "string"}, "parse_dates": ["Date Of Birth"]},
        "discounts": {"parse_dates": ["Start", "End"]},
        "stores": {"dtype": {"ZIP Code": "string"}},
        "transactions": {"parse_dates": ["Date"]},
    }
    return {
        name: pd.read_csv(raw_dir / f"{name}.csv", **read_options.get(name, {}))
        for name in RAW_TABLES
    }


# ── Nettoyage ─────────────────────────────────────────────────────────────────

def standardize_location(df: pd.DataFrame) -> pd.DataFrame:
    return df.assign(
        Country=df["Country"].replace(COUNTRY_NAMES),
        City=df["City"].replace(CITY_NAMES),
    )


def clean_customers(customers: pd.DataFrame) -> pd.DataFrame:
    # 35 % de Job Title manquants, sans modalité dominante : pas d'imputation possible.
    return standardize_location(customers).assign(
        **{"Job Title": customers["Job Title"].fillna("Unknown")}
    )


def clean_products(products: pd.DataFrame) -> pd.DataFrame:
    # Sizes est manquant uniquement pour les accessoires (taille unique).
    return products.assign(
        Color=products["Color"].fillna("Unknown"),
        Sizes=products["Sizes"].fillna("N/A"),
    )


def clean_discounts(discounts: pd.DataFrame) -> pd.DataFrame:
    # Catégorie manquante = promotion globale (Black Friday, soldes de fin d'année).
    return discounts.rename(columns={"Discont": "Discount"}).assign(
        Category=discounts["Category"].fillna("All"),
        **{"Sub Category": discounts["Sub Category"].fillna("All")},
    )


def clean_stores(stores: pd.DataFrame) -> pd.DataFrame:
    # Store Name suit toujours le motif "Store <City>" : on le régénère avec la ville traduite.
    stores = standardize_location(stores)
    return stores.assign(**{"Store Name": "Store " + stores["City"]})


def clean_transactions(transactions: pd.DataFrame) -> pd.DataFrame:
    df = transactions.drop_duplicates().copy()
    logger.info("Transactions : %d doublons exacts supprimés", len(transactions) - len(df))

    df["Color"] = df["Color"].fillna("Unknown")
    df["Size"] = df["Size"].fillna("Unknown")

    # Les retours ont Discount = 0 alors que le montant remboursé est le prix réellement
    # payé : |Line Total| / (Unit Price x Quantity) = 1 - remise de la vente d'origine.
    # On reconstitue cette remise pour que Line Total = ±Unit Price x Quantity x (1 - Discount)
    # soit vrai sur toutes les lignes.
    is_return = df["Transaction Type"].eq("Return")
    paid_ratio = df.loc[is_return, "Line Total"].abs() / (
        df.loc[is_return, "Unit Price"] * df.loc[is_return, "Quantity"]
    )
    df.loc[is_return, "Discount"] = (1 - paid_ratio).round(2)

    return df.drop(columns="Currency Symbol").reset_index(drop=True)


def count_financial_inconsistencies(transactions: pd.DataFrame, tolerance: float = 0.05) -> int:
    """Lignes où Line Total ≠ ±Unit Price x Quantity x (1 - Discount) (tolérance d'arrondi)."""
    sign = np.where(transactions["Transaction Type"].eq("Return"), -1, 1)
    expected = sign * transactions["Unit Price"] * transactions["Quantity"] * (1 - transactions["Discount"])
    return int(((transactions["Line Total"] - expected).abs() > tolerance).sum())


def clean_all(raw: dict[str, pd.DataFrame]) -> dict[str, pd.DataFrame]:
    return {
        "customers": clean_customers(raw["customers"]),
        "products": clean_products(raw["products"]),
        "discounts": clean_discounts(raw["discounts"]),
        "employees": raw["employees"].copy(),
        "stores": clean_stores(raw["stores"]),
        "transactions": clean_transactions(raw["transactions"]),
    }


# ── Modèle en étoile ──────────────────────────────────────────────────────────

def to_date_key(dates: pd.Series) -> pd.Series:
    return (dates.dt.year * 10_000 + dates.dt.month * 100 + dates.dt.day).astype("int32")


def compute_age(birth_dates: pd.Series, reference_date: pd.Timestamp) -> pd.Series:
    birthday_not_reached = (birth_dates.dt.month > reference_date.month) | (
        (birth_dates.dt.month == reference_date.month) & (birth_dates.dt.day > reference_date.day)
    )
    return reference_date.year - birth_dates.dt.year - birthday_not_reached.astype(int)


def build_dim_date(transactions: pd.DataFrame) -> pd.DataFrame:
    dates = pd.Series(pd.date_range(
        transactions["Date"].min().normalize(), transactions["Date"].max().normalize(), freq="D"
    ))
    return pd.DataFrame({
        "Date_Key": to_date_key(dates),
        "Date": dates.dt.date,
        "Year": dates.dt.year,
        "Quarter": dates.dt.quarter,
        "Month": dates.dt.month,
        "Month_Name": dates.dt.month_name(),
        "Day": dates.dt.day,
        "Day_Of_Week": dates.dt.dayofweek + 1,  # 1 = lundi
        "Day_Name": dates.dt.day_name(),
        "Is_Weekend": dates.dt.dayofweek >= 5,
        "Week_Of_Year": dates.dt.isocalendar().week.astype(int),
    })


def build_dim_customer(customers: pd.DataFrame, reference_date: pd.Timestamp) -> pd.DataFrame:
    """L'âge est calculé à la dernière date du dataset (et non à la date du jour) pour rester reproductible."""
    dim = customers.rename(columns={
        "Customer ID": "Customer_Key",
        "Name": "Customer_Name",
        "Date Of Birth": "Date_Of_Birth",
        "Job Title": "Job_Title",
    })
    dim["Age"] = compute_age(dim["Date_Of_Birth"], reference_date)
    dim["Date_Of_Birth"] = dim["Date_Of_Birth"].dt.date
    return dim[["Customer_Key", "Customer_Name", "Email", "Telephone", "City", "Country",
                "Gender", "Date_Of_Birth", "Job_Title", "Age"]]


def build_dim_product(products: pd.DataFrame) -> pd.DataFrame:
    # Seule la description anglaise est conservée (5 autres langues dans la source).
    return products.rename(columns={
        "Product ID": "Product_Key",
        "Sub Category": "Sub_Category",
        "Description EN": "Description",
        "Sizes": "Available_Sizes",
        "Production Cost": "Production_Cost",
    })[["Product_Key", "Category", "Sub_Category", "Description", "Color",
        "Available_Sizes", "Production_Cost"]]


def build_dim_store(stores: pd.DataFrame) -> pd.DataFrame:
    return stores.rename(columns={
        "Store ID": "Store_Key",
        "Store Name": "Store_Name",
        "ZIP Code": "ZIP_Code",
        "Number of Employees": "Number_Of_Employees",
    })[["Store_Key", "Store_Name", "City", "Country", "ZIP_Code", "Latitude",
        "Longitude", "Number_Of_Employees"]]


def build_dim_employee(employees: pd.DataFrame) -> pd.DataFrame:
    return employees.rename(columns={
        "Employee ID": "Employee_Key",
        "Store ID": "Store_Key",
        "Name": "Employee_Name",
    })[["Employee_Key", "Store_Key", "Employee_Name", "Position"]]


def build_dim_discount(discounts: pd.DataFrame) -> pd.DataFrame:
    dim = discounts.rename(columns={"Discount": "Discount_Rate", "Sub Category": "Sub_Category"})
    dim.insert(0, "Discount_Key", np.arange(1, len(dim) + 1))
    dim["Start"] = dim["Start"].dt.date
    dim["End"] = dim["End"].dt.date
    return dim[["Discount_Key", "Category", "Sub_Category", "Start", "End",
                "Discount_Rate", "Description"]]


def build_fact_sales(transactions: pd.DataFrame) -> pd.DataFrame:
    """Grain : une ligne de facture (Invoice_ID, Line)."""
    fact = transactions.rename(columns={
        "Invoice ID": "Invoice_ID",
        "Customer ID": "Customer_Key",
        "Product ID": "Product_Key",
        "Store ID": "Store_Key",
        "Employee ID": "Employee_Key",
        "Unit Price": "Unit_Price",
        "Line Total": "Line_Total",
        "Invoice Total": "Invoice_Total",
        "Transaction Type": "Transaction_Type",
        "Payment Method": "Payment_Method",
    })
    fact["Date_Key"] = to_date_key(fact["Date"])
    return fact[FACT_COLUMNS]


def build_star_schema(clean: dict[str, pd.DataFrame]) -> dict[str, pd.DataFrame]:
    transactions = clean["transactions"]
    reference_date = transactions["Date"].max().normalize()
    return {
        "dim_date": build_dim_date(transactions),
        "dim_customer": build_dim_customer(clean["customers"], reference_date),
        "dim_product": build_dim_product(clean["products"]),
        "dim_store": build_dim_store(clean["stores"]),
        "dim_employee": build_dim_employee(clean["employees"]),
        "dim_discount": build_dim_discount(clean["discounts"]),
        "fact_sales": build_fact_sales(transactions),
    }


# ── Contrôles ─────────────────────────────────────────────────────────────────

def validate_star_schema(tables: dict[str, pd.DataFrame]) -> None:
    """Lève une erreur si une clé étrangère est orpheline ou si une clé primaire est dupliquée."""
    fact = tables["fact_sales"]
    foreign_keys = {
        "Date_Key": "dim_date",
        "Customer_Key": "dim_customer",
        "Product_Key": "dim_product",
        "Store_Key": "dim_store",
        "Employee_Key": "dim_employee",
    }
    errors = []
    for key, dim_name in foreign_keys.items():
        dim_keys = tables[dim_name][key]
        if dim_keys.duplicated().any():
            errors.append(f"{dim_name}.{key} n'est pas unique")
        orphans = int((~fact[key].isin(dim_keys)).sum())
        if orphans:
            errors.append(f"fact_sales.{key} : {orphans} lignes orphelines")

    orphan_employees = int((~tables["dim_employee"]["Store_Key"].isin(tables["dim_store"]["Store_Key"])).sum())
    if orphan_employees:
        errors.append(f"dim_employee.Store_Key : {orphan_employees} lignes orphelines")

    if errors:
        raise ValueError("Modèle en étoile invalide :\n- " + "\n- ".join(errors))

    # La clé naturelle n'est pas contrainte en base (clé technique Sale_Key) : on la surveille.
    natural_key_duplicates = int(fact.duplicated(subset=["Invoice_ID", "Line"]).sum())
    if natural_key_duplicates:
        logger.warning("fact_sales : %d doublons sur (Invoice_ID, Line)", natural_key_duplicates)


def export_tables(tables: dict[str, pd.DataFrame], output_dir: Path = PROCESSED_DIR) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, df in tables.items():
        # Fin de ligne \n explicite : attendue par le BULK INSERT (ROWTERMINATOR = '0x0a').
        df.to_csv(output_dir / f"{name}.csv", index=False, lineterminator="\n")
        logger.info("%-13s %10d lignes -> %s", name, len(df), output_dir / f"{name}.csv")


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    clean = clean_all(load_raw_data())
    inconsistencies = count_financial_inconsistencies(clean["transactions"])
    logger.info("Lignes financièrement incohérentes après nettoyage : %d", inconsistencies)
    tables = build_star_schema(clean)
    validate_star_schema(tables)
    export_tables(tables)


if __name__ == "__main__":
    main()
