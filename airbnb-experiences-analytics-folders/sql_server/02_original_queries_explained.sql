/* =====================================================================
   קובץ 2: השאילתות המקוריות מהפרויקט, עם הסבר לכל אחת
   ---------------------------------------------------------------------
   המטרה: להיזכר מה כל שאילתה עושה, לפני שמתקנים.
   איך עובדים עם הקובץ:
     1. מסמנים עם העכבר בלוק אחד (מכותרת לכותרת)
     2. לוחצים Ctrl+Shift+E (ב-Visual Studio) או F5 (ב-SSMS).
        רק החלק המסומן ירוץ
     3. מסתכלים על התוצאה למטה וקוראים את ההסבר
   מה זה GO: מפריד בין "חבילות" פקודות. CREATE VIEW / FUNCTION /
   TRIGGER / PROCEDURE חייבים להיות ראשונים בחבילה, לכן יש GO לפניהם.
   הקוד הוא הקוד שלכם. במקומות שהייתי חייב לשנות כדי שירוץ כתבתי
   "שינוי שלי".
   ===================================================================== */
USE AirbnbPortfolio;
GO

/* =====================================================================
   1. SELECT ללא קינון - שאילתה א: הלקוחות הפעילים ביותר
   ---------------------------------------------------------------------
   שאלה עסקית: מי הזמין לפחות 2 חוויות בשנה האחרונה וגם כתב
   לפחות 2 ביקורות? (כדי לתת להם הטבת יום הולדת)
   איך: מחברים לקוח > משתמש > כרטיס אשראי > הזמנות > ביקורות.
   GROUP BY לפי לקוח, ו-HAVING מסנן אחרי הספירה.
   COUNT(DISTINCT ...) כדי לא לספור אותה הזמנה כמה פעמים.
   שימי לב: היום התוצאה ריקה! זה תיקון 2 (GETDATE).
   ===================================================================== */
SELECT
    U.FirstName + ' ' + U.LastName AS FullName,
    U.BirthDate,
    [Total_Orders] = COUNT(DISTINCT O.OrderID),
    [Total_Reviews] = COUNT(DISTINCT R.DT),
    [Last_Order_Date] = MAX(O.OrderDT)
FROM CUSTOMERS AS C JOIN USERS AS U ON C.Email = U.Email JOIN CREDIT_CARDS AS CC ON C.Email = CC.OwnedBy JOIN ORDERS AS O ON CC.Account = O.PaidWith JOIN REVIEWS AS R ON C.Email = R.Customer
WHERE
    O.OrderDT >= DATEADD(year, -1, GETDATE())
GROUP BY U.FirstName, U.LastName, C.Email, U.BirthDate
HAVING COUNT(DISTINCT O.OrderID) >= 2 AND COUNT(DISTINCT R.DT) >= 2
ORDER BY [Total_Reviews] DESC, [Total_Orders] DESC;


/* =====================================================================
   2. SELECT ללא קינון - שאילתה ב: חוויות פופולריות אצל אורחים
   ---------------------------------------------------------------------
   שאלה עסקית: אילו חוויות מופיעות הכי הרבה בחיפושים של גולשים
   שלא נרשמו לאתר? (כדי לשים שם קופון הרשמה)
   איך: SEARCHES > RETRIEVES (אילו חוויות הופיעו בתוצאות) > EXPERIENCES.
   אורח = Customer IS NULL. סופרים צפיות לכל חוויה לפי חודש.
   ===================================================================== */
SELECT
    E.Name AS Experience_Name,
    E.Location,
    [Total_NoRegisted_Guest_Views] = COUNT(R.Experience),
    [Search_Month] = MONTH(S.SearchDT)
FROM SEARCHES AS S JOIN RETRIEVES AS R ON S.IP_Address = R.IP_Address AND S.SearchDT = R.SearchDT JOIN EXPERIENCES AS E ON R.Experience = E.Name
WHERE S.Customer IS NULL
GROUP BY E.Name, E.Location, MONTH(S.SearchDT)
ORDER BY [Total_NoRegisted_Guest_Views] DESC;


/* =====================================================================
   3. קינון שמחזיר ערך יחיד (Scalar): הזמנות גדולות מהממוצע
   ---------------------------------------------------------------------
   שאלה עסקית: אילו הזמנות שוות יותר מההזמנה הממוצעת? (לקוחות VIP)
   איך: השאילתה הפנימית בסוגריים מחשבת מספר אחד - ממוצע שווי הזמנה.
   השאילתה החיצונית משווה כל הזמנה למספר הזה.
   שווי הזמנה = מספר משתתפים כפול מחיר החוויה.
   ===================================================================== */
SELECT
    O.OrderID,O.SessionName,Order_Value=O.ParticipantsNumber * E.Price
