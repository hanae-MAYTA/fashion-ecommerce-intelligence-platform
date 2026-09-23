/* ============================================================================
   01 — Base de données et schémas
   staging   : zone d'atterrissage du BULK INSERT
   warehouse : modèle en étoile + tables analytiques (RFM, churn, prévisions)
   ============================================================================ */

IF DB_ID('FashionEcommerce') IS NULL
    CREATE DATABASE FashionEcommerce;
GO

USE FashionEcommerce;
GO

IF SCHEMA_ID('staging') IS NULL
    EXEC('CREATE SCHEMA staging');
GO
IF SCHEMA_ID('warehouse') IS NULL
    EXEC('CREATE SCHEMA warehouse');
GO
