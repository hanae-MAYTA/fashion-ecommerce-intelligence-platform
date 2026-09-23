/* ============================================================================
   04 — Requêtes d'analyse métier (tous les montants en USD)
   CA brut = ventes ; CA net = ventes - retours (les retours ont un montant négatif).
   Marge : hypothèse que Production_Cost est exprimé en USD.
   ============================================================================ */

USE FashionEcommerce;
GO

-- ── 1. KPI globaux ───────────────────────────────────────────────────────────

SELECT
    SUM(CASE WHEN Transaction_Type = 'Sale'   THEN Line_Total_USD ELSE 0 END)      AS Gross_Revenue_USD,
    -SUM(CASE WHEN Transaction_Type = 'Return' THEN Line_Total_USD ELSE 0 END)     AS Returns_USD,
    SUM(Line_Total_USD)                                                            AS Net_Revenue_USD,
    COUNT(DISTINCT CASE WHEN Transaction_Type = 'Sale' THEN Invoice_ID END)        AS Nb_Orders,
    SUM(CASE WHEN Transaction_Type = 'Sale' THEN Line_Total_USD ELSE 0 END)
        / COUNT(DISTINCT CASE WHEN Transaction_Type = 'Sale' THEN Invoice_ID END)  AS Avg_Order_Value_USD,
    -SUM(CASE WHEN Transaction_Type = 'Return' THEN Line_Total_USD ELSE 0 END)
        / NULLIF(SUM(CASE WHEN Transaction_Type = 'Sale' THEN Line_Total_USD ELSE 0 END), 0) AS Return_Rate
FROM warehouse.vw_Fact_Sales_USD;
GO

-- ── 2. Évolution mensuelle du CA net et croissance vs mois précédent ────────

WITH Monthly AS (
    SELECT d.[Year], d.[Month], SUM(f.Line_Total_USD) AS Net_Revenue_USD
    FROM warehouse.vw_Fact_Sales_USD AS f
    JOIN warehouse.Dim_Date AS d ON d.Date_Key = f.Date_Key
    GROUP BY d.[Year], d.[Month]
)
SELECT
    [Year],
    [Month],
    Net_Revenue_USD,
    LAG(Net_Revenue_USD) OVER (ORDER BY [Year], [Month]) AS Prev_Month_USD,
    ROUND(100.0 * (Net_Revenue_USD - LAG(Net_Revenue_USD) OVER (ORDER BY [Year], [Month]))
          / NULLIF(LAG(Net_Revenue_USD) OVER (ORDER BY [Year], [Month]), 0), 2) AS MoM_Growth_Pct
FROM Monthly
ORDER BY [Year], [Month];
GO

-- ── 3. Rentabilité par catégorie (ventes uniquement) ────────────────────────

WITH Category_Sales AS (
    SELECT
        p.Category,
        SUM(f.Line_Total_USD)                AS Revenue_USD,
        SUM(f.Quantity * p.Production_Cost)  AS Cost_USD
    FROM warehouse.vw_Fact_Sales_USD AS f
    JOIN warehouse.Dim_Product AS p ON p.Product_Key = f.Product_Key
    WHERE f.Transaction_Type = 'Sale'
    GROUP BY p.Category
)
SELECT
    Category,
    Revenue_USD,
    Cost_USD,
    Revenue_USD - Cost_USD                                       AS Gross_Profit_USD,
    ROUND(100.0 * (Revenue_USD - Cost_USD) / NULLIF(Revenue_USD, 0), 2) AS Margin_Pct
FROM Category_Sales
ORDER BY Gross_Profit_USD DESC;
GO

-- ── 4. Top 10 produits par CA ───────────────────────────────────────────────

SELECT TOP (10)
    p.Product_Key, p.Category, p.Sub_Category, p.Description,
    SUM(f.Line_Total_USD) AS Revenue_USD,
    SUM(f.Quantity)       AS Units_Sold
FROM warehouse.vw_Fact_Sales_USD AS f
JOIN warehouse.Dim_Product AS p ON p.Product_Key = f.Product_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY p.Product_Key, p.Category, p.Sub_Category, p.Description
ORDER BY Revenue_USD DESC;
GO

-- ── 5. Produits jamais ou peu vendus (candidats au déréférencement) ─────────

SELECT TOP (20)
    p.Product_Key, p.Category, p.Sub_Category, p.Description,
    COALESCE(SUM(f.Line_Total_USD), 0) AS Revenue_USD,
    COALESCE(SUM(f.Quantity), 0)       AS Units_Sold
FROM warehouse.Dim_Product AS p
LEFT JOIN warehouse.vw_Fact_Sales_USD AS f
    ON f.Product_Key = p.Product_Key
   AND f.Transaction_Type = 'Sale'
GROUP BY p.Product_Key, p.Category, p.Sub_Category, p.Description
ORDER BY Revenue_USD ASC;
GO

-- ── 6. Taux de retour par sous-catégorie (en valeur) ────────────────────────

SELECT
    p.Category,
    p.Sub_Category,
    SUM(CASE WHEN f.Transaction_Type = 'Sale' THEN f.Line_Total_USD ELSE 0 END) AS Gross_Revenue_USD,
    ROUND(100.0 * -SUM(CASE WHEN f.Transaction_Type = 'Return' THEN f.Line_Total_USD ELSE 0 END)
          / NULLIF(SUM(CASE WHEN f.Transaction_Type = 'Sale' THEN f.Line_Total_USD ELSE 0 END), 0), 2) AS Return_Rate_Pct
FROM warehouse.vw_Fact_Sales_USD AS f
JOIN warehouse.Dim_Product AS p ON p.Product_Key = f.Product_Key
GROUP BY p.Category, p.Sub_Category
ORDER BY Return_Rate_Pct DESC;
GO

-- ── 7. Clients actifs sur les 90 derniers jours ─────────────────────────────

DECLARE @Last_Date_Key INT = (SELECT MAX(Date_Key) FROM warehouse.Fact_Sales);
DECLARE @Start_Date_Key INT = (
    SELECT Date_Key FROM warehouse.Dim_Date
    WHERE [Date] = DATEADD(DAY, -90, (SELECT [Date] FROM warehouse.Dim_Date WHERE Date_Key = @Last_Date_Key))
);

SELECT COUNT(DISTINCT Customer_Key) AS Active_Customers_Last_90d
FROM warehouse.Fact_Sales
WHERE Transaction_Type = 'Sale'
  AND Date_Key > @Start_Date_Key;
GO

-- ── 8. Performance par pays et par magasin ──────────────────────────────────

SELECT
    s.Country,
    s.Store_Name,
    SUM(f.Line_Total_USD)                                              AS Revenue_USD,
    SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost)        AS Gross_Profit_USD,
    ROUND(100.0 * (SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost))
          / NULLIF(SUM(f.Line_Total_USD), 0), 2)                       AS Margin_Pct,
    COUNT(DISTINCT f.Invoice_ID)                                       AS Nb_Orders
FROM warehouse.vw_Fact_Sales_USD AS f
JOIN warehouse.Dim_Store   AS s ON s.Store_Key   = f.Store_Key
JOIN warehouse.Dim_Product AS p ON p.Product_Key = f.Product_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY s.Country, s.Store_Name
ORDER BY Revenue_USD DESC;
GO
