/* ============================================================================
   03 — Vue de conversion en USD
   Source unique de toutes les analyses (EDA, RFM, churn, prévisions, Power BI) :
   des montants de devises différentes ne sont jamais additionnés directement.
   ============================================================================ */

USE FashionEcommerce;
GO

CREATE OR ALTER VIEW warehouse.vw_Fact_Sales_USD
AS
SELECT
    f.Sale_Key,
    f.Invoice_ID,
    f.Line,
    f.Date_Key,
    f.Customer_Key,
    f.Product_Key,
    f.Store_Key,
    f.Employee_Key,
    f.Size,
    f.Color,
    f.Quantity,
    f.Discount,
    f.Transaction_Type,
    f.Payment_Method,
    f.Currency,
    f.Unit_Price    * c.Rate_To_USD AS Unit_Price_USD,
    f.Line_Total    * c.Rate_To_USD AS Line_Total_USD,
    f.Invoice_Total * c.Rate_To_USD AS Invoice_Total_USD
FROM warehouse.Fact_Sales AS f
JOIN warehouse.Dim_Currency AS c
    ON c.Currency = f.Currency;
GO
