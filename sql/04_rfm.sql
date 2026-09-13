USE FashionEcommerce;
GO

DROP TABLE IF EXISTS warehouse.Customer_RFM;
GO

WITH RFM_Base AS (
    SELECT
        f.Customer_Key,
        MAX(d.[Date]) AS Last_Purchase_Date,
        COUNT(DISTINCT f.Invoice_ID) AS Frequency,
        SUM(f.Line_Total_USD) AS Monetary_USD
    FROM warehouse.vw_Fact_Sales_USD f
    JOIN warehouse.Dim_Date d ON f.Date_Key = d.Date_Key
    WHERE f.Transaction_Type = 'Sale'
    GROUP BY f.Customer_Key
),
Max_Date AS (
    SELECT MAX([Date]) AS Ref_Date FROM warehouse.Dim_Date d JOIN warehouse.Fact_Sales f ON d.Date_Key = f.Date_Key
)
SELECT
    r.Customer_Key,
    DATEDIFF(DAY, r.Last_Purchase_Date, m.Ref_Date) AS Recency_Days,
    r.Frequency,
    r.Monetary_USD
INTO warehouse.Customer_RFM
FROM RFM_Base r
CROSS JOIN Max_Date m;
GO

CREATE INDEX IX_Customer_RFM_Key ON warehouse.Customer_RFM(Customer_Key);
GO

SELECT COUNT(*) AS Nb_Customers, AVG(Recency_Days) AS Avg_Recency, AVG(Frequency*1.0) AS Avg_Frequency, AVG(Monetary_USD) AS Avg_Monetary
FROM warehouse.Customer_RFM;
GO