/* ============================================================================
   02 — Tables du modèle en étoile (script rejouable : les tables sont recréées)
   ============================================================================ */

USE FashionEcommerce;
GO

DROP VIEW  IF EXISTS warehouse.vw_Fact_Sales_USD;
DROP TABLE IF EXISTS warehouse.Fact_Sales;
DROP TABLE IF EXISTS staging.Fact_Sales;
DROP TABLE IF EXISTS warehouse.Dim_Employee;
DROP TABLE IF EXISTS warehouse.Dim_Store;
DROP TABLE IF EXISTS warehouse.Dim_Customer;
DROP TABLE IF EXISTS warehouse.Dim_Product;
DROP TABLE IF EXISTS warehouse.Dim_Date;
DROP TABLE IF EXISTS warehouse.Dim_Discount;
DROP TABLE IF EXISTS warehouse.Dim_Currency;
GO

-- ── Dimensions ───────────────────────────────────────────────────────────────

CREATE TABLE warehouse.Dim_Date (
    Date_Key        INT            NOT NULL PRIMARY KEY,   -- AAAAMMJJ
    [Date]          DATE           NOT NULL,
    [Year]          SMALLINT       NOT NULL,
    Quarter         TINYINT        NOT NULL,
    [Month]         TINYINT        NOT NULL,
    Month_Name      VARCHAR(10)    NOT NULL,
    [Day]           TINYINT        NOT NULL,
    Day_Of_Week     TINYINT        NOT NULL,               -- 1 = lundi
    Day_Name        VARCHAR(10)    NOT NULL,
    Is_Weekend      BIT            NOT NULL,
    Week_Of_Year    TINYINT        NOT NULL
);

CREATE TABLE warehouse.Dim_Customer (
    Customer_Key    INT            NOT NULL PRIMARY KEY,
    Customer_Name   NVARCHAR(150),
    Email           NVARCHAR(150),
    Telephone       NVARCHAR(50),
    City            NVARCHAR(100),
    Country         NVARCHAR(100),
    Gender          CHAR(1),
    Date_Of_Birth   DATE,
    Job_Title       NVARCHAR(150),
    Age             SMALLINT                               -- à la dernière date du dataset
);

CREATE TABLE warehouse.Dim_Product (
    Product_Key      INT           NOT NULL PRIMARY KEY,
    Category         NVARCHAR(50),
    Sub_Category     NVARCHAR(100),
    Description      NVARCHAR(300),
    Color            NVARCHAR(50),
    Available_Sizes  NVARCHAR(50),
    Production_Cost  DECIMAL(10,2)                         -- hypothèse : exprimé en USD
);

CREATE TABLE warehouse.Dim_Store (
    Store_Key            INT           NOT NULL PRIMARY KEY,
    Store_Name           NVARCHAR(150),
    City                 NVARCHAR(100),
    Country              NVARCHAR(100),
    ZIP_Code             VARCHAR(20),
    Latitude             DECIMAL(9,6),
    Longitude            DECIMAL(9,6),
    Number_Of_Employees  SMALLINT
);

CREATE TABLE warehouse.Dim_Employee (
    Employee_Key    INT            NOT NULL PRIMARY KEY,
    Store_Key       INT            NOT NULL REFERENCES warehouse.Dim_Store (Store_Key),
    Employee_Name   NVARCHAR(150),
    Position        NVARCHAR(100)
);

-- Table de référence autonome (périodes promotionnelles) : pas de FK depuis Fact_Sales,
-- le taux de remise effectivement appliqué est porté par chaque ligne de vente.
CREATE TABLE warehouse.Dim_Discount (
    Discount_Key    INT            NOT NULL PRIMARY KEY,
    Category        NVARCHAR(50)   NOT NULL,               -- 'All' = promotion globale
    Sub_Category    NVARCHAR(100)  NOT NULL,
    Start           DATE           NOT NULL,
    [End]           DATE           NOT NULL,
    Discount_Rate   DECIMAL(5,2)   NOT NULL,
    Description     NVARCHAR(300)
);

