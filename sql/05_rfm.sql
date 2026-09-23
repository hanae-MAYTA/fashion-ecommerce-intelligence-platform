/* ============================================================================
   05 — Base RFM (Récence, Fréquence, Montant) par client
   Date de référence : dernière date de vente du dataset.
   Montant = CA brut des ventes en USD (retours non déduits).
   Le scoring et la segmentation sont faits dans notebooks/04_rfm_segmentation.ipynb.
   ============================================================================ */

USE FashionEcommerce;
GO

DROP TABLE IF EXISTS warehouse.Customer_RFM;
GO

WITH Sales AS (
    SELECT f.Customer_Key, f.Invoice_ID, f.Line_Total_USD, d.[Date] AS Sale_Date
    FROM warehouse.vw_Fact_Sales_USD AS f
    JOIN warehouse.Dim_Date AS d ON d.Date_Key = f.Date_Key
    WHERE f.Transaction_Type = 'Sale'
),
Reference AS (
    SELECT MAX(Sale_Date) AS Reference_Date FROM Sales
)
SELECT
    s.Customer_Key,
    DATEDIFF(DAY, MAX(s.Sale_Date), r.Reference_Date) AS Recency_Days,
    COUNT(DISTINCT s.Invoice_ID)                      AS Frequency,
    SUM(s.Line_Total_USD)                             AS Monetary_USD
INTO warehouse.Customer_RFM
FROM Sales AS s
CROSS JOIN Reference AS r
GROUP BY s.Customer_Key, r.Reference_Date;
GO

ALTER TABLE warehouse.Customer_RFM
    ADD CONSTRAINT PK_Customer_RFM PRIMARY KEY (Customer_Key);
GO

-- Contrôle
SELECT
    COUNT(*)                AS Nb_Customers,
    AVG(Recency_Days * 1.0) AS Avg_Recency_Days,
    AVG(Frequency * 1.0)    AS Avg_Frequency,
    AVG(Monetary_USD)       AS Avg_Monetary_USD
FROM warehouse.Customer_RFM;
GO
