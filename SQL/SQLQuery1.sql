-- Customer Analysis ---------------------------------------------------
-- RFM -----------------------------------------------------------------
 With RFM as (
select
	a.customer_unique_id ,
	count(DISTINCT b.order_id) As Frequency,
	CAST(sum(c.price ) AS DECIMAL(18,2)) as Monetary,
	Max(Max(b.order_purchase_timestamp))over() as Last_Date,
	MAX(b.order_purchase_timestamp) as Last_Purchase
from Customers a join orders b
on a.customer_id = b.customer_id
join orders_items c
on b.order_id = c.order_id
where b.order_status = 'delivered'
group by a.customer_unique_id
),Recency_CTE as(
Select *,DATEDIFF(DAY,Last_Purchase,Last_Date) as Recency From RFM
),Scores AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY Recency DESC) AS R,
        CASE WHEN Frequency = 1 THEN 1
             WHEN Frequency = 2 THEN 3
             ELSE 5 END                       AS F,
        NTILE(5) OVER (ORDER BY Monetary ASC) AS M
    FROM Recency_CTE
),Segmants as(
SELECT *,
    CASE
        WHEN R >= 4 AND F >= 4 THEN 'Champions'
        WHEN R = 1  AND F >= 4 THEN 'Cant Lose Them'
        WHEN R <= 2 AND F >= 3 THEN 'At Risk'
        WHEN F >= 4            THEN 'Loyal'
        WHEN R >= 3 AND F = 3  THEN 'Potential Loyalist'
        WHEN R >= 4 AND F = 1  THEN 'New Customers'
        WHEN R = 3  AND F = 1  THEN 'Promising'
        WHEN R = 2             THEN 'About to Sleep'
        WHEN R = 1             THEN 'Churn'
        ELSE 'Other'
    END AS Segment
FROM Scores
)
select *,case
when Segment ='Champions' then 1
when Segment='Loyal' then 2
when Segment='Potential Loyalist' then 3
when Segment= 'Cant Lose Them' then 4
when Segment= 'Promising' then 5
when Segment='New Customers' then 6
when Segment= 'About to Sleep' then 7
when Segment='At Risk' then 8
when Segment='Churn' then 9
Else 10 End As Ranking
from Segmants;

-------------------------------------------------------------------------------
-- Retention ------------------------------------------------------------------
WITH Orders_Clean AS (
select C.customer_unique_id,
         DATEFROMPARTS(YEAR(O.order_purchase_timestamp),
         MONTH(O.order_purchase_timestamp), 1) AS Order_Month
from Customers C join orders O
on C.customer_id = O.customer_id
where O.order_status ='delivered'
),
Cohort AS (
    SELECT *,
      MIN(Order_Month)over(partition by customer_unique_id) AS Cohort_Month
    FROM Orders_Clean
),
Months AS (
    SELECT *,
        DATEDIFF(MONTH, Cohort_Month, Order_Month) AS Month_Number
    FROM Cohort
),
Agg AS (
    SELECT
        Cohort_Month,
        Month_Number,
        COUNT(DISTINCT customer_unique_id) AS Customers
    FROM Months
    GROUP BY Cohort_Month, Month_Number
)
SELECT
    Cohort_Month,
    Month_Number,
    Customers,
    CAST(100.0 * Customers /FIRST_VALUE(Customers) 
         OVER (PARTITION BY Cohort_Month  ORDER BY Month_Number)
         AS DECIMAL(5,2)) AS Retention_Pct
