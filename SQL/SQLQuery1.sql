--------------------------------------------------------------------------------------------
--  RFM + Customer Lifetime Value (CLV) ----------------------------------------------------
--------------------------------------------------------------------------------------------


WITH MaxDate AS (
    SELECT MAX(order_purchase_timestamp) AS max_date
    FROM orders
    WHERE order_status NOT IN ('canceled', 'unavailable')
),

RFM AS (
    SELECT 
        a.customer_unique_id,
        COUNT(DISTINCT b.order_id) AS Frequencey,
        SUM(COALESCE(p.payment_value, 0)) AS monitry,  
        MAX(b.order_purchase_timestamp) AS lastorder
    FROM customers a 
    LEFT JOIN orders b ON a.customer_id = b.customer_id
    JOIN order_items c ON b.order_id = c.order_id
    JOIN order_payments p ON b.order_id = p.order_id  
    WHERE b.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY a.customer_unique_id
),

Recencyy AS (
    SELECT 
        *,
        DATEDIFF(DAY, lastorder, (SELECT max_date FROM MaxDate)) AS Recency  
    FROM RFM
),

Segments AS (
    SELECT 
        *,
        CASE 
            WHEN Recency > 90 THEN 1
            WHEN Recency > 60 THEN 2
            WHEN Recency > 40 THEN 3 
            WHEN Recency > 20 THEN 4
            ELSE 5 
        END AS R,
        CASE 
            WHEN Frequencey > 10 THEN 5
            WHEN Frequencey > 6 THEN 4
            WHEN Frequencey > 3 THEN 3
            WHEN Frequencey > 1 THEN 2
            ELSE 1 
        END AS F,
        NTILE(5) OVER (ORDER BY monitry) AS M
    FROM Recencyy
),

RFM_Final AS (
    SELECT     
        customer_unique_id,
        monitry,
        Frequencey,
        Recency,
        R,
        F,
        M,
        CONCAT(R, F, M) AS RFM_Score,
        CASE
            WHEN R >= 4 AND F >= 4 AND M >= 4 THEN 'Champions'
            WHEN R >= 3 AND F >= 3 AND M >= 3 THEN 'Loyal Customers'
            WHEN R >= 4 AND F <= 2 THEN 'New Customers'
            WHEN R <= 2 AND F >= 4 THEN 'At Risk'
            WHEN R = 3 AND F >= 3 THEN 'Potential Loyalists'  
            WHEN R = 3 AND F <= 2 THEN 'Need Attention'
            WHEN R <= 2 AND F <= 2 THEN 'Hibernating'
            ELSE 'Others'
        END AS Segment
    FROM Segments
),

Customer_Summary AS (
    SELECT 
        a.customer_unique_id,
        COUNT(DISTINCT b.order_id) AS total_orders,
        SUM(p.payment_value) AS total_spent,                              
        SUM(p.payment_value) / COUNT(DISTINCT b.order_id) AS avg_order_value,  
        DATEDIFF(DAY, MIN(b.order_purchase_timestamp), MAX(b.order_purchase_timestamp)) AS customer_lifetime_days
    FROM customers a 
    JOIN orders b ON a.customer_id = b.customer_id
    JOIN order_items c ON b.order_id = c.order_id
    JOIN order_payments p ON b.order_id = p.order_id  
    WHERE b.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY a.customer_unique_id
),

Customer_Frequency AS (
    SELECT 
        customer_unique_id,
        total_orders,
        total_spent,
        avg_order_value,
        customer_lifetime_days,
        CASE 
            WHEN customer_lifetime_days = 0 THEN 1.0 
            ELSE customer_lifetime_days 
        END AS safe_lifetime_days,
        total_orders / (CASE WHEN customer_lifetime_days = 0 THEN 1.0 ELSE customer_lifetime_days END / 365.0) AS annual_frequency
    FROM Customer_Summary
),

Lifespan_Avg AS (
    SELECT AVG(customer_lifetime_days) / 365.0 AS avg_lifespan_years
    FROM Customer_Summary
),