FROM ORDERS AS O JOIN EXPERIENCES AS E ON O.SessionName = E.Name
WHERE O.ParticipantsNumber * E.Price >
      (  SELECT AVG(ord.ParticipantsNumber * exper.Price)
        FROM ORDERS AS ord JOIN EXPERIENCES AS exper ON ord.SessionName = exper.Name
      );


/* =====================================================================
   4. קינון שמחזיר רשימה (List): חוויות "חוזרות"
   ---------------------------------------------------------------------
   שאלה עסקית: לאילו חוויות אותו לקוח חזר יותר מפעם אחת?
   איך: השאילתה הפנימית מחזירה רשימת שמות חוויות שאותו כרטיס אשראי
   הזמין יותר מפעם אחת. החיצונית מביאה את הפרטים עם IN.
   שימי לב: סופרים לפי כרטיס ולא לפי לקוח. זה תיקון קטן 1.
   ===================================================================== */
SELECT Name, Category, Location
FROM EXPERIENCES
WHERE Name IN ( SELECT DISTINCT SessionName
    FROM ORDERS
    GROUP BY PaidWith, SessionName
    HAVING COUNT(*) > 1)
ORDER BY Category;


/* =====================================================================
   5. Window Function א: דוח מודל תמחור
   ---------------------------------------------------------------------
   שאלה עסקית: האם חוויות יקרות באמת מכניסות יותר, ומי הקהל שלהן?
   איך, שלב אחרי שלב:
   - בפנים (LevelData): הכנסה וגיל ממוצע לכל חוויה.
     NTILE(3) מחלק את החוויות ל-3 קבוצות מחיר שוות בגודלן
     (1 = יקר, 3 = זול).
   - בחוץ: RANK() OVER (PARTITION BY Price_Level ...) מדרג חוויות
     בתוך כל קבוצת מחיר לפי הכנסה.
     SUM(...) OVER (PARTITION BY Category) = סך ההכנסה של הקטגוריה,
     ולכן אפשר לחשב אחוז תרומה של כל חוויה לקטגוריה שלה.
   ההבדל בין Window Function ל-GROUP BY: חלון לא "מקפל" שורות.
   כל חוויה נשארת שורה, ומקבלת גם מספר שמחושב על קבוצה.
   שימי לב: GETDATE (תיקון 2) ומיון [Rank] DESC (תיקון קטן 3).
   ===================================================================== */
SELECT
    Category,
    ExperienceName,
    Price,
    Total_Revenue,
    Avg_Age,
    Price_Level,
    [Rank] = RANK() OVER (
        PARTITION BY Price_Level
        ORDER BY Total_Revenue DESC),
   [Category_Revenue_Contribution] = CAST(Total_Revenue * 100.0 /
        SUM(Total_Revenue) OVER (PARTITION BY Category) AS DECIMAL(5,2)),
    [Avg_Age_For_Price_Level] = AVG(Avg_Age) OVER (
        PARTITION BY Price_Level)
FROM (
    SELECT
        E.Category,
        E.Name AS ExperienceName,
        E.Price,
        SUM(O.ParticipantsNumber * E.Price) AS Total_Revenue,
        AVG(DATEDIFF(YEAR, U.BirthDate, GETDATE())) AS Avg_Age,
        NTILE(3) OVER (ORDER BY E.Price DESC) AS Price_Level
    FROM EXPERIENCES AS E JOIN SESSIONS AS S ON E.Name = S.Experience
    JOIN ORDERS AS O ON S.Experience = O.SessionName AND S.SessionDT = O.SessionDT
    JOIN CREDIT_CARDS AS CC ON O.PaidWith = CC.Account
    JOIN USERS AS U ON CC.OwnedBy = U.Email
    WHERE O.OrderDT >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY E.Category, E.Name, E.Price
) AS LevelData
ORDER BY Price_Level ASC, [Rank] DESC;


/* =====================================================================
   6. Window Function ב: דינמיקת הזמנות חודשית
   ---------------------------------------------------------------------
   שאלה עסקית: האם חוויה בצמיחה (לפתוח עוד סשנים) או בדעיכה
   (להגביר שיווק)?
   איך:
   - בפנים: מספר הזמנות לכל חוויה בכל חודש.
   - LAG = הערך מהשורה הקודמת (החודש הקודם), LEAD = מהשורה הבאה.
   - ROWS BETWEEN 2 PRECEDING AND CURRENT ROW = ממוצע נע של 3 חודשים.
   - CASE נותן סטטוס: צמיחה, ירידה או יציב.
   שימי לב: LAG לוקח "שורה קודמת" ולא "חודש קודם". זה תיקון 4.
   ===================================================================== */
SELECT
    Experience_Name,
    [Year],
    [Month],
    Total_Orders,
