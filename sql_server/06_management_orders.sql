/* =====================================================================
   קובץ 8: Views לדשבורד ההנהלה
   ---------------------------------------------------------------------
   V_Mgmt_Orders: שורה לכל הזמנה, עם כל מה שהדשבורד צריך:
   תאריך, חוויה, קטגוריה, עיר, מארח (מייל + שם) והכנסה.
   ככה כל גרף (כרטיסים, קו לפי חודש, עמודות לפי עיר, מארחים מובילים)
   נבנה מאותה טבלה, וסלייסר השנה והקטגוריה מסננים את כולם.

   מארח מזוהה לפי המייל (המפתח), והשם משמש רק לתצוגה.
   אם בעתיד למארח יהיו כמה חוויות, הסכום לפי מארח יחבר אותן לבד.

   מריצים פעם אחת: F5 בלי לסמן כלום.
   ===================================================================== */
USE AirbnbPortfolio;
GO

CREATE OR ALTER VIEW V_Mgmt_Orders AS
SELECT
    O.OrderID,
    Order_Date      = CAST(O.OrderDT AS DATE),
    Experience_Name = E.Name,
    Category        = E.Category,
    City            = E.Location,
    Host_Email      = E.Host,
    Host_Name       = U.FirstName + ' ' + U.LastName,
    Participants    = O.ParticipantsNumber,
    Revenue         = O.ParticipantsNumber * E.Price
FROM ORDERS AS O
JOIN EXPERIENCES AS E ON O.SessionName = E.Name
LEFT JOIN USERS  AS U ON U.Email = E.Host;
GO

/* ---------- בדיקה ---------- */
SELECT Orders = COUNT(*), Revenue = SUM(Revenue) FROM V_Mgmt_Orders;
-- צפוי: 669 / 163,598

SELECT TOP 5 Host_Name, Experiences = COUNT(DISTINCT Experience_Name), Revenue = SUM(Revenue)
FROM V_Mgmt_Orders
GROUP BY Host_Email, Host_Name
ORDER BY Revenue DESC;
-- צפוי: המארח הראשון עם 10,350, ולכל אחד חוויה אחת
GO