FROM Agg;
-------------------------------------------------------------------------------
-- Repeat Purchers Rate -------------------------------------------------------
WITH Cust AS (
    SELECT
        C.customer_unique_id,
        COUNT(DISTINCT O.order_id) AS Orders_Count
    FROM Customers C
    JOIN orders O ON C.customer_id = O.customer_id
    WHERE O.order_status = 'delivered'
    GROUP BY C.customer_unique_id
)
SELECT
    COUNT(*) AS Total_Customers,
    SUM(CASE WHEN Orders_Count >= 2 THEN 1 ELSE 0 END) AS Repeat_Customers,
    CAST(100.0 * SUM(CASE WHEN Orders_Count >= 2 THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS Repeat_Rate_Pct
FROM Cust;
---------------------------------------------------------------------------------
-- Monthely Growth value --------------------------------------------------------
WITH Monthly AS (
    SELECT
        DATEFROMPARTS(YEAR(O.order_purchase_timestamp),
                      MONTH(O.order_purchase_timestamp), 1) AS Order_Month,
        SUM(OI.price) AS Revenue,
       count(Distinct O.order_id) AS  Total_Orders
    FROM orders O
    JOIN orders_items OI ON O.order_id = OI.order_id
    WHERE O.order_status = 'delivered'
    GROUP BY DATEFROMPARTS(YEAR(O.order_purchase_timestamp),
                           MONTH(O.order_purchase_timestamp), 1)
)
SELECT *,
      (Revenue / Total_Orders )AS AOV,
   (Revenue-lag(Revenue)over(order by Order_Month))*100
   /Nullif(lag(Revenue)over(order by Order_Month),0) AS MoM_Growth_Pct
FROM Monthly;
---------------------------------------------------------------------------------
-- Delivery vs Review -----------------------------------------------------------
With Delivery as(
select O.order_id,
       Datediff(DAY,O.order_estimated_delivery_date
       ,O.order_delivered_customer_date) AS Delay_days
from orders O
where O.order_status ='delivered'
and O.order_delivered_customer_date is not null
),Reviews as(
select order_id,
       AVG(1.0 *review_score) As Order_Score
from orders_reviews ORV
group by order_id
),Bucketed as(
select D.order_id, R.Order_Score,
case
when D.Delay_days < 0  then '1 - Early'
when D.Delay_days = 0  then '2 - On Time'
when D.Delay_days <= 3 then '3 - Late 1-3 days'
when D.Delay_days <= 7 then '4 - Late 4-7 days'
else '5 - Late 7+ days' end As Delay_Bucket
from Delivery D join Reviews R
on D.order_id = R.order_id
)
select Delay_Bucket,
       Count(*) as Total_Orders,
       Cast(AVG(Order_Score) as Decimal(4,2)) as [ARS]
from Bucketed
group by Delay_Bucket;
---------------------------------------------------------------------------------
-- Category Analysis ------------------------------------------------------------
WITH Cat AS (
    SELECT
        COALESCE(P.category_english, 'Unknown') AS Category,
        SUM(OI.price)                           AS Category_Revenue
    FROM orders_items OI
    JOIN orders   O ON OI.order_id   = O.order_id
    JOIN products P ON OI.product_id = P.product_id
    WHERE O.order_status = 'delivered'
    GROUP BY COALESCE(P.category_english, 'Unknown')
),
Pct AS (
    SELECT *,
        100.0 * Category_Revenue / SUM(Category_Revenue) OVER() AS PCT
    FROM Cat
)
SELECT
    Category,
    CAST(Category_Revenue AS DECIMAL(18,2)) AS Category_Revenue,
    CAST(PCT AS DECIMAL(5,3))               AS PCT,
    CAST(SUM(PCT) OVER (ORDER BY Category_Revenue DESC
                        ROWS UNBOUNDED PRECEDING) AS DECIMAL(5,2)) AS Cumulative_PCT
FROM Pct;
---------------------------------------------------------------------------------
-- Geographic -------------------------------------------------------------------
With Reviews as(
select order_id,
       AVG(1.0 * review_score) as Order_Score
from orders_reviews
group by order_id
),State_Orders as(
select C.customer_state,
       C.customer_unique_id,
       O.order_id,
       SUM(OI.price) as Order_Revenue,
       case when DATEDIFF(DAY,O.order_estimated_delivery_date
            ,O.order_delivered_customer_date) > 0 then 1 else 0 end as Is_Late
from Customers C join orders O
on C.customer_id = O.customer_id
join orders_items OI
on O.order_id = OI.order_id
where O.order_status = 'delivered'
group by C.customer_state, C.customer_unique_id, O.order_id,
         O.order_estimated_delivery_date, O.order_delivered_customer_date
)
select S.customer_state,
       Count(distinct S.customer_unique_id) as Customers,
       Cast(Sum(S.Order_Revenue) as Decimal(18,2)) as Revenue,
       Cast(Sum(S.Order_Revenue) / Count(distinct S.customer_unique_id) as Decimal(18,2)) as Revenue_Per_Customer,
       Cast(100.0 * Sum(S.Order_Revenue) / Sum(Sum(S.Order_Revenue)) over() as Decimal(5,2)) as Revenue_Pct,
       Cast(AVG(R.Order_Score) as Decimal(4,2)) as Avg_Score,
       Cast(100.0 * AVG(1.0 * S.Is_Late) as Decimal(5,2)) as Late_Pct
from State_Orders S left join Reviews R
on S.order_id = R.order_id
group by S.customer_state
order by Revenue desc;
---------------------------------------------------------------------------------
-- Seller Analysis --------------------------------------------------------------
WITH Reviews AS (
select order_id,
Avg(1.0 * review_score) AS Order_Score
From orders_reviews
Group by order_id
),
Seller_Orders AS (
SELECT
    OI.seller_id,
    O.order_id,
    SUM(OI.price) AS Order_Revenue,
    CASE WHEN DATEDIFF(DAY, O.order_estimated_delivery_date,
     O.order_delivered_customer_date) > 0 THEN 1 ELSE 0 END AS Is_Late
FROM orders_items OI
JOIN orders O ON OI.order_id = O.order_id
WHERE O.order_status = 'delivered'
GROUP BY OI.seller_id, O.order_id,O.order_estimated_delivery_date,
 O.order_delivered_customer_date
)
SELECT
    S.seller_id,
    SL.seller_state,
    COUNT(*) AS Orders,
    CAST(SUM(S.Order_Revenue) AS DECIMAL(18,2)) AS Revenue,
    CAST(AVG(R.Order_Score) AS DECIMAL(4,2)) AS Avg_Score,
    CAST(100.0 * AVG(1.0 * S.Is_Late) AS DECIMAL(5,2)) AS Late_Pct
FROM Seller_Orders S
JOIN sellers SL ON S.seller_id = SL.seller_id
LEFT JOIN Reviews R ON S.order_id = R.order_id
GROUP BY S.seller_id, SL.seller_state
HAVING COUNT(*) >= 30
ORDER BY Revenue DESC;
---------------------------------------------------------------------------------
-- Payment ----------------------------------------------------------------------
With Pay as(
select order_id, payment_type,
       sum(payment_value) as Pay_Value
from orders_payments
group by order_id, payment_type
)
select P.payment_type,
       Count(distinct P.order_id) as Orders,
       Cast(Sum(P.Pay_Value) as Decimal(18,2)) as Total_Value,
       Cast(Avg(P.Pay_Value) as Decimal(18,2)) as Avg_Value,
       Cast(100.0 * Count(distinct P.order_id)
            / Sum(Count(distinct P.order_id)) over() as Decimal(5,2)) as Orders_Pct
from Pay P join orders O
on P.order_id = O.order_id
where O.order_status = 'delivered'
group by P.payment_type
order by Orders desc;
---------------------------------------------------------------------------------
-- Payment ----------------------------------------------------------------------
With Inst as(
select order_id,
       Max(payment_installments) as Installments,
       sum(payment_value) as Pay_Value
from orders_payments
group by order_id
)
select case
       when I.Installments = 1 then '1 - Single'
       when I.Installments <= 3 then '2 - 2 to 3'
       when I.Installments <= 6 then '3 - 4 to 6'
       else '4 - 7+' end as Installment_Bucket,
       Count(*) as Orders,
       Cast(Avg(I.Pay_Value) as Decimal(18,2)) as Avg_Order_Value
from Inst I join orders O
on I.order_id = O.order_id
where O.order_status = 'delivered'
group by case
       when I.Installments = 1 then '1 - Single'
       when I.Installments <= 3 then '2 - 2 to 3'
       when I.Installments <= 6 then '3 - 4 to 6'
       else '4 - 7+' end
order by Installment_Bucket;
---------------------------------------------------------------------------------
-- Freight ----------------------------------------------------------------------
With Freight_Orders as(
select C.customer_state,
       O.order_id,
       Sum(OI.price) as Price,
       Sum(OI.freight_value) as Freight
from Customers C join orders O
on C.customer_id = O.customer_id
join orders_items OI
on O.order_id = OI.order_id
where O.order_status = 'delivered'
group by C.customer_state, O.order_id
)
select customer_state,
       Count(*) as Orders,
       Cast(Sum(Price) as Decimal(18,2)) as Total_Price,
       Cast(Sum(Freight) as Decimal(18,2)) as Total_Freight,
       Cast(100.0 * Sum(Freight) / Sum(Price) as Decimal(5,2)) as Freight_Pct,
       Cast(Avg(Freight) as Decimal(18,2)) as Avg_Freight
from Freight_Orders
group by customer_state
order by Freight_Pct desc;
---------------------------------------------------------------------------------
-- Historical CLV ---------------------------------------------------------------
With Cust_Orders as(
select C.customer_unique_id,
       O.order_id,
       Sum(OI.price) as Order_Revenue
from Customers C join orders O
on C.customer_id = O.customer_id
join orders_items OI
on O.order_id = OI.order_id
where O.order_status = 'delivered'
group by C.customer_unique_id, O.order_id
)
select customer_unique_id,
       Count(*) as Orders,
       Cast(Sum(Order_Revenue) as Decimal(18,2)) as CLV,
       Cast(Avg(Order_Revenue) as Decimal(18,2)) as AOV
from Cust_Orders
group by customer_unique_id
order by Orders Desc;