CLV_Individual AS (
    SELECT 
        cf.customer_unique_id,
        ROUND(cf.avg_order_value, 2) AS avg_order_value,
        ROUND(cf.annual_frequency, 2) AS annual_frequency,
        ROUND(la.avg_lifespan_years, 2) AS avg_expected_lifespan_years,
        ROUND(cf.avg_order_value * cf.annual_frequency * la.avg_lifespan_years, 2) AS predicted_clv
    FROM Customer_Frequency cf
    CROSS JOIN Lifespan_Avg la
)

SELECT 
    r.Segment,
    COUNT(DISTINCT r.customer_unique_id) AS number_of_customers,
    ROUND(AVG(c.predicted_clv), 2) AS avg_clv_per_customer,
    ROUND(SUM(c.predicted_clv), 0) AS total_clv_for_segment,
    ROUND(AVG(c.avg_order_value), 2) AS avg_order_value,
    ROUND(AVG(c.annual_frequency), 2) AS avg_annual_frequency,
    ROUND(100.0 * COUNT(DISTINCT r.customer_unique_id) / SUM(COUNT(DISTINCT r.customer_unique_id)) OVER(), 2) AS pct_of_customers
FROM RFM_Final r
LEFT JOIN CLV_Individual c ON r.customer_unique_id = c.customer_unique_id
GROUP BY r.Segment
ORDER BY avg_clv_per_customer DESC;
----------------------------------------------------------------
--Customer behavior - Cohort Analysis --------------------
----------------------------------------------------------------
 WITH 
first_purchase AS (
    SELECT 
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),

cohort_info AS (
    SELECT 
        customer_unique_id,
        YEAR(first_order_date)  AS cohort_year,
        MONTH(first_order_date) AS cohort_month
    FROM first_purchase
),

customer_activity AS (
    SELECT DISTINCT
        c.customer_unique_id,
        YEAR(o.order_purchase_timestamp)  AS activity_year,
        MONTH(o.order_purchase_timestamp) AS activity_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),

activity_periods AS (
    SELECT 
        a.customer_unique_id,
        ch.cohort_year,
        ch.cohort_month,
        (a.activity_year * 12 + a.activity_month) 
        - (ch.cohort_year * 12 + ch.cohort_month) 
        AS months_since_first_purchase
    FROM customer_activity a
    JOIN cohort_info ch 
        ON a.customer_unique_id = ch.customer_unique_id
),

cohort_summary AS (
    SELECT 
        cohort_year,
        cohort_month,
        months_since_first_purchase,
        COUNT(DISTINCT customer_unique_id) AS active_customers_count
    FROM activity_periods
    GROUP BY 
        cohort_year, 
        cohort_month, 
        months_since_first_purchase
),

cohort_base_size AS (
    SELECT 
        cohort_year,
        cohort_month,
        active_customers_count AS total_customers_in_cohort
    FROM cohort_summary
    WHERE months_since_first_purchase = 0
)

SELECT 
    c.cohort_year,
    c.cohort_month,
    c.months_since_first_purchase,
    c.active_customers_count,
    b.total_customers_in_cohort,
    
    CAST(c.active_customers_count AS DECIMAL(10,2)) 
        / NULLIF(b.total_customers_in_cohort, 0) 
        * 100 AS retention_rate_pct
        
FROM cohort_summary c
LEFT JOIN cohort_base_size b 
    ON c.cohort_year = b.cohort_year 
    AND c.cohort_month = b.cohort_month

ORDER BY 
    c.cohort_year, 
    c.cohort_month, 
    c.months_since_first_purchase;
