/* =====================================================================
   קובץ 9: מבנה "כוכב" (Star Schema) לדשבורד ההנהלה
   ---------------------------------------------------------------------
   למה: הדירוג מגיע מטבלת הביקורות, וההכנסות מטבלת ההזמנות.
   כדי שסלייסר קטגוריה או בחירת מארח יסננו את שתיהן יחד,
   צריך טבלה אחת "באמצע" שמתארת את החוויות, ושתיהן מחוברות אליה.

        Calendar ──┐                 ┌── V_Mgmt_Experiences (חוויה, קטגוריה, עיר, מארח)
                   ├── V_Mgmt_Orders ┤
                   └── V_Mgmt_Reviews┘

   V_Mgmt_Orders מקובץ 8 נשאר כמו שהוא.
   מריצים פעם אחת: F5 בלי לסמן כלום.
   ===================================================================== */
USE AirbnbPortfolio;
GO

/* ---------- טבלת התיאור: שורה לכל חוויה ---------- */
CREATE OR ALTER VIEW V_Mgmt_Experiences AS
SELECT
    Experience_Name = E.Name,
    Category        = E.Category,
    City            = E.Location,
    Price           = E.Price,
    Host_Email      = E.Host,
    Host_Name       = U.FirstName + ' ' + U.LastName
FROM EXPERIENCES AS E
LEFT JOIN USERS AS U ON U.Email = E.Host;
GO

/* ---------- טבלת הביקורות: שורה לכל ביקורת ---------- */
CREATE OR ALTER VIEW V_Mgmt_Reviews AS
SELECT
    Review_Date     = CAST(R.DT AS DATE),
    Experience_Name = R.MadeAbout,
    Rating          = R.Rank
FROM REVIEWS AS R;
GO

/* ---------- בדיקה ---------- */
SELECT Experiences = COUNT(*), Hosts = COUNT(DISTINCT Host_Email) FROM V_Mgmt_Experiences;
-- צפוי: 100 / 100

SELECT [Year] = YEAR(Review_Date), Reviews = COUNT(*), Avg_Rating = CAST(AVG(1.0 * Rating) AS DECIMAL(3,2))
FROM V_Mgmt_Reviews
GROUP BY YEAR(Review_Date)
ORDER BY [Year];
-- צפוי: 2024 -> 1110 / 3.59 ,  2025 -> 775 / 3.63
GO