[Prev_Month_Order_Count] = ISNULL(
                                  LAG(Total_Orders)
                                  OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]),
                              0),
   [Next_Month_Order_Count] = ISNULL(
                                  LEAD(Total_Orders)
                                  OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]),
                              0),
   [Avg_Last_3_Months_Order_Count] = ISNULL(
                                         CAST(
                                            AVG(CAST(Total_Orders AS DECIMAL(10,2)))
                                            OVER (
                                                PARTITION BY Experience_Name
                                                ORDER BY [Year], [Month]
                                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
                                            )
                                         AS DECIMAL(10,1)),
                                     0) ,
    STATUS = CASE
        WHEN Total_Orders > AVG(CAST(Total_Orders AS DECIMAL(10,2)))
             OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month] ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
        THEN 'Growth Trend'
        WHEN Total_Orders < LAG(Total_Orders) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month])
        THEN 'Decline'
        ELSE 'Stable'
    END
FROM (
    SELECT
        SessionName AS Experience_Name,
        YEAR(SessionDT) AS [Year],
        MONTH(SessionDT) AS [Month],
        COUNT(OrderID) AS Total_Orders
    FROM ORDERS
    GROUP BY SessionName, YEAR(SessionDT), MONTH(SessionDT)
) AS MonthlyStatus;


/* =====================================================================
   7. WITH (CTE): מארחים מובילים
   ---------------------------------------------------------------------
   שאלה עסקית: אילו מארחים גם מלאים (תפוסה 60%+), גם מדורגים
   גבוה (4+) וגם מרוויחים מעל הממוצע? (לתגמל ולשמר אותם)
   איך: CTE = "טבלה זמנית עם שם" שקיימת רק בתוך השאילתה.
   Host_Activity > Host_Efficiency > Top_Hosts, כל שלב בונה על הקודם.
   שימי לב לתוצאה: תפוסה של 197% ו-468% - בלתי אפשרי!
   זה תיקון 1, הבאג הכי חשוב בפרויקט.
   ===================================================================== */
WITH
Host_Activity AS (
    SELECT
        E.Host,
        [Total_Rev] = SUM(O.ParticipantsNumber * E.Price),
        [Total_Participants] = SUM(O.ParticipantsNumber),
      [Total_Capacity] = COUNT(DISTINCT O.SessionDT) * MAX(E.MaxParticipants),
        [Avg_Rank] = AVG(CAST(R.Rank AS DECIMAL(10,2)))
    FROM EXPERIENCES AS E
    JOIN ORDERS AS O ON E.Name = O.SessionName
    LEFT JOIN REVIEWS AS  R ON E.Name = R.MadeAbout
    GROUP BY E.Host
),
Host_Efficiency AS (
    SELECT
        Host,
        Total_Rev,
        Avg_Rank,
        [Occupancy_Rate] = CAST(Total_Participants AS DECIMAL(10,2))
/NULLIF(Total_Capacity, 0)
    FROM Host_Activity
),
Top_Hosts AS (
    SELECT
        Host,
        Total_Rev,
        Occupancy_Rate,
        Avg_Rank,
        [Global_Avg_Rev] = (SELECT AVG(Total_Rev) FROM Host_Efficiency)
    FROM Host_Efficiency
    WHERE Occupancy_Rate >= 0.6
     AND Avg_Rank >=4
     AND Total_Rev > (SELECT AVG(Total_Rev) FROM Host_Efficiency)
      )
SELECT
    U.FirstName + ' ' + U.LastName AS Host_Name,
   [Income] = CAST(TH.Total_Rev AS INT),
    [Avg_Rank] = CAST(TH.Avg_Rank AS DECIMAL(10,2)),
    [Occupancy_Percent] = CAST(TH.Occupancy_Rate * 100 AS int),
    [Gap_From_Avg] = CAST(TH.Total_Rev - TH.Global_Avg_Rev AS INT)
FROM Top_Hosts AS TH
JOIN USERS AS U ON TH.Host = U.Email
ORDER BY [Gap_From_Avg] DESC;
GO


/* =====================================================================
   8. View: מספר הזמנות לכל חוויה + מנוע המלצות תמחור
   ---------------------------------------------------------------------
   View = שאילתה ששמורה בשם, ומשתמשים בה כמו בטבלה.
   LEFT JOIN כדי שגם חוויה בלי הזמנות תופיע (עם 0).
   אחר כך: CASE שממליץ להעלות או להוריד מחיר לפי מספר ההזמנות.
   שימי לב: 93 מ-100 חוויות מקבלות "Keep Price". זה תיקון 6.
   ===================================================================== */
CREATE OR ALTER VIEW V_Experience_Stats AS
SELECT
   ExperienceName= E.Name,
   ExperienceCategory= E.Category,
   HostEmail= E.Host,
   Price=E.Price,
   TotalOrders= COUNT(DISTINCT O.OrderID)