------------------------------------------------------------------
-- Customer behavior - Churn Rate --------------------------------
------------------------------------------------------------------
WITH last_purchase AS(
    SELECT 
        a.Customer_unique_id, 
        MAX(b.order_purchase_timestamp) AS [last_order] 
    FROM customers a 
    JOIN orders b ON a.Customer_id = b.Customer_id 
    where b.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY a.Customer_unique_id
),
Day_Diff AS(
    SELECT *,
           DATEDIFF(DAY, [last_order], 
               (SELECT MAX(order_purchase_timestamp) 
                FROM orders
                WHERE order_status NOT IN ('canceled', 'unavailable'))) AS [Date_Dif] 
    FROM last_purchase
),
classified AS (
    SELECT *,
           CASE WHEN [Date_Dif] > 180 THEN 'Churn'
                ELSE 'Active' END AS [Churn_or_Active]
    FROM Day_Diff
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN [Date_Dif] > 180 THEN 1 ELSE 0 END) AS churned_customers,
    SUM(CASE WHEN [Date_Dif] <= 180 THEN 1 ELSE 0 END) AS active_customers,
    
    CAST(SUM(CASE WHEN [Date_Dif] > 180 THEN 1 ELSE 0 END) AS DECIMAL(10,2)) 
        / NULLIF(COUNT(*), 0) * 100 AS churn_rate_pct
FROM classified;
--------------------------------------------------------------------------------------
--Customer behavior -  Repeat Purchase Interval --------------------------------------
--------------------------------------------------------------------------------------
with Next_date as (
select 
      a.customer_unique_id,b.order_purchase_timestamp,LEAD(b.order_purchase_timestamp)
    over(PARTITION BY a.customer_unique_id order by b.order_purchase_timestamp) as next_order
from customers a join orders b on a.customer_id=b.customer_id
where b.order_status NOT IN ('canceled', 'unavailable')
),DIff_Date as(
select *,
    Datediff(Day,order_purchase_timestamp,next_order) as days_between_orders
from Next_date
where next_order is not null
)
select 
    customer_unique_id,
    AVG(days_between_orders) as avg_days_between_orders
from DIff_Date
where days_between_orders <> 0
group by customer_unique_id
order by avg_days_between_orders
----------------------------------------------------------------------------------------------
--customer behavior - First vs Repeat Orders -------------------------------------------------
----------------------------------------------------------------------------------------------
WITH Ranked_Orders AS (
    SELECT 
        a.customer_unique_id,
        b.order_id,
        b.order_purchase_timestamp,
        ROW_NUMBER() OVER (PARTITION BY a.customer_unique_id ORDER BY b.order_purchase_timestamp) AS order_rank
    FROM customers a 
    JOIN orders b ON a.customer_id = b.customer_id
    WHERE b.order_status NOT IN ('canceled', 'unavailable')
),
First_Order_Price AS (
    SELECT 
        ro.customer_unique_id,
        SUM(oi.price) AS first_price
    FROM Ranked_Orders ro
    JOIN order_items oi ON ro.order_id = oi.order_id
    WHERE ro.order_rank = 1
    GROUP BY ro.customer_unique_id
),
Total_Price AS (
    SELECT 
        a.customer_unique_id,
        SUM(oi.price) AS all_price
    FROM customers a 
    JOIN orders b ON a.customer_id = b.customer_id
    JOIN order_items oi ON b.order_id = oi.order_id
    WHERE b.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY a.customer_unique_id
)
SELECT 
    f.customer_unique_id,
    f.first_price,
    t.all_price,
    (t.all_price - f.first_price) AS repeat_price
FROM First_Order_Price f
JOIN Total_Price t ON f.customer_unique_id = t.customer_unique_id
ORDER BY repeat_price DESC; 
----------------------------------------------------------------------------------------------
-- Market Basket Analysis --------------------------------------------------------------------
----------------------------------------------------------------------------------------------

with totla_orders as (
select count(distinct order_id) as[Total orders] from order_items
), products_freq as(
select 
    product_id,
    count(distinct order_id) as [products_frq]
from order_items
group by product_id
),products_pair as(
    select
    a.product_id as [first product],
    b.product_id as [secound product],
    count (distinct a.order_id)as [pair_frequency]
    from order_items a join order_items b 
    on a.order_id = b.order_id
    where a.product_id<b.product_id
    group by a.product_id,b.product_id
    having COUNT(distinct a.order_id)>=10
)
select
    pp.[first product],
    pp.[secound product],
    pp.pair_frequency as orders_together,
    ROUND(100.0 * pp.pair_frequency / t.[Total orders], 2) AS Support_Percentage,
    ROUND(100.0 * pp.pair_frequency / pf1.[products_frq], 2) AS Confidence_1_to_2,
     ROUND(
        (pp.pair_frequency * 1.0 / pf1.[products_frq]) / 
        (pf2.[products_frq] * 1.0 / t.[Total orders])
    , 2) AS Lift_Score