-- Taux de change fixes utilisés pour ramener toutes les ventes en USD.
-- HYPOTHÈSE : taux moyens de marché 2023-2024 (le dataset ne fournit pas de taux).
-- Les ratios de prix entre pays ne sont PAS des taux de change (grilles tarifaires locales).
CREATE TABLE warehouse.Dim_Currency (
    Currency        CHAR(3)        NOT NULL PRIMARY KEY,
    Rate_To_USD     DECIMAL(10,6)  NOT NULL
);

INSERT INTO warehouse.Dim_Currency (Currency, Rate_To_USD) VALUES
    ('USD', 1.000000),
    ('EUR', 1.080000),
    ('GBP', 1.270000),
    ('CNY', 0.139100);

-- ── Faits ────────────────────────────────────────────────────────────────────

-- Staging : mêmes colonnes, dans le même ordre, que data/processed/fact_sales.csv.
CREATE TABLE staging.Fact_Sales (
    Invoice_ID        VARCHAR(30)    NOT NULL,
    Line              SMALLINT       NOT NULL,
    Date_Key          INT            NOT NULL,
    Customer_Key      INT            NOT NULL,
    Product_Key       INT            NOT NULL,
    Store_Key         INT            NOT NULL,
    Employee_Key      INT            NOT NULL,
    SKU               VARCHAR(50),
    Size              VARCHAR(20),
    Color             NVARCHAR(50),
    Quantity          SMALLINT       NOT NULL,
    Unit_Price        DECIMAL(10,2)  NOT NULL,
    Discount          DECIMAL(5,2)   NOT NULL,
    Line_Total        DECIMAL(12,2)  NOT NULL,
    Invoice_Total     DECIMAL(12,2)  NOT NULL,
    Transaction_Type  VARCHAR(20)    NOT NULL,
    Payment_Method    VARCHAR(30),
    Currency          CHAR(3)        NOT NULL
);

-- Grain : une ligne de facture. Clé technique Sale_Key car l'unicité de la clé
-- naturelle (Invoice_ID, Line) n'est pas garantie par la source (contrôlée dans l'ETL).
CREATE TABLE warehouse.Fact_Sales (
    Sale_Key          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Fact_Sales PRIMARY KEY,
    Invoice_ID        VARCHAR(30)    NOT NULL,
    Line              SMALLINT       NOT NULL,
    Date_Key          INT            NOT NULL REFERENCES warehouse.Dim_Date (Date_Key),
    Customer_Key      INT            NOT NULL REFERENCES warehouse.Dim_Customer (Customer_Key),
    Product_Key       INT            NOT NULL REFERENCES warehouse.Dim_Product (Product_Key),
    Store_Key         INT            NOT NULL REFERENCES warehouse.Dim_Store (Store_Key),
    Employee_Key      INT            NOT NULL REFERENCES warehouse.Dim_Employee (Employee_Key),
    SKU               VARCHAR(50),
    Size              VARCHAR(20),
    Color             NVARCHAR(50),
    Quantity          SMALLINT       NOT NULL CHECK (Quantity > 0),
    Unit_Price        DECIMAL(10,2)  NOT NULL CHECK (Unit_Price > 0),
    Discount          DECIMAL(5,2)   NOT NULL CHECK (Discount BETWEEN 0 AND 1),
    Line_Total        DECIMAL(12,2)  NOT NULL,             -- négatif pour les retours
    Invoice_Total     DECIMAL(12,2)  NOT NULL,
    Transaction_Type  VARCHAR(20)    NOT NULL CHECK (Transaction_Type IN ('Sale', 'Return')),
    Payment_Method    VARCHAR(30),
    Currency          CHAR(3)        NOT NULL REFERENCES warehouse.Dim_Currency (Currency)
);
GO

CREATE INDEX IX_Fact_Sales_Invoice  ON warehouse.Fact_Sales (Invoice_ID, Line);
CREATE INDEX IX_Fact_Sales_Date     ON warehouse.Fact_Sales (Date_Key);
CREATE INDEX IX_Fact_Sales_Customer ON warehouse.Fact_Sales (Customer_Key) INCLUDE (Date_Key, Transaction_Type);
CREATE INDEX IX_Fact_Sales_Product  ON warehouse.Fact_Sales (Product_Key);
CREATE INDEX IX_Fact_Sales_Store    ON warehouse.Fact_Sales (Store_Key);
GO
