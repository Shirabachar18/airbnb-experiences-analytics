/* =====================================================================
   קובץ 3: התיקונים, אחד אחרי השני
   ---------------------------------------------------------------------
   לפני שמתחילים: להריץ קודם את קובץ 1, ואז את קובץ 2 עד הסוף.
   מריצים עם Ctrl+Shift+E ב-Visual Studio, או F5 ב-SSMS.
   כל תיקון בנוי משלושה חלקים:
     A = הבעיה: מריצים ורואים מה לא בסדר
     B = התיקון: הקוד המתוקן
     C = בדיקה: מוודאים שהתיקון עבד
   מסמנים כל חלק בנפרד ומריצים.
   ההסבר המלא לכל תיקון נמצא במדריך (בדוק לפי המספר).
   ===================================================================== */
USE AirbnbPortfolio;
GO


/* =====================================================================
   תיקון 1: הכפלת שורות במארחים המובילים
   ===================================================================== */

-- 1A. הבעיה: אותה הזמנה מופיעה פעם אחת לכל ביקורת על החוויה
--     השורה הראשונה סופרת הזמנות אמיתיות, השנייה סופרת שורות אחרי ה-JOIN
SELECT 'Real orders' AS What, COUNT(*) AS Row_Count FROM ORDERS
UNION ALL
SELECT 'Rows after JOIN to REVIEWS', COUNT(*)
FROM EXPERIENCES AS E
JOIN ORDERS AS O ON E.Name = O.SessionName
LEFT JOIN REVIEWS AS R ON E.Name = R.MadeAbout;
-- צפוי: 669 מול 13,589. כל SUM על השורות האלה מנופח


-- 1B. התיקון: כל מדד מחושב בנפרד, ברמת מארח, ורק אז מחברים
WITH
Host_Sales AS (          -- הכנסות ומשתתפים, בלי ביקורות
    SELECT E.Host,
           Total_Rev          = SUM(O.ParticipantsNumber * E.Price),
           Total_Participants = SUM(O.ParticipantsNumber)
    FROM EXPERIENCES AS E
    JOIN ORDERS AS O ON E.Name = O.SessionName
    GROUP BY E.Host
),
Host_Capacity AS (       -- קיבולת: כל סשן שהוזמן נספר פעם אחת
    SELECT E.Host,
           Total_Capacity = SUM(E.MaxParticipants)
    FROM (SELECT DISTINCT SessionName, SessionDT FROM ORDERS) AS S
    JOIN EXPERIENCES AS E ON E.Name = S.SessionName
    GROUP BY E.Host
),
Host_Rating AS (         -- ביקורות, בלי הזמנות
    SELECT E.Host,
           Avg_Rank = AVG(CAST(R.Rank AS DECIMAL(10,2)))
    FROM EXPERIENCES AS E
    JOIN REVIEWS AS R ON E.Name = R.MadeAbout
    GROUP BY E.Host
),
Host_Efficiency AS (
    SELECT S.Host, S.Total_Rev, R.Avg_Rank,
           Occupancy_Rate = CAST(S.Total_Participants AS DECIMAL(10,2))
                            / NULLIF(C.Total_Capacity, 0)
    FROM Host_Sales AS S
    JOIN Host_Capacity AS C ON C.Host = S.Host
    LEFT JOIN Host_Rating AS R ON R.Host = S.Host
),
Top_Hosts AS (           -- ספים יחסיים במקום 60% קבוע
    SELECT Host, Total_Rev, Occupancy_Rate, Avg_Rank,
           Global_Avg_Rev = (SELECT AVG(Total_Rev) FROM Host_Efficiency)
    FROM Host_Efficiency
    WHERE Occupancy_Rate > (SELECT AVG(Occupancy_Rate) FROM Host_Efficiency)
      AND Avg_Rank >= 3.8
      AND Total_Rev > (SELECT AVG(Total_Rev) FROM Host_Efficiency)
)
SELECT
    U.FirstName + ' ' + U.LastName AS Host_Name,
    Income            = CAST(TH.Total_Rev AS INT),
    Avg_Rank          = CAST(TH.Avg_Rank AS DECIMAL(10,2)),
    Occupancy_Percent = CAST(TH.Occupancy_Rate * 100 AS INT),
    Gap_From_Avg      = CAST(TH.Total_Rev - TH.Global_Avg_Rev AS INT)