from products_pair pp cross join totla_orders t
join products_freq pf1 on pp.[first product]=pf1.product_id
join products_freq pf2 on pp.[secound product]=pf2.product_id
order by Lift_Score desc
------------------------------------------------------------------------------
--Seasonality by Category-----------------------------------------------------
------------------------------------------------------------------------------
with Orders_With_Category as(
select a.order_id,
    a.order_purchase_timestamp,
    YEAR(a.order_purchase_timestamp) as[year],
    Month(a.order_purchase_timestamp) as[month],
    COALESCE(c.product_category_name,'Unknowen') as [product category]
from orders a join order_items b 
on a.order_id =b.order_id
join products c on b.product_id=c.product_id
WHERE a.order_status NOT IN ('canceled', 'unavailable')
AND YEAR(a.order_purchase_timestamp) IN (2016, 2017)
),Monthly_Category_Summary AS (
    SELECT 
        year,
        month,
        [product category],
        COUNT(DISTINCT order_id) AS total_orders  
    FROM Orders_With_Category
    GROUP BY year, month, [product category]
),Top_Categories AS (
    SELECT TOP 10
        [product category],
        SUM(total_orders) AS total_sales
    FROM Monthly_Category_Summary
    GROUP BY [product category]
    ORDER BY total_sales DESC
)SELECT 
    m.year,
    m.month,
    m.[product category],
    m.total_orders
FROM Monthly_Category_Summary m
JOIN Top_Categories t ON m.[product category] = t.[product category]
ORDER BY m.[product category], m.year,m.month
----------------------------------------------------------------------------------------
--Installments Impact-------------------------------------------------------------------
----------------------------------------------------------------------------------------
select 
    b.payment_installments,
    count(distinct a.order_id) as total_orders,
    avg(b.payment_value) as avg_order_value,  
    sum(b.payment_value) as total_revenue
from orders a join order_payments b on a.order_id=b.order_id
where a.order_status NOT IN ('canceled', 'unavailable')
group by b.payment_installments
order by  total_revenue desc
----------------------------------------------------------------------------------------
--Payment Method Preference-------------------------------------------------------------
----------------------------------------------------------------------------------------
with cte as (select 
    a.payment_type,
    c.customer_state,
    count(distinct b.order_id) as total_orders
from order_payments a join orders b on a.order_id=b.order_id
join customers c on b.customer_id=c.customer_id
where b.order_status NOT IN ('canceled', 'unavailable')
group by a.payment_type,c.customer_state
), cte2 as(select
    b.customer_state,
    count(distinct order_id) as totaly 
from orders a join customers b 
on a.customer_id=b.customer_id
where a.order_status NOT IN ('canceled', 'unavailable')
group by b.customer_state
) , final as (
select 
    cte.payment_type,
    cte.customer_state,
    cte.total_orders,
    cte2.totaly as total_state_orders,  
    
    ROUND(100.0 * cte.total_orders / cte2.totaly, 2) as pct_within_state
from cte 
join cte2 on cte.customer_state = cte2.customer_state  
)
select 
    customer_state,
    max(case when payment_type = 'credit_card' then pct_within_state else 0 end) as Credit_Card_Pct,
    max(case when payment_type = 'boleto' then pct_within_state else 0 end) as Boleto_Pct,
    max(case when payment_type = 'voucher' then pct_within_state else 0 end) as Voucher_Pct,
    max(case when payment_type = 'debit_card' then pct_within_state else 0 end) as Debit_Card_Pct
from final
group by customer_state
order by customer_state;
----------------------------------------------------------------------------------------
--Cancellation Root Cause Analysis------------------------------------------------------
----------------------------------------------------------------------------------------

