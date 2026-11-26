/* =====================================================================
   קובץ 4: כל ה-Views שהדשבורד של השיווק צריך
   ---------------------------------------------------------------------
   מריצים פעם אחת: פותחים ב-SSMS ולוחצים F5 (בלי לסמן כלום).
   בסוף מופיעה טבלה עם 5 שורות - שם כל View וכמה שורות יש בו.
   ===================================================================== */
USE AirbnbPortfolio;
GO

/* ---------- 1. כרטיס KPI + טרימאפ: הזדמנות מאורחים (תיקון 3) ---------- */
CREATE OR ALTER VIEW V_Guest_Revenue_Opportunity AS
WITH Benchmarks AS (
    SELECT
        Conversion_Rate =
            CAST((SELECT COUNT(*)
                  FROM ORDERS AS O
                  JOIN SEARCHES AS S ON O.IP_Address = S.IP_Address AND O.SearchDT = S.SearchDT
                  WHERE S.Customer IS NOT NULL) AS DECIMAL(10,4))
            / (SELECT COUNT(*) FROM SEARCHES WHERE Customer IS NOT NULL),
        Avg_Group_Size =
            (SELECT AVG(CAST(ParticipantsNumber AS DECIMAL(10,2))) FROM ORDERS)
)
SELECT
    E.Name AS Experience_Name,
    E.Category,
    E.Price,
    Guest_Views = COUNT(*),
    Estimated_Opportunity = CAST(COUNT(*) * E.Price
                                 * MAX(B.Avg_Group_Size)
                                 * MAX(B.Conversion_Rate) AS DECIMAL(12,2))
FROM SEARCHES AS S
JOIN RETRIEVES AS R   ON S.IP_Address = R.IP_Address AND S.SearchDT = R.SearchDT
JOIN EXPERIENCES AS E ON R.Experience = E.Name
CROSS JOIN Benchmarks AS B
WHERE S.Customer IS NULL
GROUP BY E.Name, E.Category, E.Price;
GO

/* ---------- 2. גרף פיזור: היצע מול ביקוש לפי עיר ---------- */
CREATE OR ALTER VIEW V_Marketing_City_Activity AS
SELECT
    E.Location AS City,
    COUNT(DISTINCT E.Name) AS Total_Experiences,
    COUNT(O.OrderID) AS Total_Orders,
    CASE
        WHEN COUNT(DISTINCT E.Name) = 0 THEN 0
        ELSE CAST(COUNT(O.OrderID) AS DECIMAL(10,2)) / COUNT(DISTINCT E.Name)
    END AS Activity_Index
FROM EXPERIENCES E
LEFT JOIN ORDERS O ON E.Name = O.SessionName
GROUP BY E.Location;
GO

/* ---------- 3. Top 5: הזמנות לכל חוויה (שורה לכל חוויה) ---------- */
CREATE OR ALTER VIEW V_Experience_Stats AS
SELECT
   ExperienceName     = E.Name,
   ExperienceCategory = E.Category,
   HostEmail          = E.Host,
   Price              = E.Price,
   TotalOrders        = COUNT(DISTINCT O.OrderID)
FROM EXPERIENCES AS E LEFT JOIN ORDERS AS O ON E.Name = O.SessionName
GROUP BY E.Name, E.Category, E.Host, E.Price;
GO

