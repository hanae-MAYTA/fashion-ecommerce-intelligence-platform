/* ============================================================================
   06 — Features de churn à une date d'observation (« snapshot »)

   Features : calculées uniquement sur l'historique <= @Snapshot_Date (pas de fuite).
   Label    : Churned = 1 si le client n'achète pas dans les @Window_Days jours
              suivant le snapshot ; NULL si la fenêtre dépasse la fin des données
              (snapshot de scoring).

   Une fonction plutôt qu'une table figée : le même code produit le jeu
   d'entraînement, le jeu de test (validation temporelle) et le jeu à scorer.
   Exemple :
       SELECT * FROM warehouse.fn_Churn_Features('2024-12-01', 90);
   ============================================================================ */

USE FashionEcommerce;
GO

CREATE OR ALTER FUNCTION warehouse.fn_Churn_Features (
    @Snapshot_Date DATE,
    @Window_Days   INT
)
RETURNS TABLE
AS
RETURN
WITH Sales AS (
    SELECT
        f.Customer_Key,
        f.Invoice_ID,
        f.Quantity,
        f.Discount,
        f.Line_Total_USD,
        p.Category,
        d.[Date] AS Sale_Date
    FROM warehouse.vw_Fact_Sales_USD AS f
    JOIN warehouse.Dim_Date    AS d ON d.Date_Key    = f.Date_Key
    JOIN warehouse.Dim_Product AS p ON p.Product_Key = f.Product_Key
    WHERE f.Transaction_Type = 'Sale'
),
Data_End AS (
    SELECT MAX(Sale_Date) AS Last_Date FROM Sales
),
History AS (
    SELECT
        Customer_Key,
        MIN(Sale_Date)                                     AS First_Purchase_Date,
        MAX(Sale_Date)                                     AS Last_Purchase_Date,
        COUNT(DISTINCT Invoice_ID)                         AS Frequency,
        SUM(Line_Total_USD)                                AS Monetary_USD,
        AVG(Line_Total_USD)                                AS Avg_Line_Value_USD,
        AVG(CASE WHEN Discount > 0 THEN 1.0 ELSE 0.0 END)  AS Discount_Usage_Rate,
        COUNT(DISTINCT Category)                           AS Distinct_Categories,
        SUM(Quantity)                                      AS Total_Units,
        COUNT(DISTINCT CASE WHEN Sale_Date > DATEADD(DAY, -90, @Snapshot_Date)
                            THEN Invoice_ID END)           AS Orders_Last_90d,
        COUNT(DISTINCT CASE WHEN Sale_Date >  DATEADD(DAY, -180, @Snapshot_Date)
                             AND Sale_Date <= DATEADD(DAY, -90, @Snapshot_Date)
                            THEN Invoice_ID END)           AS Orders_Prior_90d
    FROM Sales
    WHERE Sale_Date <= @Snapshot_Date
    GROUP BY Customer_Key
),
Future_Buyers AS (
    SELECT DISTINCT Customer_Key
    FROM Sales
    WHERE Sale_Date >  @Snapshot_Date
      AND Sale_Date <= DATEADD(DAY, @Window_Days, @Snapshot_Date)
)
SELECT
    h.Customer_Key,
    @Snapshot_Date                                          AS Snapshot_Date,
    DATEDIFF(DAY, h.Last_Purchase_Date, @Snapshot_Date)     AS Recency_Days,
    DATEDIFF(DAY, h.First_Purchase_Date, @Snapshot_Date)    AS Tenure_Days,
    h.Frequency,
    h.Monetary_USD,
    h.Avg_Line_Value_USD,
    h.Discount_Usage_Rate,
    h.Distinct_Categories,
    h.Total_Units,
    h.Orders_Last_90d,
    h.Orders_Prior_90d,
    h.Orders_Last_90d - h.Orders_Prior_90d                  AS Momentum,
    CASE
        WHEN DATEADD(DAY, @Window_Days, @Snapshot_Date) > de.Last_Date THEN NULL
        WHEN fb.Customer_Key IS NULL THEN 1
        ELSE 0
    END                                                     AS Churned
FROM History AS h
CROSS JOIN Data_End AS de
LEFT JOIN Future_Buyers AS fb ON fb.Customer_Key = h.Customer_Key;
GO

-- Contrôle : taux de churn par snapshot (ni 0 %, ni 100 %)
SELECT
    Snapshot_Date,
    COUNT(*)                                AS Nb_Customers,
    ROUND(100.0 * AVG(Churned * 1.0), 2)    AS Churn_Rate_Pct
FROM warehouse.fn_Churn_Features('2024-12-01', 90)
GROUP BY Snapshot_Date;
GO
