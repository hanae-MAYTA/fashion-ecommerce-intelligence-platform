USE FashionEcommerce;
GO

CREATE TABLE warehouse.Dim_Date (
    Date_Key        INT             PRIMARY KEY,
    [Date]          DATE            NOT NULL,
    [Year]          SMALLINT        NOT NULL,
    Quarter         TINYINT         NOT NULL,
    [Month]         TINYINT         NOT NULL,
    Month_Name      VARCHAR(10)     NOT NULL,
    [Day]           TINYINT         NOT NULL,
    Day_Of_Week     TINYINT         NOT NULL,
    Day_Name        VARCHAR(10)     NOT NULL,
    Is_Weekend      BIT             NOT NULL,
    Week_Of_Year    TINYINT         NOT NULL
);
GO

CREATE TABLE warehouse.Dim_Customer (
    Customer_Key    INT             PRIMARY KEY,
    Customer_Name   NVARCHAR(150),
    Email           NVARCHAR(150),
    Telephone       NVARCHAR(50),
    City            NVARCHAR(100),
    Country         NVARCHAR(100),
    Gender          CHAR(1),
    Date_Of_Birth   DATE,
    Job_Title       NVARCHAR(150),
    Age             SMALLINT
);
GO

CREATE TABLE warehouse.Dim_Product (
    Product_Key      INT            PRIMARY KEY,
    Category         NVARCHAR(50),
    Sub_Category     NVARCHAR(100),
    Description      NVARCHAR(300),
    Color            NVARCHAR(50),
    Available_Sizes  NVARCHAR(50),
    Production_Cost  DECIMAL(10,2)
);
GO

CREATE TABLE warehouse.Dim_Store (
    Store_Key             INT        PRIMARY KEY,
    Store_Name            NVARCHAR(150),
    City                  NVARCHAR(100),
    Country               NVARCHAR(100),
    ZIP_Code              VARCHAR(20),
    Latitude               DECIMAL(9,6),
    Longitude              DECIMAL(9,6),
    Number_Of_Employees    SMALLINT
);
GO

CREATE TABLE warehouse.Dim_Employee (
    Employee_Key    INT             PRIMARY KEY,
    Store_Key       INT             NOT NULL REFERENCES warehouse.Dim_Store(Store_Key),
    Employee_Name   NVARCHAR(150),
    Position        NVARCHAR(100)
);
GO

CREATE TABLE warehouse.Dim_Discount (
    Discount_Key    INT             PRIMARY KEY,
    Category        NVARCHAR(50),
    Sub_Category    NVARCHAR(100),
    Start           DATE,
    [End]           DATE,
    Discount_Rate   DECIMAL(5,2),
    Description     NVARCHAR(300)
);
GO

CREATE TABLE warehouse.Fact_Sales (
    Invoice_ID        VARCHAR(30)    NOT NULL,
    Line               SMALLINT      NOT NULL,
    Date_Key            INT          NOT NULL REFERENCES warehouse.Dim_Date(Date_Key),
    Customer_Key        INT          NOT NULL REFERENCES warehouse.Dim_Customer(Customer_Key),
    Product_Key         INT          NOT NULL REFERENCES warehouse.Dim_Product(Product_Key),
    Store_Key            INT         NOT NULL REFERENCES warehouse.Dim_Store(Store_Key),
    Employee_Key          INT        NOT NULL REFERENCES warehouse.Dim_Employee(Employee_Key),
    SKU                 VARCHAR(50),
    Size                 VARCHAR(20),
    Color                NVARCHAR(50),
    Quantity              SMALLINT   NOT NULL,
    Unit_Price            DECIMAL(10,2) NOT NULL,
    Discount              DECIMAL(5,2)  NOT NULL,
    Line_Total            DECIMAL(12,2) NOT NULL,
    Invoice_Total          DECIMAL(12,2) NOT NULL,
    Return_Ratio            DECIMAL(6,3) NOT NULL,
    Transaction_Type        VARCHAR(20)  NOT NULL,
    Payment_Method           VARCHAR(30),
    Currency                  CHAR(3),
    CONSTRAINT PK_Fact_Sales PRIMARY KEY (Invoice_ID, Line)
);
GO

CREATE INDEX IX_Fact_Sales_Date     ON warehouse.Fact_Sales(Date_Key);
CREATE INDEX IX_Fact_Sales_Customer ON warehouse.Fact_Sales(Customer_Key);
CREATE INDEX IX_Fact_Sales_Product  ON warehouse.Fact_Sales(Product_Key);
CREATE INDEX IX_Fact_Sales_Store    ON warehouse.Fact_Sales(Store_Key);
GO