/* ---------- 4. טבלת מגמות (תיקון 4) ---------- */
CREATE OR ALTER VIEW V_Experience_Trends_Simple AS
WITH MonthlyStats AS (
    SELECT E.Name AS Experience_Name, E.Category,
           YEAR(O.SessionDT)  AS [Year],
           MONTH(O.SessionDT) AS [Month],
           Month_Index     = YEAR(O.SessionDT) * 12 + MONTH(O.SessionDT),
           Orders          = COUNT(*),
           Current_Revenue = SUM(O.ParticipantsNumber * E.Price)
    FROM ORDERS AS O
    JOIN EXPERIENCES AS E ON O.SessionName = E.Name
    GROUP BY E.Name, E.Category, YEAR(O.SessionDT), MONTH(O.SessionDT)
),
WithPrev AS (
    SELECT *,
           Prev_Index   = LAG(Month_Index)     OVER (PARTITION BY Experience_Name ORDER BY Month_Index),
           Prev_Revenue = LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY Month_Index),
           Prev_Orders  = LAG(Orders)          OVER (PARTITION BY Experience_Name ORDER BY Month_Index)
    FROM MonthlyStats
)
SELECT
    Experience_Name, Category, [Year], [Month], Orders, Current_Revenue,
    Prev_Month_Revenue = CASE WHEN Prev_Index = Month_Index - 1 THEN Prev_Revenue ELSE 0 END,
    Revenue_Change     = Current_Revenue
                         - CASE WHEN Prev_Index = Month_Index - 1 THEN Prev_Revenue ELSE 0 END,
    Trend_Status = CASE
        WHEN Prev_Index IS NULL                   THEN 'New'
        WHEN Prev_Index < Month_Index - 1         THEN 'Back after a break'
        WHEN Orders + Prev_Orders < 5             THEN 'Too few orders'
        WHEN Current_Revenue > Prev_Revenue * 1.2 THEN 'Growth'
        WHEN Current_Revenue < Prev_Revenue * 0.8 THEN 'Decline'
        ELSE 'Stable' END
FROM WithPrev;
GO

/* ---------- 5. עוגת גילאים (תיקון 2) ---------- */
CREATE OR ALTER VIEW V_Orders_Age_Distribution AS
SELECT
    Age_Group,
    Sort_Order,
    COUNT(OrderID) AS Total_Orders_Made,
    CAST(COUNT(OrderID) * 100.0 / SUM(COUNT(OrderID)) OVER () AS DECIMAL(5,2)) AS Orders_Pct
FROM (
    SELECT
        O.OrderID,
        Age_Group = CASE
            WHEN A.Age < 18 THEN 'Under 18'
            WHEN A.Age < 25 THEN '18-24'
            WHEN A.Age < 35 THEN '25-34'
            WHEN A.Age < 51 THEN '35-50'
            WHEN A.Age < 65 THEN '51-64'
            ELSE '65+' END,
        Sort_Order = CASE
            WHEN A.Age < 18 THEN 1
            WHEN A.Age < 25 THEN 2
            WHEN A.Age < 35 THEN 3
            WHEN A.Age < 51 THEN 4
            WHEN A.Age < 65 THEN 5
            ELSE 6 END
    FROM ORDERS AS O
    JOIN CREDIT_CARDS AS CC ON O.PaidWith = CC.Account
    JOIN USERS AS U         ON CC.OwnedBy = U.Email
    CROSS JOIN (SELECT MAX(OrderDT) AS AsOf FROM ORDERS) AS D
    CROSS APPLY (SELECT Age = FLOOR(DATEDIFF(DAY, U.Birthdate, D.AsOf) / 365.25)) AS A
) AS OrderDemographics
GROUP BY Age_Group, Sort_Order;
GO

/* ---------- בדיקה ---------- */
SELECT View_Name = 'V_Guest_Revenue_Opportunity', Row_Count = COUNT(*) FROM V_Guest_Revenue_Opportunity
UNION ALL SELECT 'V_Marketing_City_Activity',  COUNT(*) FROM V_Marketing_City_Activity
UNION ALL SELECT 'V_Experience_Stats',         COUNT(*) FROM V_Experience_Stats
UNION ALL SELECT 'V_Experience_Trends_Simple', COUNT(*) FROM V_Experience_Trends_Simple
UNION ALL SELECT 'V_Orders_Age_Distribution',  COUNT(*) FROM V_Orders_Age_Distribution;
-- צפוי: 48 / 48 / 100 / 323 / 4
GO
