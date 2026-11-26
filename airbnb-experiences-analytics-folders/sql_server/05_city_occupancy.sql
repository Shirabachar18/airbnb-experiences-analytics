/* =====================================================================
   קובץ 6: תפוסה לפי עיר (היצע מול ביקוש במקומות)
   היצע = כמה מקומות היו בכל הסשנים בעיר
   ביקוש = כמה מקומות נמכרו
   תפוסה = ביקוש / היצע
   חיפושים = כמה אנשים התעניינו בעיר (ל-Tooltip)
   מריצים פעם אחת: F5 בלי לסמן כלום.
   ===================================================================== */
USE AirbnbPortfolio;
GO

CREATE OR ALTER VIEW V_City_Occupancy AS
WITH Per_Experience AS (
    SELECT E.Name, E.Location,
           Seats_Offered = E.MaxParticipants
                           * (SELECT COUNT(*) FROM SESSIONS AS S WHERE S.Experience = E.Name),
           Seats_Sold    = (SELECT ISNULL(SUM(O.ParticipantsNumber), 0)
                            FROM ORDERS AS O WHERE O.SessionName = E.Name)
    FROM EXPERIENCES AS E
),
City_Searches AS (       -- עניין: כמה חיפושים היו בעיר (רשומים ואורחים)
    SELECT Location, Searches = COUNT(*)
    FROM SEARCHES
    GROUP BY Location
)
SELECT
    City          = P.Location,
    Searches      = ISNULL(MAX(CS.Searches), 0),
    Experiences   = COUNT(*),
    Seats_Offered = SUM(Seats_Offered),
    Seats_Sold    = SUM(Seats_Sold),
    Occupancy     = CAST(1.0 * SUM(Seats_Sold) / NULLIF(SUM(Seats_Offered), 0) AS DECIMAL(5,3))
FROM Per_Experience AS P
LEFT JOIN City_Searches AS CS ON CS.Location = P.Location
GROUP BY P.Location;
GO

/* ---------- בדיקה ---------- */
SELECT TOP 5 * FROM V_City_Occupancy ORDER BY Occupancy DESC;
-- צפוי: Lisbon ראשונה עם 0.488 (119 מתוך 244 מקומות, 53 חיפושים), אחריה Amsterdam עם 0.200
GO