FROM Top_Hosts AS TH
JOIN USERS AS U ON TH.Host = U.Email
ORDER BY Gap_From_Avg DESC;
-- צפוי: 2 מארחות - Haley Hoffman ו-Abigail Thomas


-- 1C. בדיקה: סך ההכנסות של כל המארחים צריך להיות שווה לסך ההכנסות באתר
SELECT Sum_Of_Hosts = SUM(Total_Rev)          -- צפוי: 163598.00
FROM (
    SELECT E.Host, Total_Rev = SUM(O.ParticipantsNumber * E.Price)
    FROM EXPERIENCES AS E JOIN ORDERS AS O ON E.Name = O.SessionName
    GROUP BY E.Host
) AS X;
GO


/* =====================================================================
   תיקון 2: תלות בתאריך של היום (GETDATE)
   הרעיון: במקום GETDATE() משתמשים בתאריך ההזמנה האחרונה בנתונים.
   (SELECT MAX(OrderDT) FROM ORDERS) AS D  ->  D.AsOf
   ===================================================================== */

-- 2A. הבעיה: כמה הזמנות יש "בשנה האחרונה" לפי היום, ולפי הנתונים
SELECT
    Orders_Last_Year_By_Today = SUM(CASE WHEN O.OrderDT >= DATEADD(YEAR, -1, GETDATE()) THEN 1 ELSE 0 END),
    Orders_Last_Year_By_Data  = SUM(CASE WHEN O.OrderDT >= DATEADD(YEAR, -1, D.AsOf)    THEN 1 ELSE 0 END),
    Data_Ends_On = MAX(D.AsOf)
FROM ORDERS AS O
CROSS JOIN (SELECT MAX(OrderDT) AS AsOf FROM ORDERS) AS D;


-- 2B-1. שאילתת הלקוחות הפעילים, מתוקנת
SELECT
    U.FirstName + ' ' + U.LastName AS FullName,
    U.BirthDate,
    Total_Orders    = COUNT(DISTINCT O.OrderID),
    Total_Reviews   = COUNT(DISTINCT R.DT),
    Last_Order_Date = MAX(O.OrderDT)
FROM CUSTOMERS AS C
JOIN USERS AS U         ON C.Email = U.Email
JOIN CREDIT_CARDS AS CC ON C.Email = CC.OwnedBy
JOIN ORDERS AS O        ON CC.Account = O.PaidWith
JOIN REVIEWS AS R       ON C.Email = R.Customer
CROSS JOIN (SELECT MAX(OrderDT) AS AsOf FROM ORDERS) AS D
WHERE O.OrderDT >= DATEADD(YEAR, -1, D.AsOf)
GROUP BY U.FirstName, U.LastName, C.Email, U.BirthDate
HAVING COUNT(DISTINCT O.OrderID) >= 2 AND COUNT(DISTINCT R.DT) >= 2
ORDER BY Total_Reviews DESC, Total_Orders DESC;
GO


-- 2B-2. ה-View של הגילאים (שלך), מתוקן:
--       גיל לפי D.AsOf, גיל מדויק בימים (תיקון קטן 2), ועמודת מיון לגרף
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

-- 2C. בדיקה: סך האחוזים 100, וסך ההזמנות 669
SELECT * FROM V_Orders_Age_Distribution ORDER BY Sort_Order;
SELECT SUM(Total_Orders_Made) AS Orders, SUM(Orders_Pct) AS Pct FROM V_Orders_Age_Distribution;
GO


/* =====================================================================
   תיקון 3: ההכנסה הפוטנציאלית מאורחים (החלק שלך)
   ===================================================================== */

