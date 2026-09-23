# Données

Les données ne sont **pas versionnées** (≈ 1 Go, et la table clients contient des noms, emails et téléphones — synthétiques, mais traités comme des données personnelles).

## Source

Dataset public Kaggle **« Global Fashion Retail Sales »** (données synthétiques d'une enseigne de mode fictive, 35 magasins dans 7 pays, janvier 2023 → mars 2025).

Télécharger les 6 fichiers CSV et les placer dans `data/raw/` avec exactement ces noms :

```
data/raw/
├── customers.csv
├── discounts.csv
├── employees.csv
├── products.csv
├── stores.csv
└── transactions.csv
```

## Organisation

| Dossier | Contenu | Produit par |
|---|---|---|
| `raw/` | CSV sources, jamais modifiés | téléchargement |
| `processed/` | tables du modèle en étoile (`dim_*.csv`, `fact_sales.csv`) | `python -m src.etl` |
