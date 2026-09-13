USE FashionEcommerce;
GO

DROP TABLE IF EXISTS warehouse.Churn_Features;
GO

DECLARE @CutoffDate DATE = '2024-12-01';
DECLARE @ChurnWindowEnd DATE = DATEADD(DAY, 90, @CutoffDate);  -- 2025-03-01

WITH Pre_Cutoff AS (
    -- Historique du client AVANT la coupure (= nos features)
    SELECT
        f.Customer_Key,
        MIN(d.[Date]) AS First_Purchase_Date,
        MAX(d.[Date]) AS Last_Purchase_Date,
        COUNT(DISTINCT f.Invoice_ID) AS Frequency,
        SUM(f.Line_Total_USD) AS Monetary_USD,
        AVG(f.Line_Total_USD) AS Avg_Line_Value_USD,
        SUM(CASE WHEN f.Discount > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS Discount_Usage_Rate,
        COUNT(DISTINCT p.Category) AS Distinct_Categories,
        SUM(f.Quantity) AS Total_Units
    FROM warehouse.vw_Fact_Sales_USD f
    JOIN warehouse.Dim_Date d ON f.Date_Key = d.Date_Key
    JOIN warehouse.Dim_Product p ON f.Product_Key = p.Product_Key
    WHERE f.Transaction_Type = 'Sale'
        AND d.[Date] <= @CutoffDate
    GROUP BY f.Customer_Key
),
Future_Activity AS (
    -- A-t-il acheté dans les 90 jours APRES la coupure ? (= notre label)
    SELECT DISTINCT f.Customer_Key
    FROM warehouse.vw_Fact_Sales_USD f
    JOIN warehouse.Dim_Date d ON f.Date_Key = d.Date_Key
    WHERE f.Transaction_Type = 'Sale'
        AND d.[Date] > @CutoffDate
        AND d.[Date] <= @ChurnWindowEnd
)
SELECT
    p.Customer_Key,
    DATEDIFF(DAY, p.Last_Purchase_Date, @CutoffDate) AS Recency_Days,
    DATEDIFF(DAY, p.First_Purchase_Date, @CutoffDate) AS Tenure_Days,
    p.Frequency,
    p.Monetary_USD,
    p.Avg_Line_Value_USD,
    p.Discount_Usage_Rate,
    p.Distinct_Categories,
    p.Total_Units,
    CASE WHEN fa.Customer_Key IS NULL THEN 1 ELSE 0 END AS Churned
INTO warehouse.Churn_Features
FROM Pre_Cutoff p
LEFT JOIN Future_Activity fa ON p.Customer_Key = fa.Customer_Key;
GO

CREATE INDEX IX_Churn_Features_Key ON warehouse.Churn_Features(Customer_Key);
GO

-- Vérification : taux de churn global (doit être raisonnable, pas 0% ni 100%)
SELECT
    COUNT(*) AS Nb_Customers,
    SUM(Churned) AS Nb_Churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 2) AS Churn_Rate_Pct
FROM warehouse.Churn_Features;
GO