-- 3A. הבעיה: גודל קבוצה בחיפוש מול גודל קבוצה בהזמנה בפועל
SELECT
    Avg_Group_In_Guest_Searches = (SELECT AVG(CAST(ParticipantsNumber AS DECIMAL(10,2))) FROM SEARCHES WHERE Customer IS NULL),
    Avg_Group_In_Real_Orders    = (SELECT AVG(CAST(ParticipantsNumber AS DECIMAL(10,2))) FROM ORDERS),
    Old_Potential_Total         = (SELECT SUM(Total_Potential_Loss) FROM V_Missed_Money_On_Floor);
-- צפוי: 8.3 מול 2.2, וסך של 90,461


-- 3B. התיקון: View חדש עם שיעור המרה וגודל הזמנה אמיתיים
CREATE OR ALTER VIEW V_Guest_Revenue_Opportunity AS
WITH Benchmarks AS (     -- נמדד מהמשתמשים הרשומים
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

-- 3C. בדיקה: הסך החדש מול הישן, ולפי קטגוריה (מה שהגרף יציג)
SELECT New_Total = SUM(Estimated_Opportunity) FROM V_Guest_Revenue_Opportunity;   -- בערך 6,500
SELECT Category, Opportunity = SUM(Estimated_Opportunity)
FROM V_Guest_Revenue_Opportunity
GROUP BY Category
ORDER BY Opportunity DESC;
GO


/* =====================================================================
   תיקון 4: אחוזי צמיחה בטבלת המגמות (החלק שלך)
   ===================================================================== */

-- 4A. הבעיה: כמה השוואות הן לא לחודש הצמוד
WITH M AS (
    SELECT SessionName, Month_Index = YEAR(SessionDT) * 12 + MONTH(SessionDT)
    FROM ORDERS
    GROUP BY SessionName, YEAR(SessionDT) * 12 + MONTH(SessionDT)
),
L AS (
    SELECT Month_Index,
           Prev_Index = LAG(Month_Index) OVER (PARTITION BY SessionName ORDER BY Month_Index)
    FROM M
)
SELECT Comparisons     = COUNT(Prev_Index),
       Not_Prev_Month  = SUM(CASE WHEN Month_Index - Prev_Index > 1 THEN 1 ELSE 0 END)
FROM L;
-- צפוי: 223 השוואות, 92 מהן לא לחודש הקודם

-- ודוגמה: Ancient Ruins Photography - אין מכירות במרץ, אפריל ומאי
SELECT Experience_Name, [Year], [Month], Current_Revenue, Previous_Revenue, Growth_Pct
FROM V_Experience_Trends_Simple
WHERE Experience_Name = 'Ancient Ruins Photography';
GO


-- 4B. התיקון
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
    -- החודש הקודם האמיתי. אם לא היו בו מכירות - 0
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

-- 4C. בדיקה: כמה שורות בכל סטטוס, ואותה דוגמה שוב
SELECT Trend_Status, Row_Count = COUNT(*)
FROM V_Experience_Trends_Simple
GROUP BY Trend_Status
ORDER BY Row_Count DESC;

SELECT * FROM V_Experience_Trends_Simple
WHERE Experience_Name = 'Ancient Ruins Photography';
GO


/* =====================================================================
   תיקון 4ב: אותה בעיה בשאילתה 6 (דינמיקת הזמנות חודשית)
   הפתרון כאן שונה: בונים "רשת" של כל חוויה כפול כל חודש, עם 0
   בחודשים בלי הזמנות. ככה "שורה קודמת" היא תמיד "חודש קודם",
   ו-LAG, LEAD והממוצע של 3 חודשים עובדים נכון.
   ===================================================================== */

-- 4ב-A. הבעיה: Kyoto Bamboo Forest Walk בגרסה המקורית
--       אין בכלל שורות לפברואר ולאפריל, אז "החודש הקודם" של מרץ הוא ינואר
SELECT SessionName, [Month] = MONTH(SessionDT), Total_Orders = COUNT(*)
FROM ORDERS
WHERE SessionName = 'Kyoto Bamboo Forest Walk'
GROUP BY SessionName, MONTH(SessionDT)
ORDER BY [Month];
-- צפוי: רק 4 שורות (1, 3, 5, 6). חודשים 2 ו-4 חסרים
GO


-- 4ב-B. התיקון
WITH
Months AS (              -- כל החודשים שיש בנתונים (ינואר עד יוני 2025)
    SELECT DISTINCT [Year] = YEAR(SessionDT), [Month] = MONTH(SessionDT)
    FROM ORDERS
),
Grid AS (                -- כל חוויה כפול כל חודש: 100 x 6 = 600 שורות
    SELECT E.Name AS Experience_Name, M.[Year], M.[Month]
    FROM EXPERIENCES AS E
    CROSS JOIN Months AS M
),
Counts AS (              -- ההזמנות בפועל
    SELECT SessionName, [Year] = YEAR(SessionDT), [Month] = MONTH(SessionDT),
           Total_Orders = COUNT(*)
    FROM ORDERS
    GROUP BY SessionName, YEAR(SessionDT), MONTH(SessionDT)
),
MonthlyStatus AS (       -- חודש בלי הזמנות מקבל 0 במקום להיעלם
    SELECT G.Experience_Name, G.[Year], G.[Month],
           Total_Orders = ISNULL(C.Total_Orders, 0)
    FROM Grid AS G
    LEFT JOIN Counts AS C
           ON C.SessionName = G.Experience_Name
          AND C.[Year] = G.[Year] AND C.[Month] = G.[Month]
)
SELECT
    Experience_Name, [Year], [Month], Total_Orders,
    -- בלי ISNULL: בחודש הראשון אין "קודם" ובאחרון אין "הבא". זה לא 0, זה לא ידוע
    Prev_Month_Order_Count = LAG(Total_Orders)  OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]),
    Next_Month_Order_Count = LEAD(Total_Orders) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]),
    Avg_Last_3_Months_Order_Count = CAST(
        AVG(CAST(Total_Orders AS DECIMAL(10,2)))
        OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]
              ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(10,1)),
    STATUS = CASE
        WHEN Total_Orders > AVG(CAST(Total_Orders AS DECIMAL(10,2)))
             OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]
                   ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) THEN 'Growth Trend'
        WHEN Total_Orders < LAG(Total_Orders)
             OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]) THEN 'Decline'
        ELSE 'Stable' END
