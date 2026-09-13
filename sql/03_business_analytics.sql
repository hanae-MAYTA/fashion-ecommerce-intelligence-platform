USE FashionEcommerce;
GO

-- ============================================================
-- 1. SALES — vue d'ensemble
-- ============================================================

SELECT
    SUM(Line_Total_USD) AS Revenue_Net_USD,
    SUM(CASE WHEN Transaction_Type = 'Sale' THEN Line_Total_USD ELSE 0 END) AS Revenue_Gross_USD,
    SUM(CASE WHEN Transaction_Type = 'Return' THEN Line_Total_USD ELSE 0 END) AS Returns_Value_USD,
    COUNT(DISTINCT Invoice_ID) AS Nb_Invoices,
    SUM(Line_Total_USD) / COUNT(DISTINCT Invoice_ID) AS Avg_Basket_Value_USD
FROM warehouse.vw_Fact_Sales_USD;
GO

-- Marge globale
SELECT
    SUM(f.Line_Total_USD) AS Revenue_USD,
    SUM(f.Quantity * p.Production_Cost) AS Total_Cost_USD,
    SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost) AS Gross_Profit_USD,
    ROUND(100.0 * (SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost)) / NULLIF(SUM(f.Line_Total_USD), 0), 2) AS Margin_Pct
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Product p ON f.Product_Key = p.Product_Key
WHERE f.Transaction_Type = 'Sale';
GO

-- Croissance mensuelle du CA (USD)
SELECT
    d.[Year], d.[Month], d.Month_Name,
    SUM(f.Line_Total_USD) AS Monthly_Revenue_USD,
    LAG(SUM(f.Line_Total_USD)) OVER (ORDER BY d.[Year], d.[Month]) AS Prev_Month_Revenue_USD,
    ROUND(
        100.0 * (SUM(f.Line_Total_USD) - LAG(SUM(f.Line_Total_USD)) OVER (ORDER BY d.[Year], d.[Month]))
        / NULLIF(LAG(SUM(f.Line_Total_USD)) OVER (ORDER BY d.[Year], d.[Month]), 0),
        2
    ) AS Growth_Pct
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Date d ON f.Date_Key = d.Date_Key
GROUP BY d.[Year], d.[Month], d.Month_Name
ORDER BY d.[Year], d.[Month];
GO

-- ============================================================
-- 2. PRODUCT (comparable en USD maintenant)
-- ============================================================

SELECT TOP 10
    p.Product_Key, p.Category, p.Sub_Category, p.Description,
    SUM(f.Line_Total_USD) AS Revenue_USD,
    SUM(f.Quantity) AS Units_Sold
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Product p ON f.Product_Key = p.Product_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY p.Product_Key, p.Category, p.Sub_Category, p.Description
ORDER BY Revenue_USD DESC;
GO

SELECT
    p.Category,
    SUM(f.Line_Total_USD) AS Revenue_USD,
    SUM(f.Quantity * p.Production_Cost) AS Cost_USD,
    SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost) AS Profit_USD,
    ROUND(100.0 * (SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost)) / NULLIF(SUM(f.Line_Total_USD),0), 2) AS Margin_Pct
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Product p ON f.Product_Key = p.Product_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY p.Category
ORDER BY Profit_USD DESC;
GO

SELECT TOP 20
    p.Product_Key, p.Category, p.Sub_Category, p.Description,
    COALESCE(SUM(f.Line_Total_USD), 0) AS Revenue_USD,
    COALESCE(SUM(f.Quantity), 0) AS Units_Sold
FROM warehouse.Dim_Product p
LEFT JOIN warehouse.vw_Fact_Sales_USD f
    ON p.Product_Key = f.Product_Key AND f.Transaction_Type = 'Sale'
GROUP BY p.Product_Key, p.Category, p.Sub_Category, p.Description
ORDER BY Revenue_USD ASC;
GO

-- ============================================================
-- 3. CUSTOMER
-- ============================================================

SELECT TOP 20
    c.Customer_Key, c.Customer_Name, c.Country,
    COUNT(DISTINCT f.Invoice_ID) AS Nb_Orders,
    SUM(f.Line_Total_USD) AS Total_Spent_USD
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Customer c ON f.Customer_Key = c.Customer_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY c.Customer_Key, c.Customer_Name, c.Country
ORDER BY Total_Spent_USD DESC;
GO

DECLARE @MaxDate DATE = (SELECT MAX([Date]) FROM warehouse.Dim_Date d JOIN warehouse.Fact_Sales f ON d.Date_Key = f.Date_Key);

SELECT COUNT(DISTINCT f.Customer_Key) AS Active_Customers_Last_90d
FROM warehouse.Fact_Sales f
JOIN warehouse.Dim_Date d ON f.Date_Key = d.Date_Key
WHERE d.[Date] >= DATEADD(DAY, -90, @MaxDate)
    AND f.Transaction_Type = 'Sale';
GO

-- ============================================================
-- 4. STORE / GEOGRAPHY (comparable en USD)
-- ============================================================

SELECT
    s.Store_Key, s.Store_Name, s.City, s.Country,
    SUM(f.Line_Total_USD) AS Revenue_USD,
    SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost) AS Profit_USD,
    ROUND(100.0 * (SUM(f.Line_Total_USD) - SUM(f.Quantity * p.Production_Cost)) / NULLIF(SUM(f.Line_Total_USD),0), 2) AS Margin_Pct,
    COUNT(DISTINCT f.Invoice_ID) AS Nb_Orders
FROM warehouse.vw_Fact_Sales_USD f
JOIN warehouse.Dim_Store s ON f.Store_Key = s.Store_Key
JOIN warehouse.Dim_Product p ON f.Product_Key = p.Product_Key
WHERE f.Transaction_Type = 'Sale'
GROUP BY s.Store_Key, s.Store_Name, s.City, s.Country
ORDER BY Profit_USD DESC;
GO