with 
state_totals as (
    select 
        c.customer_state,
        count(distinct o.order_id) as total_orders_in_state
    from orders o
    join customers c on o.customer_id = c.customer_id
    where o.order_status in ('delivered', 'shipped', 'processing', 'canceled')
    group by c.customer_state
),

order_cancellations as (
    select 
        c.customer_state,
        o.order_id,
        case 
            when o.order_status = 'canceled' 
                 and o.order_approved_at is null 
                 then 'Payment_Failure (Boleto/Bank)'
                 
            when o.order_status in ('canceled' , 'unavailable')
                 and o.order_approved_at is not null 
                 and o.order_delivered_carrier_date is null 
                 then 'Seller_Stock_Issue'
                 
            when o.order_status = 'canceled' 
                 and o.order_approved_at is not null 
                 and o.order_delivered_carrier_date is not null 
                 then 'Logistics_Delay_OR_Customer_Refusal'
                 
            else 'Not_Canceled'
        end as cancellation_category
    from orders o
    join customers c on o.customer_id = c.customer_id
    where o.order_status in ('delivered', 'shipped', 'processing', 'canceled')
)
select 
    o.customer_state,
    o.cancellation_category,
    count(distinct o.order_id) as canceled_orders_for_this_reason,
    round(100.0 * count(distinct o.order_id) / 
          sum(count(distinct o.order_id)) over (partition by o.customer_state), 2) as pct_of_cancellations,
    round(100.0 * count(distinct o.order_id) / 
          max(st.total_orders_in_state), 2) as cancellation_rate_vs_total_orders

from order_cancellations o
join state_totals st on o.customer_state = st.customer_state
where o.cancellation_category <> 'Not_Canceled'
group by o.customer_state, o.cancellation_category, st.total_orders_in_state
order by cancellation_rate_vs_total_orders desc
----------------------------------------------------------------------------------------
-- Top Rated Products ------------------------------------------------------------------
----------------------------------------------------------------------------------------
with product_reviews as (
    select 
        b.product_id,
        avg(cast(a.review_score as decimal(10,2))) as avg_review_score,
        count(distinct a.order_id) as total_reviews
    from order_reviews a 
    join order_items b on a.order_id = b.order_id
    group by b.product_id
), final as(
select
    b.product_category_name,
    a.product_id ,
    a.avg_review_score,
    a.total_reviews,
    case 
        when avg_review_score >= 4.5 and total_reviews >= 100 then ' Gold '
        when avg_review_score >= 4.0 and total_reviews >= 50  then ' Silver '
        when avg_review_score >= 3.5 and total_reviews >= 30  then ' Bronze'
        else ' Low Quality '
    end as recommendation
from product_reviews a join products b on a.product_id=b.product_id
)
select * from final
WHERE total_reviews >= 30 
  AND (recommendation = ' Gold ' OR recommendation = ' Silver ')
  order by avg_review_score desc, total_reviews desc
----------------------------------------------------------------------------------------
-- Top Rated Sellers -------------------------------------------------------------------
----------------------------------------------------------------------------------------
with seller_metrics as (
    select 
        a.seller_id,
        avg(cast(b.review_score as decimal(10,2))) as avg_review_score,
        count(distinct a.order_id) as total_reviews,
        count(distinct a.product_id) as total_products
    from order_items a 
    join order_reviews b on a.order_id = b.order_id
    group by a.seller_id
) ,finaly as(
select 
    seller_id,
    avg_review_score,
    total_reviews,
    total_products,
    case 
        when avg_review_score >= 4.5 and total_reviews >= 250 then ' Platinum'
        when avg_review_score >= 4.0 and total_reviews >= 100  then ' Gold'
        when avg_review_score >= 3.5 and total_reviews >= 50  then 'Silver'
        else 'Needs Review'
    end as seller_rank
from seller_metrics
)
select top 25 * from finaly
WHERE total_reviews >= 20 
  AND (seller_rank = ' Platinum' OR seller_rank = ' Gold')
  order by total_reviews desc,Seller_rank desc 