FROM EXPERIENCES AS E LEFT JOIN ORDERS AS O ON E.Name = O.SessionName
GROUP BY E.Name, E.Category, E.Host, E.Price;
GO

SELECT
    ExperienceName,
    ExperienceCategory,
    [Current_Price] = Price,
    TotalOrders,
    [Pricing_Strategy] = CASE
        WHEN TotalOrders >= 10 THEN 'High Demand - Increase Price (+10%)'
        WHEN TotalOrders <= 2  THEN 'Low Demand - Decrease Price (-15%)'
        ELSE 'Stable Demand - Keep Price'
    END,
    [New_Recommended_Price] = CAST(
        CASE
            WHEN TotalOrders >= 10 THEN CAST(Price AS DECIMAL(10,2)) * 1.10
            WHEN TotalOrders <= 2  THEN CAST(Price AS DECIMAL(10,2)) * 0.85
            ELSE CAST(Price AS DECIMAL(10,2))
        END AS DECIMAL(10,2))
FROM V_Experience_Stats
ORDER BY TotalOrders DESC;
GO


/* =====================================================================
   9. פונקציה סקלרית: תווית פופולריות לחוויה
   ---------------------------------------------------------------------
   פונקציה סקלרית = מקבלת ערך ומחזירה ערך אחד.
   מקבלת שם חוויה, קוראת את מספר ההזמנות מה-View, ומחזירה תווית.
   DECLARE = הגדרת משתנה. @ = שם של משתנה.
   ===================================================================== */
CREATE OR ALTER FUNCTION F_Get_Experience_Label (@ExpName VARCHAR(100))
RETURNS VARCHAR(20)
AS BEGIN
    DECLARE @Orders INT;
    DECLARE @Label VARCHAR(20);
    SELECT @Orders = TotalOrders
    FROM V_Experience_Stats
    WHERE ExperienceName = @ExpName;
    IF @Orders >= 10
        SET @Label = 'Best Seller';
    ELSE IF @Orders >= 3
        SET @Label = 'Trending';
    ELSE
        SET @Label = 'Slow Mover';
    RETURN @Label;
END;
GO

SELECT
    ExperienceName,
    ExperienceCategory,
    TotalOrders,
    [Performance_Label] = dbo.F_Get_Experience_Label(ExperienceName)
FROM V_Experience_Stats
ORDER BY TotalOrders DESC;
GO


/* =====================================================================
   10. פונקציה טבלאית: חוויות זמינות ביעד מסוים
   ---------------------------------------------------------------------
   פונקציה טבלאית = מחזירה טבלה. משתמשים בה ב-FROM כמו בטבלה.
   מקבלת עיר ותאריך, ומחזירה את כל הסשנים מהתאריך הזה והלאה.
   ===================================================================== */
CREATE OR ALTER FUNCTION F_Find_Available_Experiences (@Location VARCHAR(100),@StartDate DATETIME)
RETURNS TABLE
AS
RETURN (
    SELECT
        ExperienceName = E.Name,
        Category = E.Category,
        SessionTime = S.SessionDT,
        Price = E.Price
 FROM SESSIONS AS S JOIN EXPERIENCES AS E ON S.Experience = E.Name
    WHERE
        E.Location = @Location
        AND S.SessionDT >= @StartDate
);
GO

SELECT * FROM F_Find_Available_Experiences('Berlin', '2025-05-01')
ORDER BY SessionTime ASC;
GO


/* =====================================================================
   11. Trigger: עדכון מקומות פנויים בכל הזמנה
   ---------------------------------------------------------------------
   Trigger = קוד שרץ לבד כשקורה משהו בטבלה (כאן: INSERT להזמנות).
   שלבים: (א) מוסיפים עמודה AvailableSpots לסשנים
          (ב) ממלאים אותה: מקסימום משתתפים פחות מה שכבר הוזמן
          (ג) יוצרים את הטריגר
   inserted = טבלה מיוחדת שמכילה את השורות שנוספו עכשיו.
   ===================================================================== */
-- (א) שינוי שלי: הוספתי IF, כדי שאפשר יהיה להריץ שוב בלי שגיאה
IF COL_LENGTH('SESSIONS', 'AvailableSpots') IS NULL
    ALTER TABLE SESSIONS ADD AvailableSpots INT;
GO
IF OBJECT_ID('CK_AvailableSpots_NonNegative') IS NULL
    ALTER TABLE SESSIONS
    ADD CONSTRAINT CK_AvailableSpots_NonNegative CHECK (AvailableSpots >= 0);
GO