FROM MonthlyStatus
WHERE Experience_Name = 'Kyoto Bamboo Forest Walk'   -- למחוק את השורה הזו כדי לראות את כל החוויות
ORDER BY Experience_Name, [Year], [Month];
-- 4ב-C. צפוי: 6 שורות. בפברואר ובאפריל 0. במאי הבא הוא 15, ביוני הקודם הוא 1
GO


/* =====================================================================
   תיקון 5: הדגמת ה-Trigger
   ===================================================================== */

-- 5A+B. ההדגמה המתוקנת: אותו סשן לפני ואחרי. הכול בתוך טרנזקציה
--       עם ROLLBACK, כדי שההזמנה לדוגמה לא תישאר בנתונים
BEGIN TRAN;

    SELECT 'Before' AS Status, Experience, SessionDT, AvailableSpots
    FROM SESSIONS
    WHERE Experience = 'Eiffel Tower Twilight Sketching' AND SessionDT = '2025-06-19 09:00:00';

    INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, PaidWith, SessionName, SessionDT, IP_Address, SearchDT)
    VALUES (671, GETDATE(), 2, (SELECT TOP 1 Account FROM CREDIT_CARDS),
            'Eiffel Tower Twilight Sketching', '2025-06-19 09:00:00',
            '116.69.84.161', '2024-07-31T00:21:16.783');

    SELECT 'After' AS Status, Experience, SessionDT, AvailableSpots
    FROM SESSIONS
    WHERE Experience = 'Eiffel Tower Twilight Sketching' AND SessionDT = '2025-06-19 09:00:00';
    -- צפוי: Before = 36, After = 34

ROLLBACK;
GO


-- 5C. שדרוג רשות: הודעה עסקית ברורה כשאין מספיק מקומות.
--     מסירים את ה-CHECK, אחרת הוא נכשל ראשון עם הודעה טכנית
IF OBJECT_ID('CK_AvailableSpots_NonNegative') IS NOT NULL
    ALTER TABLE SESSIONS DROP CONSTRAINT CK_AvailableSpots_NonNegative;