-------------------------------------------------------------------------------------
--Seller Revenue Ranking--------------------------------------------------------
-------------------------------------------------------------------------------------
with seller_revenue as (
    select 
        oi.seller_id,
        sum(oi.price) as total_revenue,
        count(distinct oi.order_id) as total_orders,
        round(sum(oi.price) / count(distinct oi.order_id), 2) as avg_order_value
    from order_items oi
    join orders o on oi.order_id = o.order_id
    where o.order_status NOT IN ('canceled', 'unavailable')
      and oi.seller_id is not null
    group by oi.seller_id
), Ranking as(
            select *,
                dense_rank() over(order by total_revenue desc) as revenue_rank
            from seller_revenue
)
select 
    seller_id,
    total_revenue,
    total_orders,
    avg_order_value,
    case 
        when total_revenue >= 80000 then ' Mega Seller '
        when total_revenue >= 60000 then ' Top Seller '
        when total_revenue >= 10000  then ' Growth Seller'
        else ' Small Seller '
    end as revenue_tier ,
    revenue_rank
from Ranking
where revenue_rank <= 25
order by revenue_rank 
-----------------------------------------------------------------------------------------------------
--Seller Delivery Performance------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------
select
    c.seller_id,
    AVG(DATEDIFF(DAY, a.order_purchase_timestamp, a.order_delivered_customer_date)) as [AVG Delivery Performance],
    AVG(datediff(DAY,a.order_estimated_delivery_date,a.order_delivered_customer_date)) as [order delay],
    ROUND(100.0 * SUM(CASE WHEN a.order_delivered_customer_date > a.order_estimated_delivery_date THEN 1 ELSE 0 END) 
    / COUNT(DISTINCT a.order_id),2) AS late_delivery_percentage
from orders a join order_items b on a.order_id=b.order_id
join olist_sellers_dataset c on b.seller_id=c.seller_id
where a.order_status= 'delivered'
group by c.seller_id
order by [AVG Delivery Performance] desc
---------------------------------------------------------------------------------------------------------------------------------------
-- Seller Growth & Activity -----------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT 
        c.seller_id,
        DATEFROMPARTS(YEAR(a.order_purchase_timestamp), MONTH(a.order_purchase_timestamp), 1) AS order_month,
        SUM(b.price) AS monthly_revenue,
        COUNT(DISTINCT a.order_id) AS monthly_orders
    FROM orders a 
    JOIN order_items b ON a.order_id = b.order_id
    JOIN olist_sellers_dataset c ON b.seller_id = c.seller_id
    WHERE a.order_status = 'delivered'
    GROUP BY 
        c.seller_id, 
        DATEFROMPARTS(YEAR(a.order_purchase_timestamp), MONTH(a.order_purchase_timestamp), 1)
),
growth_analysis AS (
    SELECT 
        seller_id,
        order_month,
        monthly_revenue,
        monthly_orders,
        LAG(monthly_revenue) OVER(PARTITION BY seller_id ORDER BY order_month) AS previous_month_revenue,
        MIN(order_month) OVER(PARTITION BY seller_id) AS first_active_month,
        MAX(order_month) OVER(PARTITION BY seller_id) AS last_active_month
    FROM monthly_revenue
)
SELECT 
    seller_id,
    first_active_month AS [First Order Month],
    last_active_month AS [Last Order Month],
    order_month AS [Current Month],
    monthly_revenue AS [Current Revenue],
    previous_month_revenue AS [Previous Revenue],
    monthly_orders as [Order Count],
    ROUND(monthly_revenue / NULLIF(monthly_orders, 0), 2) AS [Avg Order Value],
    CASE 
        WHEN previous_month_revenue IS NULL AND monthly_revenue > 0 THEN 'New Seller (First Month)'
        WHEN monthly_revenue > previous_month_revenue THEN 'Growing Seller'
        WHEN monthly_revenue < previous_month_revenue THEN 'Declining Seller'
        WHEN monthly_revenue = previous_month_revenue THEN 'Stable Seller'
        ELSE 'Inactive'
    END AS growth_status
FROM growth_analysis
WHERE monthly_revenue > 0 
ORDER BY seller_id, order_month;