-- (ב)
WITH ExistingBookings AS (
    SELECT
        SessionName,
        SessionDT,
       TotalBooked=SUM(ParticipantsNumber)
    FROM ORDERS
    GROUP BY SessionName, SessionDT
)
UPDATE S
SET AvailableSpots = E.MaxParticipants - ISNULL(EB.TotalBooked, 0)
FROM SESSIONS AS S JOIN EXPERIENCES AS E ON S.Experience = E.Name LEFT JOIN ExistingBookings EB ON (S.Experience = EB.SessionName AND S.SessionDT = EB.SessionDT);
GO

-- (ג)
CREATE OR ALTER TRIGGER TR_Update_Availability
ON ORDERS FOR INSERT
AS
BEGIN
UPDATE SESSIONS
SET AvailableSpots =
    ISNULL(AvailableSpots, 0) - (
        SELECT SUM(i.ParticipantsNumber)
        FROM inserted i
        WHERE i.SessionName = SESSIONS.Experience
          AND i.SessionDT = SESSIONS.SessionDT
    )
FROM SESSIONS JOIN inserted i2 ON
    SESSIONS.Experience = i2.SessionName AND
    SESSIONS.SessionDT = i2.SessionDT;
END;
GO

-- הדגמה. שינוי שלי: הכול בתוך BEGIN TRAN ... ROLLBACK,
-- כדי שההזמנה לדוגמה לא תישאר בנתונים ולא תשנה את המספרים בהמשך.
-- שינוי שלי 2: זמן החיפוש תוקן לזמן שקיים בטבלה, אחרת ה-FK נכשל.
BEGIN TRAN;

    SELECT 'Before New Order' AS Status, Experience, SessionDT, AvailableSpots
    FROM SESSIONS
    WHERE Experience = 'Eiffel Tower Twilight Sketching'
      AND SessionDT = '2025-06-19 09:00:00';

    INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, PaidWith, SessionName, SessionDT, IP_Address, SearchDT)
    SELECT 671, GETDATE(), 2, (SELECT TOP 1 Account FROM CREDIT_CARDS),
           'Eiffel Tower Twilight Sketching', '2025-06-19 09:00:00',
           '116.69.84.161', '2024-07-31T00:21:16.783';

    -- זו השאילתה המקורית: בודקת סשן אחר (Pasta) שלא קיים. התוצאה ריקה. ראי תיקון 5
    SELECT Experience, SessionDT, AvailableSpots
    FROM SESSIONS
    WHERE Experience = 'Pasta Making from Scratch'
      AND SessionDT = '2024-06-01 18:00';

ROLLBACK;
GO


/* =====================================================================
   12. Stored Procedure: דוח הכנסות חודשי למארחים
   ---------------------------------------------------------------------
   פרוצדורה = תוכנית שמורה שמקבלת פרמטרים (כאן: חודש ושנה).
   יוצרת טבלה HOST_REVENUE_REPORT וממלאת בה סיכום לכל מארח.
   שינוי שלי: הוספתי END; שהיה חסר. בלעדיו ה-EXEC נכנס לתוך הפרוצדורה.
   ===================================================================== */
CREATE OR ALTER PROCEDURE SP_Calc_Host_Revenue (@Month INT, @Year INT)
AS
BEGIN
    IF OBJECT_ID('HOST_REVENUE_REPORT', 'U') IS NOT NULL
        DROP TABLE HOST_REVENUE_REPORT;

    CREATE TABLE HOST_REVENUE_REPORT (
        HostEmail VARCHAR(100),
        ReportYear INT,
        ReportMonth INT,
        TotalGuests INT,
        TotalRevenue DECIMAL(10, 2)
    );

    INSERT INTO HOST_REVENUE_REPORT (HostEmail, ReportYear, ReportMonth, TotalGuests, TotalRevenue)
    SELECT
        E.Host,
        @Year,
        @Month,
        SUM(O.ParticipantsNumber),
        SUM(O.ParticipantsNumber * E.Price)
    FROM EXPERIENCES E JOIN ORDERS O ON E.Name = O.SessionName
    WHERE MONTH(O.SessionDT) = @Month AND YEAR(O.SessionDT) = @Year
    GROUP BY E.Host;
END;
GO

EXEC SP_Calc_Host_Revenue @Month = 5, @Year = 2025;
SELECT * FROM HOST_REVENUE_REPORT ORDER BY TotalRevenue DESC;
GO


/* =====================================================================
   13. ה-Views של דשבורד השיווק  <<< זה החלק שלך >>>
   ---------------------------------------------------------------------
   ארבעה Views שמזינים את ה-Power BI של השיווק.
   אחרי שתריצי כל CREATE, הריצי את ה-SELECT שמתחתיו כדי לראות
   מה הדשבורד מקבל.
   ===================================================================== */