GO

CREATE OR ALTER TRIGGER TR_Update_Availability
ON ORDERS FOR INSERT
AS
BEGIN
    UPDATE SESSIONS
    SET AvailableSpots = ISNULL(AvailableSpots, 0) - (
            SELECT SUM(i.ParticipantsNumber)
            FROM inserted AS i
            WHERE i.SessionName = SESSIONS.Experience
              AND i.SessionDT   = SESSIONS.SessionDT)
    FROM SESSIONS
    JOIN inserted AS i2 ON SESSIONS.Experience = i2.SessionName
                       AND SESSIONS.SessionDT  = i2.SessionDT;

    IF EXISTS (SELECT 1
               FROM SESSIONS AS S
               JOIN inserted AS i ON S.Experience = i.SessionName AND S.SessionDT = i.SessionDT
               WHERE S.AvailableSpots < 0)
    BEGIN
        THROW 50001, 'Not enough available spots for this session.', 1;
    END
END;
GO

-- בדיקה: מנסים להזמין 100 מקומות. צפוי: ההודעה שלך, וההזמנה לא נשמרת
BEGIN TRY
    BEGIN TRAN;
    INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, PaidWith, SessionName, SessionDT, IP_Address, SearchDT)
    VALUES (672, GETDATE(), 100, (SELECT TOP 1 Account FROM CREDIT_CARDS),
            'Eiffel Tower Twilight Sketching', '2025-06-19 09:00:00',
            '116.69.84.161', '2024-07-31T00:21:16.783');
    ROLLBACK;
    SELECT 'Order accepted (unexpected)' AS Result;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_MESSAGE() AS Result;
END CATCH;

SELECT COUNT(*) AS Orders_Count FROM ORDERS;   -- צפוי: עדיין 669
GO


/* =====================================================================
   תיקון 6: ספים במנוע התמחור ובתוויות
   ===================================================================== */

-- 6A. הבעיה: כמה חוויות נופלות בכל קבוצה לפי הספים המקוריים
SELECT Label = CASE WHEN TotalOrders >= 10 THEN 'High (10+)'
                    WHEN TotalOrders <= 2  THEN 'Low (2 or less)'
                    ELSE 'Stable (3-9)' END,
       Experiences = COUNT(*)
FROM V_Experience_Stats
GROUP BY CASE WHEN TotalOrders >= 10 THEN 'High (10+)'
              WHEN TotalOrders <= 2  THEN 'Low (2 or less)'
              ELSE 'Stable (3-9)' END;
-- צפוי: 7 / 93 / 0
GO


-- 6B-1. מנוע התמחור לפי רבעונים
WITH Ranked AS (
    SELECT *, Demand_Quartile = NTILE(4) OVER (ORDER BY TotalOrders DESC)
    FROM V_Experience_Stats
)
SELECT ExperienceName, ExperienceCategory, TotalOrders,
       Current_Price = Price,
       Pricing_Strategy = CASE Demand_Quartile
           WHEN 1 THEN 'Top 25% demand - test +10%'
           WHEN 4 THEN 'Bottom 25% demand - test -15% or promote'
           ELSE 'Keep price' END,
       New_Recommended_Price = CAST(Price * CASE Demand_Quartile
           WHEN 1 THEN 1.10 WHEN 4 THEN 0.85 ELSE 1.00 END AS DECIMAL(10,2))
FROM Ranked
ORDER BY TotalOrders DESC;
GO


-- 6B-2. פונקציית התווית לפי רבעונים
CREATE OR ALTER FUNCTION F_Get_Experience_Label (@ExpName VARCHAR(100))
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @Quartile INT;

    SELECT @Quartile = Demand_Quartile
    FROM (SELECT ExperienceName,
                 Demand_Quartile = NTILE(4) OVER (ORDER BY TotalOrders DESC)
          FROM V_Experience_Stats) AS Q
    WHERE ExperienceName = @ExpName;

    RETURN CASE @Quartile WHEN 1 THEN 'Best Seller'
                          WHEN 4 THEN 'Slow Mover'
                          ELSE 'Steady' END;