-- 13א. "כסף על הרצפה": הכנסה פוטנציאלית מאורחים (הטרימאפ)
-- לכל חוויה: כמה פעמים הופיעה לאורחים, כפול מחיר, כפול גודל קבוצה ממוצע.
-- שימי לב: מניח שכל אורח היה קונה. זה תיקון 3.
CREATE OR ALTER VIEW V_Missed_Money_On_Floor AS
SELECT
    E.Name AS Experience_Name,
    E.Category,
    E.Price,
    COUNT(S.SearchDT) AS Search_Volume,
    AVG(CAST(ISNULL(S.ParticipantsNumber, 1) AS DECIMAL(10,2))) AS Avg_Group_Size,
    CAST(
        (COUNT(S.SearchDT) * E.Price * AVG(CAST(ISNULL(S.ParticipantsNumber, 1) AS DECIMAL(10,2))))
    AS DECIMAL(12, 2)) AS Total_Potential_Loss
FROM
    SEARCHES S
JOIN
    RETRIEVES R ON S.IP_Address = R.IP_Address AND S.SearchDT = R.SearchDT
JOIN
    EXPERIENCES E ON R.Experience = E.Name
WHERE
    S.Customer IS NULL
GROUP BY
    E.Name, E.Category, E.Price;
GO
SELECT TOP 10 * FROM V_Missed_Money_On_Floor ORDER BY Total_Potential_Loss DESC;
SELECT SUM(Total_Potential_Loss) AS Total FROM V_Missed_Money_On_Floor;   -- 90,461
GO

-- 13ב. היצע מול ביקוש לפי עיר (גרף העמודות)
-- Activity_Index = כמה הזמנות יש בממוצע לכל חוויה בעיר.
-- גבוה = ביקוש גדול על היצע קטן, צריך לגייס מארחים.
-- שינוי שלי: הסרתי סימן ? שנשאר בסוף השאילתה מבעיית קידוד.
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
SELECT * FROM V_Marketing_City_Activity ORDER BY Activity_Index DESC;
GO

-- 13ג. פילוח הזמנות לפי גיל (עוגה)
-- בפנים: לכל הזמנה מחשבים את קבוצת הגיל של המזמין.
-- בחוץ: סופרים ומחשבים אחוז. SUM(COUNT(...)) OVER() = סך כל ההזמנות.
CREATE OR ALTER VIEW V_Orders_Age_Distribution AS
SELECT
    Age_Group,
    COUNT(OrderID) AS Total_Orders_Made,
    CAST(
        COUNT(OrderID) * 100.0 / SUM(COUNT(OrderID)) OVER()
    AS DECIMAL(5,2)) AS Orders_Pct
FROM (
    SELECT
        O.OrderID,
        U.Email,
        CASE
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) < 18 THEN 'Under 18'
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) BETWEEN 18 AND 24 THEN '18-24'
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) BETWEEN 25 AND 34 THEN '25-34'
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) BETWEEN 35 AND 50 THEN '35-50'
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) BETWEEN 51 AND 64 THEN '51-64'
            WHEN DATEDIFF(YEAR, BirthDate, GETDATE()) >= 65 THEN '65+'
            ELSE 'Unknown'
        END AS Age_Group
FROM ORDERS as O
    JOIN CREDIT_CARDS as CC ON O.PaidWith = CC.Account
    JOIN USERS U ON CC.OwnedBy = U.Email
) AS OrderDemographics
GROUP BY Age_Group;
GO
SELECT * FROM V_Orders_Age_Distribution ORDER BY Age_Group;
GO

-- 13ד. מגמת מכירות חודשית לכל חוויה (הטבלה עם החצים)
-- MonthlyStats = הכנסה לכל חוויה בכל חודש.
-- LAG מביא את ההכנסה של "החודש הקודם", ומחשבים אחוז שינוי וסטטוס.
-- שימי לב: 3100% ו-1450%. זה תיקון 4.
CREATE OR ALTER VIEW V_Experience_Trends_Simple AS
WITH MonthlyStats AS (
    SELECT
        E.Name AS Experience_Name,
        E.Category,
        YEAR(S.SessionDT) AS [Year],
        MONTH(S.SessionDT) AS [Month],
        SUM(O.ParticipantsNumber * E.Price) AS Current_Revenue
    FROM ORDERS O
    JOIN SESSIONS S ON O.SessionName = S.Experience AND O.SessionDT = S.SessionDT
    JOIN EXPERIENCES E ON S.Experience = E.Name
    GROUP BY E.Name, E.Category, YEAR(S.SessionDT), MONTH(S.SessionDT)
)
SELECT
    Experience_Name,
    Category,
    [Year],
    [Month],
    Current_Revenue,
    LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]) AS Previous_Revenue,
    CASE
        WHEN LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]) IS NULL THEN NULL
        WHEN LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]) = 0 THEN 1
        ELSE
            (Current_Revenue - LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]))
            / CAST(LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month]) AS DECIMAL(10,2))
    END AS Growth_Pct,
    CASE
        WHEN (Current_Revenue - LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month])) < 0 THEN 'Decline'
        WHEN (Current_Revenue - LAG(Current_Revenue) OVER (PARTITION BY Experience_Name ORDER BY [Year], [Month])) > 0 THEN 'Growth'
        ELSE 'Stable'
    END AS Trend_Status
FROM MonthlyStats;
GO
SELECT * FROM V_Experience_Trends_Simple ORDER BY Growth_Pct DESC;
GO


/* =====================================================================
   14. ה-Views של דשבורד ההנהלה (של השותפות)
   ---------------------------------------------------------------------
   שימי לב: הקוד הזה מגדיר מחדש את V_Experience_Stats עם עמודת תאריך.
   זה שובר את הפונקציה מסעיף 9 (ראי תיקון 6). לכן כאן יצרתי אותו
   בשם אחר, V_Experience_Stats_Mgmt, כדי לא לשבור את מה שלמעלה.
   (שינוי שלי: רק השם)
   ===================================================================== */
CREATE OR ALTER VIEW V_Experience_Stats_Mgmt AS
SELECT
    ExperienceName = E.Name,
    ExperienceCategory = E.Category,
    HostEmail = E.Host,
    Location = E.Location,
    Price = E.Price,
    OrderDate = O.OrderDT,
    TotalOrders = COUNT(O.OrderID),
    TotalRevenue = SUM(E.Price * O.ParticipantsNumber)
FROM EXPERIENCES AS E
LEFT JOIN ORDERS AS O ON E.Name = O.SessionName
GROUP BY E.Name, E.Category, E.Host, E.Location, E.Price, O.OrderDT;
GO

CREATE OR ALTER VIEW V_Experience_Quality AS
SELECT
    ExperienceCategory = E.Category,
    ExperienceName = E.Name,
    ReviewDate = R.DT,
    AvgRating = AVG(R.Rank * 1.0),
    TotalReviews = COUNT(R.Rank)
FROM EXPERIENCES AS E
LEFT JOIN REVIEWS AS R ON E.Name = R.MadeAbout
GROUP BY E.Category, E.Name, R.DT;
GO


/* =====================================================================
   15. אופטימיזציה עם אינדקסים (מטלה 4)
   ---------------------------------------------------------------------
   אינדקס = כמו תוכן עניינים בספר. השרת מוצא שורות מהר בלי לסרוק
   את כל הטבלה. הפלט לא משתנה, רק המהירות.
   EXISTS במקום IN: עוצר ברגע שמצא התאמה אחת.
   ===================================================================== */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SEARCHES_Guest_Search')
    CREATE INDEX IX_SEARCHES_Guest_Search ON SEARCHES (IP_Address, SearchDT) INCLUDE (Customer);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RETRIEVES_Search')
    CREATE INDEX IX_RETRIEVES_Search ON RETRIEVES (IP_Address, SearchDT, Experience);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ORDERS_SessionName_PaidWith')
    CREATE INDEX IX_ORDERS_SessionName_PaidWith ON ORDERS (SessionName, PaidWith);
GO

SELECT E.Name, E.Category, E.Location
FROM EXPERIENCES E
WHERE EXISTS (
    SELECT 1
    FROM ORDERS O
    WHERE O.SessionName = E.Name
    GROUP BY O.PaidWith
    HAVING COUNT(*) > 1)
ORDER BY E.Category;
GO


/* =====================================================================
   16. בונוס JSON: פרוצדורה עם פירוט הכנסות לכל מארח
   ---------------------------------------------------------------------
   FOR JSON PATH הופך תוצאת שאילתה לטקסט JSON, ושומר אותו בעמודה אחת.
   כך כל שורת מארח מכילה גם פירוט לפי חוויה.
   שינוי שלי: הוספתי END; חסר, ועטפתי את נתוני הדמו ב-BEGIN TRAN ...
   ROLLBACK כדי שלא יישארו בבסיס הנתונים.
   ===================================================================== */