END;
GO

-- 6B-3. חלופה (מומלצת): המלצה לפי שיעור תפוסה עם ספים עסקיים קבועים.
--        טווח רחב באמצע, כדי שהפרש של הזמנה אחת לא יהפוך את ההמלצה.
--        את הספים אפשר לשנות בשתי השורות הראשונות.
DECLARE @RaiseAbove   DECIMAL(4,2) = 0.80;   -- "כמעט אזל"
DECLARE @PromoteBelow DECIMAL(4,2) = 0.10;   -- "כמעט ריק"

WITH Occupancy AS (
    SELECT E.Name AS ExperienceName, E.Category, E.Price,
           Sessions     = (SELECT COUNT(*) FROM SESSIONS AS S WHERE S.Experience = E.Name),
           Seats_Sold   = (SELECT ISNULL(SUM(O.ParticipantsNumber), 0) FROM ORDERS AS O WHERE O.SessionName = E.Name),
           Seats_Offered = E.MaxParticipants * (SELECT COUNT(*) FROM SESSIONS AS S WHERE S.Experience = E.Name)
    FROM EXPERIENCES AS E
)
SELECT ExperienceName, Category, Current_Price = Price,
       Sessions, Seats_Sold, Seats_Offered,
       Occupancy_Pct = CAST(100.0 * Seats_Sold / NULLIF(Seats_Offered, 0) AS DECIMAL(5,1)),
       Recommendation = CASE
           WHEN 1.0 * Seats_Sold / NULLIF(Seats_Offered, 0) >= @RaiseAbove   THEN 'Near sold out - test +10%'
           WHEN 1.0 * Seats_Sold / NULLIF(Seats_Offered, 0) <  @PromoteBelow THEN 'Low occupancy - promote first'
           ELSE 'Keep price' END
FROM Occupancy
ORDER BY Occupancy_Pct DESC;
-- צפוי: אף חוויה לא מעל 80%. הגבוהה ביותר Lisbon Tile Painting עם 54.7%. הממוצע כ-12%
GO

-- סיכום: כמה חוויות בכל טווח תפוסה
SELECT Occupancy_Band, Experiences = COUNT(*)
FROM (
    SELECT Occupancy_Band = CASE
        WHEN Occ >= 0.8 THEN '1. 80%+'
        WHEN Occ >= 0.5 THEN '2. 50-80%'
        WHEN Occ >= 0.1 THEN '3. 10-50%'
        ELSE '4. under 10%' END
    FROM (
        SELECT Occ = 1.0 * (SELECT ISNULL(SUM(O.ParticipantsNumber), 0) FROM ORDERS AS O WHERE O.SessionName = E.Name)
                   / (E.MaxParticipants * (SELECT COUNT(*) FROM SESSIONS AS S WHERE S.Experience = E.Name))
        FROM EXPERIENCES AS E
    ) AS X
) AS B
GROUP BY Occupancy_Band
ORDER BY Occupancy_Band;
-- צפוי: 0 / 1 / 49 / 50
GO


-- 6C. בדיקה: עכשיו כל תווית מקבלת בערך רבע מהחוויות
SELECT Performance_Label = dbo.F_Get_Experience_Label(ExperienceName),
       Experiences = COUNT(*)
FROM V_Experience_Stats
GROUP BY dbo.F_Get_Experience_Label(ExperienceName);
GO


/* =====================================================================
   תיקונים קטנים
   ===================================================================== */

-- קטן 1. חוויות חוזרות - לפי לקוח ולא לפי כרטיס אשראי
SELECT E.Name, E.Category, E.Location
FROM EXPERIENCES AS E
WHERE E.Name IN (
    SELECT O.SessionName
    FROM ORDERS AS O
    JOIN CREDIT_CARDS AS CC ON O.PaidWith = CC.Account
    GROUP BY CC.OwnedBy, O.SessionName
    HAVING COUNT(*) > 1)
ORDER BY E.Category;
-- צפוי: 9 חוויות (במקור 8)
GO

-- קטן 2 (חישוב גיל) כבר תוקן בתיקון 2B-2.
-- קטן 3. במודל התמחור (קובץ 2, סעיף 5) לשנות בשורה האחרונה:
--        ORDER BY Price_Level ASC, [Rank] ASC;

-- קטן 4+5. הפרוצדורה: END שהיה חסר, ובלי למחוק היסטוריה.
--          הטבלה נוצרת פעם אחת. כל הרצה מוחקת ומחשבת רק את החודש שלה
IF OBJECT_ID('HOST_REVENUE_REPORT', 'U') IS NOT NULL
    DROP TABLE HOST_REVENUE_REPORT;   -- פעם אחת, כדי להתחיל נקי

CREATE TABLE HOST_REVENUE_REPORT (
    HostEmail    VARCHAR(100),
    ReportYear   INT,
    ReportMonth  INT,
    TotalGuests  INT,
    TotalRevenue DECIMAL(10,2),
    CONSTRAINT PK_HOST_REVENUE_REPORT PRIMARY KEY (HostEmail, ReportYear, ReportMonth)
);
GO

CREATE OR ALTER PROCEDURE SP_Calc_Host_Revenue (@Month INT, @Year INT)
AS
BEGIN
    DELETE FROM HOST_REVENUE_REPORT
    WHERE ReportYear = @Year AND ReportMonth = @Month;

    INSERT INTO HOST_REVENUE_REPORT (HostEmail, ReportYear, ReportMonth, TotalGuests, TotalRevenue)
    SELECT E.Host, @Year, @Month,
           SUM(O.ParticipantsNumber),
           SUM(O.ParticipantsNumber * E.Price)
    FROM EXPERIENCES AS E
    JOIN ORDERS AS O ON E.Name = O.SessionName
    WHERE MONTH(O.SessionDT) = @Month AND YEAR(O.SessionDT) = @Year
    GROUP BY E.Host;
END;
GO

-- בדיקה: מריצים שני חודשים, ושניהם נשמרים
EXEC SP_Calc_Host_Revenue @Month = 5, @Year = 2025;
EXEC SP_Calc_Host_Revenue @Month = 6, @Year = 2025;
SELECT ReportYear, ReportMonth, Hosts = COUNT(*), Revenue = SUM(TotalRevenue)
FROM HOST_REVENUE_REPORT
GROUP BY ReportYear, ReportMonth;
-- צפוי: שתי שורות - מאי 26,784 ויוני 39,242
GO


/* =====================================================================
   בדיקות איכות נתונים (לשמור כקובץ data_checks.sql לתיק)
   ===================================================================== */
SELECT Check_Name = 'Reviews vs orders',
       Result = CONCAT((SELECT COUNT(*) FROM REVIEWS), ' reviews / ', (SELECT COUNT(*) FROM ORDERS), ' orders')
UNION ALL
SELECT 'Reviews written by a buyer of that experience',
       CONCAT(COUNT(*), ' of ', (SELECT COUNT(*) FROM REVIEWS))
FROM REVIEWS AS R
WHERE EXISTS (SELECT 1 FROM ORDERS AS O
              JOIN CREDIT_CARDS AS CC ON O.PaidWith = CC.Account
              WHERE CC.OwnedBy = R.Customer AND O.SessionName = R.MadeAbout)
UNION ALL
SELECT 'Orders placed after the session date',
       CAST(COUNT(*) AS VARCHAR(20)) FROM ORDERS WHERE OrderDT > SessionDT
UNION ALL
SELECT 'Orders placed before their search',
       CAST(COUNT(*) AS VARCHAR(20)) FROM ORDERS WHERE OrderDT < SearchDT
UNION ALL
SELECT 'Session date range',
       CONCAT(CONVERT(VARCHAR(10), MIN(SessionDT), 23), ' to ', CONVERT(VARCHAR(10), MAX(SessionDT), 23))
FROM SESSIONS;
-- צפוי: 1885/669, 15 of 1885, 103, 419, 2025-01-01 to 2025-06-28
GO