CREATE OR ALTER PROCEDURE SP_Calc_Host_Revenue_WithJSON (@Month INT, @Year INT)
AS
BEGIN
    IF OBJECT_ID('HOST_REVENUE_REPORT', 'U') IS NOT NULL DROP TABLE HOST_REVENUE_REPORT;

    CREATE TABLE HOST_REVENUE_REPORT (
        HostEmail VARCHAR(100),
        ReportYear INT,
        ReportMonth INT,
        TotalGuests INT,
        TotalRevenue DECIMAL(10, 2),
        RevenueBreakdown NVARCHAR(MAX)
    );

    INSERT INTO HOST_REVENUE_REPORT (HostEmail, ReportYear, ReportMonth, TotalGuests, TotalRevenue, RevenueBreakdown)
    SELECT
        E.Host, @Year, @Month, SUM(O.ParticipantsNumber), SUM(O.ParticipantsNumber * E.Price),
        (
            SELECT E_Inner.Name AS ExperienceName, COUNT(O_Inner.OrderID) AS OrdersCount,
                   SUM(O_Inner.ParticipantsNumber * E_Inner.Price) AS ExperienceRevenue
            FROM EXPERIENCES E_Inner
            JOIN ORDERS O_Inner ON E_Inner.Name = O_Inner.SessionName
            WHERE E_Inner.Host = E.Host AND MONTH(O_Inner.SessionDT) = @Month AND YEAR(O_Inner.SessionDT) = @Year
            GROUP BY E_Inner.Name, E_Inner.Price
            FOR JSON PATH
        )
    FROM EXPERIENCES E
    JOIN ORDERS O ON E.Name = O.SessionName
    WHERE MONTH(O.SessionDT) = @Month AND YEAR(O.SessionDT) = @Year
    GROUP BY E.Host;
END;
GO

-- הדמו: מארח עם שתי חוויות, כדי לראות JSON עם יותר מפריט אחד.
-- דורש שסעיף 11 (Trigger) רץ קודם, כי משתמש בעמודה AvailableSpots.
BEGIN TRAN;

DECLARE @Email VARCHAR(100) = 'DEMO999@gmail.com';
DECLARE @Location VARCHAR(50) = 'London';
DECLARE @SearchDate DATETIME = '2025-05-01 10:00:00';
DECLARE @IP VARCHAR(20) = '127.0.0.1';
DECLARE @ExistingCard VARCHAR(20);
SELECT TOP 1 @ExistingCard = PaidWith FROM ORDERS WHERE PaidWith IS NOT NULL;

INSERT INTO USERS (Email, Password, FirstName, LastName, PhoneNumber, Birthdate)
VALUES (@Email, 'Pa$$w0rd123!', 'Demo', 'Host', '0500000000', '1990-01-01');
INSERT INTO HOSTS (Email, Bio, AccountNumber, BankBranch, BankName, AccountHolderName)
VALUES (@Email, 'Demo Bio', '123456', '999', 'Bank Leumi', 'Demo Host');
INSERT INTO CUSTOMERS (Email) VALUES (@Email);
INSERT INTO SEARCHES (IP_Address, SearchDT, Location, StartDate, EndDate, ParticipantsNumber, Customer)
VALUES (@IP, @SearchDate, @Location, '2025-05-01', '2025-05-30', 2, @Email);
INSERT INTO EXPERIENCES (Name, Category, Price, Location, MaxParticipants, Description, Host)
VALUES ('Demo_Cooking_Class', 'Cooking', 100, @Location, 10, 'Test 1', @Email);
INSERT INTO EXPERIENCES (Name, Category, Price, Location, MaxParticipants, Description, Host)
VALUES ('Demo_Art_Tour', 'Art', 50, @Location, 20, 'Test 2', @Email);
INSERT INTO SESSIONS (Experience, SessionDT, AvailableSpots) VALUES ('Demo_Cooking_Class', '2025-05-10 10:00:00', 10);
INSERT INTO SESSIONS (Experience, SessionDT, AvailableSpots) VALUES ('Demo_Art_Tour', '2025-05-15 16:00:00', 20);
INSERT INTO SESSIONS (Experience, SessionDT, AvailableSpots) VALUES ('Demo_Art_Tour', '2025-05-20 16:00:00', 20);
INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, SessionName, SessionDT, IP_Address, SearchDT, PaidWith)
VALUES (99001, GETDATE(), 3, 'Demo_Cooking_Class', '2025-05-10 10:00:00', @IP, @SearchDate, @ExistingCard);
INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, SessionName, SessionDT, IP_Address, SearchDT, PaidWith)
VALUES (99002, GETDATE(), 2, 'Demo_Art_Tour', '2025-05-15 16:00:00', @IP, @SearchDate, @ExistingCard);
INSERT INTO ORDERS (OrderID, OrderDT, ParticipantsNumber, SessionName, SessionDT, IP_Address, SearchDT, PaidWith)
VALUES (99003, GETDATE(), 4, 'Demo_Art_Tour', '2025-05-20 16:00:00', @IP, @SearchDate, @ExistingCard);

EXEC SP_Calc_Host_Revenue_WithJSON @Month = 5, @Year = 2025;

SELECT HostEmail, TotalRevenue, RevenueBreakdown
FROM HOST_REVENUE_REPORT
WHERE HostEmail = 'DEMO999@gmail.com';

ROLLBACK;
GO
